package com.storm.iotdata.fog.metrics;

import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Lightweight embedded HTTP server that exposes Prometheus-format metrics
 * for the gateway LocalCluster (which has no external Storm UI).
 *
 * Prometheus scrapes http://gateway-host:METRICS_PORT/metrics
 */
public class PrometheusMetricsServer {

    private final String gatewayId;
    private final AtomicLong tuplesProcessed = new AtomicLong();
    private final AtomicLong flushCount      = new AtomicLong();
    private final AtomicLong mqttPublished   = new AtomicLong();
    private final AtomicLong queueSize       = new AtomicLong();

    // Store-and-forward queue event counters
    private final AtomicLong queueEnqueued = new AtomicLong();
    private final AtomicLong queueDrained  = new AtomicLong();

    // Anomaly alerting counters
    private final AtomicLong alertsFired      = new AtomicLong(); // anomalies dispatched to a channel
    private final AtomicLong alertsSuppressed = new AtomicLong(); // anomalies muted by per-device cooldown

    // EMA of bolt execute latency; Double.NaN means "no measurement yet"
    private volatile double executeLatencyEmaMs = Double.NaN;
    // Max execute latency in the current flush window (reset after each flush)
    private volatile double executeLatencyMaxMs = 0.0;

    // EMA of flush() duration (MQTT publish to cloud); NaN until first flush
    private volatile double flushLatencyEmaMs = Double.NaN;
    // Max flush latency in the current measurement window
    private volatile double flushLatencyMaxMs = 0.0;

    // Capacity computed at each flush
    private volatile double capacity = 0.0;

    public PrometheusMetricsServer(int port, String gatewayId) throws IOException {
        this.gatewayId = gatewayId;
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);
        server.createContext("/metrics", exchange -> {
            byte[] body = buildMetrics().getBytes("UTF-8");
            exchange.getResponseHeaders().set("Content-Type", "text/plain; version=0.0.4; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        });
        server.setExecutor(null);
        server.start();
        System.out.printf("[PrometheusMetrics] gateway=%s listening on :%d/metrics%n", gatewayId, port);
    }

    private String buildMetrics() {
        String lbl = "{gateway_id=\"" + gatewayId + "\",tier=\"gateway\"}";
        StringBuilder sb = new StringBuilder();

        metric(sb, "fog_gateway_tuples_processed_total", "counter",
               "Total raw tuples processed by bolt-ingest", lbl, tuplesProcessed.get());
        metric(sb, "fog_gateway_flush_total", "counter",
               "Total flush operations (MQTT publishes attempted)", lbl, flushCount.get());
        metric(sb, "fog_gateway_mqtt_published_total", "counter",
               "MQTT messages successfully published to Cloud", lbl, mqttPublished.get());
        metric(sb, "fog_gateway_store_queue_size", "gauge",
               "Pending messages in store-and-forward queue", lbl, queueSize.get());
        metric(sb, "fog_gateway_queue_enqueued_total", "counter",
               "Batches added to store-and-forward queue (MQTT publish failed)", lbl, queueEnqueued.get());
        metric(sb, "fog_gateway_queue_drained_total", "counter",
               "Batches successfully drained from queue back to cloud", lbl, queueDrained.get());
        metric(sb, "fog_gateway_alerts_fired_total", "counter",
               "Anomaly alerts dispatched to an external channel (e.g. Slack)", lbl, alertsFired.get());
        metric(sb, "fog_gateway_alerts_suppressed_total", "counter",
               "Anomaly alerts muted by per-device cooldown", lbl, alertsSuppressed.get());

        // Execute latency: report 0 until first measurement to avoid NaN in output
        double execEma = Double.isNaN(executeLatencyEmaMs) ? 0.0 : executeLatencyEmaMs;
        dmetric(sb, "fog_gateway_bolt_execute_latency_ms", "gauge",
                "EMA of bolt-ingest execute latency per tuple (ms)", lbl, execEma);
        dmetric(sb, "fog_gateway_bolt_execute_latency_max_ms", "gauge",
                "Max bolt-ingest execute latency since last flush (ms)", lbl, executeLatencyMaxMs);

        // Flush latency: time for flush() to complete (includes MQTT publish to cloud)
        double flushEma = Double.isNaN(flushLatencyEmaMs) ? 0.0 : flushLatencyEmaMs;
        dmetric(sb, "fog_gateway_flush_latency_ms", "gauge",
                "EMA of flush duration including MQTT publish to cloud (ms)", lbl, flushEma);
        dmetric(sb, "fog_gateway_flush_latency_max_ms", "gauge",
                "Max flush duration since last reset (ms)", lbl, flushLatencyMaxMs);

        dmetric(sb, "fog_gateway_bolt_capacity", "gauge",
                "Approximate bolt capacity (0-1 scale, based on actual avg latency)", lbl, capacity);

        return sb.toString();
    }

    private void metric(StringBuilder sb, String name, String type, String help, String lbl, long val) {
        sb.append("# HELP ").append(name).append(' ').append(help).append('\n');
        sb.append("# TYPE ").append(name).append(' ').append(type).append('\n');
        sb.append(name).append(lbl).append(' ').append(val).append('\n');
    }

    private void dmetric(StringBuilder sb, String name, String type, String help, String lbl, double val) {
        sb.append("# HELP ").append(name).append(' ').append(help).append('\n');
        sb.append("# TYPE ").append(name).append(' ').append(type).append('\n');
        sb.append(name).append(lbl).append(' ').append(String.format("%.4f", val)).append('\n');
    }

    public void incrementTuplesProcessed()      { tuplesProcessed.incrementAndGet(); }
    public void incrementFlushCount(int n)      { flushCount.addAndGet(n); }
    public void incrementMqttPublished()        { mqttPublished.incrementAndGet(); }
    public void addQueueSize(int delta)         { queueSize.addAndGet(delta); }
    public void setQueueSize(long n)            { queueSize.set(n); }
    public void incrementQueueEnqueued()        { queueEnqueued.incrementAndGet(); }
    public void incrementQueueDrained()         { queueDrained.incrementAndGet(); }
    public void incrementAlertsFired()          { alertsFired.incrementAndGet(); }
    public void incrementAlertsSuppressed()     { alertsSuppressed.incrementAndGet(); }

    /**
     * Called after each data tuple is processed in Bolt_ingest.
     * Uses EMA (alpha=0.2) for responsiveness; also tracks window max.
     */
    public void recordExecuteLatency(long startNs) {
        double ms = (System.nanoTime() - startNs) / 1_000_000.0;
        if (Double.isNaN(executeLatencyEmaMs)) {
            executeLatencyEmaMs = ms;
        } else {
            executeLatencyEmaMs = executeLatencyEmaMs * 0.8 + ms * 0.2;
        }
        if (ms > executeLatencyMaxMs) {
            executeLatencyMaxMs = ms;
        }
    }

    /**
     * Called once per flush() completion. Measures actual MQTT publish duration.
     * Uses EMA (alpha=0.3) since flush happens infrequently.
     */
    public void recordFlushLatency(long startNs) {
        double ms = (System.nanoTime() - startNs) / 1_000_000.0;
        if (Double.isNaN(flushLatencyEmaMs)) {
            flushLatencyEmaMs = ms;
        } else {
            flushLatencyEmaMs = flushLatencyEmaMs * 0.7 + ms * 0.3;
        }
        if (ms > flushLatencyMaxMs) {
            flushLatencyMaxMs = ms;
        }
    }

    /**
     * Reset per-window max counters. Call at the start of each flush window
     * so max values reflect the window that just ended, then clear for next window.
     */
    public void resetWindowMaxes() {
        executeLatencyMaxMs = 0.0;
        flushLatencyMaxMs   = 0.0;
    }

    public void updateCapacity(long processedInWindow, long windowMs) {
        double avgLatencyMs = Double.isNaN(executeLatencyEmaMs) ? 0.0 : executeLatencyEmaMs;
        capacity = windowMs > 0 ? Math.min(1.0, (processedInWindow * avgLatencyMs) / windowMs) : 0;
    }
}
