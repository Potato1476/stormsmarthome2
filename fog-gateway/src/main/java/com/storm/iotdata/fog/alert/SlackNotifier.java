package com.storm.iotdata.fog.alert;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.storm.iotdata.fog.anomaly.AnomalyResult;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * Delivers {@link Alert}s to Slack Incoming Webhooks using Block Kit messages,
 * routing each alert to its house's own channel via a {@link RouteRegistry} so a
 * household only sees alerts for its own devices.
 *
 * Design constraints (this runs inside a Storm bolt on a Raspberry-Pi-class node):
 *   - NEVER block the bolt thread on the network: sends run on a small bounded
 *     background pool; if the pool is saturated the alert is dropped (counted),
 *     never queued unbounded.
 *   - Self-throttle: a minimum interval between posts is enforced <em>per
 *     destination webhook</em>, so a noisy house never starves another house's
 *     channel (per-device cool-down is enforced upstream in the bolt).
 *   - Fail safe: an unconfigured registry is a silent no-op, not an error.
 *
 * Only depends on the JDK's HttpURLConnection + Gson (already on the classpath) —
 * no extra dependency, Java 8 compatible.
 */
public class SlackNotifier {

    private static final Gson GSON = new GsonBuilder().disableHtmlEscaping().create();
    private static final SimpleDateFormat TS_FMT = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    private final RouteRegistry registry;
    private final boolean enabled;
    private final long minIntervalMs;

    private final ThreadPoolExecutor pool;
    // Last post time per destination webhook -> per-channel throttle, not global.
    private final Map<String, Long> lastSentByUrl = new ConcurrentHashMap<>();

    // Lightweight observability — readable by the bolt for metrics/logging.
    private volatile long sent = 0L;
    private volatile long failed = 0L;
    private volatile long dropped = 0L;

    /** Route-aware: each alert is delivered to its house's channel (or the default). */
    public SlackNotifier(RouteRegistry registry, boolean enabled, long minIntervalMs) {
        this.registry = registry != null ? registry : RouteRegistry.fromJson("{}", "");
        this.enabled = enabled && !this.registry.isEmpty();
        this.minIntervalMs = Math.max(0, minIntervalMs);
        // Single worker, bounded queue: ordered delivery, predictable memory, drop-on-overflow.
        this.pool = new ThreadPoolExecutor(
                1, 1, 0L, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(256),
                r -> {
                    Thread t = new Thread(r, "slack-notifier");
                    t.setDaemon(true);
                    return t;
                },
                new ThreadPoolExecutor.AbortPolicy());
    }

    /** Back-compat / smoke-test: a single webhook used for every house. */
    public SlackNotifier(String webhookUrl, boolean enabled, long minIntervalMs) {
        this(RouteRegistry.fromJson("{}", webhookUrl), enabled, minIntervalMs);
    }

    public boolean isEnabled() { return enabled; }
    public long getSent()      { return sent; }
    public long getFailed()    { return failed; }
    public long getDropped()   { return dropped; }

    /**
     * Queue an alert for asynchronous delivery.
     * @return true if accepted for sending, false if disabled or the queue was full.
     */
    public boolean send(Alert alert) {
        if (!enabled) return false;
        try {
            pool.execute(() -> deliver(alert));
            return true;
        } catch (RuntimeException rejected) { // queue full
            dropped++;
            System.err.println("[SlackNotifier] queue full, dropped alert for " + alert.deviceKey());
            return false;
        }
    }

    private void deliver(Alert alert) {
        String webhookUrl = registry.resolve(alert.getHouseId());
        if (webhookUrl == null || webhookUrl.isEmpty()) {
            // House has no channel and no default — nothing to deliver to.
            dropped++;
            return;
        }
        // Per-destination self-throttle: space out posts to one channel so we never
        // trip Slack's rate limit, without one busy house blocking another's channel.
        if (minIntervalMs > 0) {
            long last = lastSentByUrl.getOrDefault(webhookUrl, 0L);
            long wait = minIntervalMs - (System.currentTimeMillis() - last);
            if (wait > 0) {
                try { Thread.sleep(wait); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            }
        }
        boolean ok = post(webhookUrl, buildPayload(alert));
        lastSentByUrl.put(webhookUrl, System.currentTimeMillis());
        if (ok) sent++; else failed++;
    }

    /** Blocking HTTP POST. Returns true on 2xx. */
    static boolean post(String webhookUrl, String jsonPayload) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(webhookUrl).openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);
            conn.setDoOutput(true);
            byte[] body = jsonPayload.getBytes(StandardCharsets.UTF_8);
            try (OutputStream os = conn.getOutputStream()) {
                os.write(body);
            }
            int code = conn.getResponseCode();
            if (code >= 200 && code < 300) return true;
            System.err.println("[SlackNotifier] Slack returned HTTP " + code);
            return false;
        } catch (Exception e) {
            System.err.println("[SlackNotifier] POST failed: " + e.getMessage());
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    /**
     * Build a Slack Block Kit message from an alert. Pure function (no I/O) so it
     * is unit-testable and reusable for other webhook-style channels.
     */
    static String buildPayload(Alert alert) {
        boolean critical = alert.getSeverity() == AnomalyResult.Severity.CRITICAL;
        String emoji = critical ? "🚨" : "⚠️";
        String sevLabel = critical ? "CRITICAL" : "WARNING";

        String header = String.format("%s [STORM-ALERT] %s — House #%d / Household %d / Plug %d",
                emoji, sevLabel, alert.getHouseId(), alert.getHouseholdId(), alert.getPlugId());

        StringBuilder detail = new StringBuilder();
        detail.append("*Reading:* ").append(fmtW(alert.getValue())).append('\n');
        detail.append("*Baseline (EWMA):* ").append(fmtW(alert.getBaseline())).append('\n');
        if ("Z_SCORE".equals(alert.getType())) {
            detail.append("*Deviation:* ").append(String.format("%.1fσ", alert.getZScore())).append('\n');
        }
        detail.append("*Why:* ").append(alert.getReason());

        String context = String.format("⏱ %s  |  Gateway: %s  |  Detector: %s",
                TS_FMT.format(new Date(alert.getTimestampMs())), alert.getGatewayId(), alert.getType());

        // Block Kit structure built as maps -> Gson handles all escaping.
        List<Object> blocks = new ArrayList<>();
        blocks.add(headerBlock(header));
        blocks.add(sectionBlock(detail.toString()));
        blocks.add(contextBlock(context));

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("text", header); // fallback for notifications/clients without Block Kit
        payload.put("blocks", blocks);
        return GSON.toJson(payload);
    }

    private static Map<String, Object> headerBlock(String text) {
        Map<String, Object> txt = new LinkedHashMap<>();
        txt.put("type", "plain_text");
        txt.put("text", text);
        txt.put("emoji", true);
        Map<String, Object> block = new LinkedHashMap<>();
        block.put("type", "header");
        block.put("text", txt);
        return block;
    }

    private static Map<String, Object> sectionBlock(String markdown) {
        Map<String, Object> txt = new LinkedHashMap<>();
        txt.put("type", "mrkdwn");
        txt.put("text", markdown);
        Map<String, Object> block = new LinkedHashMap<>();
        block.put("type", "section");
        block.put("text", txt);
        return block;
    }

    private static Map<String, Object> contextBlock(String text) {
        Map<String, Object> element = new LinkedHashMap<>();
        element.put("type", "mrkdwn");
        element.put("text", text);
        List<Object> elements = new ArrayList<>();
        elements.add(element);
        Map<String, Object> block = new LinkedHashMap<>();
        block.put("type", "context");
        block.put("elements", elements);
        return block;
    }

    private static String fmtW(double watts) {
        // No thousands separator: locale-independent and keeps the value greppable.
        return String.format("%.0f W", watts);
    }

    public void shutdown() {
        pool.shutdown();
    }

    /**
     * Standalone smoke test:
     *   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... \
     *   java -cp fog-gateway.jar com.storm.iotdata.fog.alert.SlackNotifier
     * Sends one synthetic CRITICAL alert and prints the HTTP result.
     */
    public static void main(String[] args) {
        String url = args.length > 0 ? args[0] : System.getenv("SLACK_WEBHOOK_URL");
        if (url == null || url.trim().isEmpty()) {
            System.err.println("Set SLACK_WEBHOOK_URL (env) or pass the webhook URL as arg[0].");
            System.exit(2);
        }
        AnomalyResult r = AnomalyResult.hardCeiling(2850.0, 2780.0, 2500.0);
        Alert test = new Alert("gw-smoke-test", 3, 1, 2, r, System.currentTimeMillis());
        System.out.println("Payload:\n" + buildPayload(test));
        boolean ok = post(url.trim(), buildPayload(test));
        System.out.println(ok ? "✅ Sent to Slack." : "❌ Failed — check the webhook URL.");
        System.exit(ok ? 0 : 1);
    }
}
