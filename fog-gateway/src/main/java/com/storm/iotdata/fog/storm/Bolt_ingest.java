package com.storm.iotdata.fog.storm;

import com.google.gson.Gson;
import com.storm.iotdata.fog.GatewayConfig;
import com.storm.iotdata.fog.alert.Alert;
import com.storm.iotdata.fog.alert.RouteRegistry;
import com.storm.iotdata.fog.alert.SlackNotifier;
import com.storm.iotdata.fog.anomaly.AnomalyDetector;
import com.storm.iotdata.fog.anomaly.AnomalyResult;
import com.storm.iotdata.fog.metrics.PrometheusMetricsServer;
import com.storm.iotdata.fog.models.AggregatedBatch;
import com.storm.iotdata.fog.models.AggregatedRecord;
import java.util.concurrent.ConcurrentHashMap;
import org.apache.storm.task.OutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.topology.base.BaseRichBolt;
import org.apache.storm.tuple.Tuple;
import org.eclipse.paho.client.mqttv3.*;
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Core Fog Computing innovation:
 *
 * 1. LOGICAL FAN-OUT: instead of emitting 5 tuples for 5 window sizes,
 *    we update 5 in-memory counters per tuple — no physical network traffic.
 *
 * 2. INCREMENTAL AGGREGATION: only count+sum are stored, not raw tuples.
 *    Memory = O(devices × windows) = a few KB, not O(raw stream).
 *
 * 3. TRAFFIC SHAPING: flush to Cloud every 60 s regardless of input rate.
 *    Cloud never sees "fire-hose" spikes.
 *
 * 4. STORE-AND-FORWARD: if Cloud MQTT is unreachable, batches are queued
 *    to local disk and replayed when the connection recovers.
 *
 * 5. CUMULATIVE SEMANTICS: each flush contains full cumulative totals for
 *    every active time slice. Cloud uses REPLACE (not ADD) — idempotent.
 */
public class Bolt_ingest extends BaseRichBolt {

    private static final long CLEAN_THRESHOLD_MS = 3L * 60 * 60 * 1000; // 3 h
    // Shared across prepare() re-invocations (Storm rebalance/restart within same JVM)
    // so metrics counters survive topology restarts and port-already-in-use errors.
    private static final ConcurrentHashMap<String, PrometheusMetricsServer> METRIC_REGISTRY =
        new ConcurrentHashMap<>();

    private final GatewayConfig config;
    private transient OutputCollector collector;
    private transient PrometheusMetricsServer metrics;

    // windowMin -> (deviceSliceKey -> double[]{count, sum})
    // Key format: "houseId:householdId:plugId:year:month:day:sliceIndex"
    private final Map<Integer, Map<String, double[]>> accumulators = new HashMap<>();
    // windowMin -> (deviceSliceKey -> lastUpdateMs)
    private final Map<Integer, Map<String, Long>> lastUpdate = new HashMap<>();
    // [metrics] windowMin -> (deviceSliceKey -> max produced epoch-ms) for end-to-end latency
    private final Map<Integer, Map<String, Long>> eventTsAcc = new HashMap<>();

    private transient MqttClient cloudClient;
    private transient Gson gson;

    // Edge anomaly detection + multi-channel alerting (null when disabled)
    private transient AnomalyDetector anomalyDetector;
    private transient SlackNotifier slack;
    private transient Map<String, Long> lastAlertAt; // deviceKey -> last alert epoch ms
    private long alertCooldownMs;

    private long windowStartMs = System.currentTimeMillis();
    private long processedInWindow = 0;

    public Bolt_ingest(GatewayConfig config) {
        this.config = config;
        for (int w : config.getWindowList()) {
            accumulators.put(w, new HashMap<>());
            lastUpdate.put(w, new HashMap<>());
            eventTsAcc.put(w, new HashMap<>());
        }
    }

    @Override
    public void prepare(Map stormConf, TopologyContext context, OutputCollector collector) {
        this.collector = collector;
        this.gson = new Gson();
        metrics = METRIC_REGISTRY.computeIfAbsent(config.getGatewayId(), id -> {
            try {
                return new PrometheusMetricsServer(config.getMetricsPort(), id);
            } catch (IOException e) {
                System.err.println("[Bolt_ingest] Failed to start metrics server: " + e.getMessage());
                return null;
            }
        });
        initCloudClient();
        ensureQueueDir();
        initAlerting();
    }

    private void initAlerting() {
        if (!config.isAlertEnabled()) {
            System.out.printf("[Bolt_ingest-%s] Alerting disabled (no SLACK_WEBHOOK_URL).%n", config.getGatewayId());
            return;
        }
        anomalyDetector = new AnomalyDetector(
                config.getAlertEwmaAlpha(), config.getAlertZThreshold(),
                config.getAlertHardCeilingW(), config.getAlertWarmup());
        // Per-house routing: each house's alerts go to its own Slack channel, with
        // SLACK_WEBHOOK_URL as the admin catch-all for unmapped houses.
        RouteRegistry routes = RouteRegistry.fromJsonFile(
                config.getAlertRoutesFile(), config.getSlackWebhookUrl());
        slack = new SlackNotifier(routes, true, config.getAlertMinIntervalMs());
        lastAlertAt = new HashMap<>();
        alertCooldownMs = config.getAlertCooldownSec() * 1000L;
        System.out.printf("[Bolt_ingest-%s] Alerting ON: ceiling=%.0fW z>=%.1f warmup=%d cooldown=%ds routes=%d(+admin)%n",
                config.getGatewayId(), config.getAlertHardCeilingW(), config.getAlertZThreshold(),
                config.getAlertWarmup(), config.getAlertCooldownSec(), routes.size());
    }

    @Override
    public void execute(Tuple tuple) {
        try {
            if ("data".equals(tuple.getSourceStreamId())) {
                processData(tuple);
            } else if ("trigger".equals(tuple.getSourceStreamId())) {
                flush();
            }
            collector.ack(tuple);
        } catch (Exception e) {
            e.printStackTrace();
            collector.fail(tuple);
        }
    }

    private void processData(Tuple tuple) {
        long startNs = System.nanoTime();
        try {
            int houseId     = Integer.parseInt(tuple.getStringByField("houseId"));
            int householdId = Integer.parseInt(tuple.getStringByField("householdId"));
            int plugId      = Integer.parseInt(tuple.getStringByField("plugId"));
            long timestamp  = Long.parseLong(tuple.getStringByField("timestamp"));
            double value    = Double.parseDouble(tuple.getStringByField("value"));

            @SuppressWarnings("deprecation")
            Date date = new Date(timestamp * 1000L);
            String year  = String.valueOf(1900 + date.getYear());
            String month = String.format("%02d", 1 + date.getMonth());
            String day   = String.format("%02d", date.getDate());
            long timeInDay = date.getTime() % 86400000L;

            // Logical fan-out: update all window accumulators in one pass (no tuple emission)
            long now = System.currentTimeMillis();
            long producedMs = timestamp * 1000L; // [metrics] when the reading was produced
            for (int windowMin : config.getWindowList()) {
                int sliceIndex = (int) (timeInDay / (windowMin * 60000L));
                String key = houseId + ":" + householdId + ":" + plugId + ":"
                           + year + ":" + month + ":" + day + ":" + sliceIndex;
                double[] acc = accumulators.get(windowMin)
                                           .computeIfAbsent(key, k -> new double[]{0, 0});
                acc[0]++;           // count
                acc[1] += value;    // sum
                lastUpdate.get(windowMin).put(key, now);
                eventTsAcc.get(windowMin).merge(key, producedMs, Math::max); // [metrics]
            }

            processedInWindow++;
            if (metrics != null) metrics.incrementTuplesProcessed();

            // Real-time anomaly detection at the edge — runs on the raw reading,
            // so an alert fires within milliseconds, not after the 60s cloud flush.
            if (anomalyDetector != null) {
                detectAndAlert(houseId, householdId, plugId, value);
            }

        } finally {
            if (metrics != null) metrics.recordExecuteLatency(startNs);
        }
    }

    private void detectAndAlert(int houseId, int householdId, int plugId, double value) {
        String deviceKey = houseId + ":" + householdId + ":" + plugId;
        AnomalyResult result = anomalyDetector.update(deviceKey, value);
        if (!result.isAnomaly()) return;

        long now = System.currentTimeMillis();
        Long last = lastAlertAt.get(deviceKey);
        if (last != null && now - last < alertCooldownMs) {
            if (metrics != null) metrics.incrementAlertsSuppressed();
            return; // still in cooldown — don't spam the channel for the same device
        }
        lastAlertAt.put(deviceKey, now);

        Alert alert = new Alert(config.getGatewayId(), houseId, householdId, plugId, result, now);
        if (slack.send(alert) && metrics != null) {
            metrics.incrementAlertsFired();
        }
        System.out.printf("[Bolt_ingest-%s] ALERT %s house=%d hh=%d plug=%d %s%n",
                config.getGatewayId(), result.getSeverity(), houseId, householdId, plugId, result.getReason());
    }

    private void flush() {
        long flushStartNs = System.nanoTime();
        long now = System.currentTimeMillis();
        int published = 0;

        // Reset per-window max counters before accumulating new window's data
        if (metrics != null) metrics.resetWindowMaxes();

        // Drain store-and-forward queue first (opportunistic retry)
        drainQueue();

        // Publish one AggregatedBatch per window size
        for (int windowMin : config.getWindowList()) {
            Map<String, double[]> windowAcc = accumulators.get(windowMin);
            if (windowAcc.isEmpty()) continue;

            Map<String, Long> windowEventTs = eventTsAcc.get(windowMin);
            List<AggregatedRecord> records = new ArrayList<>(windowAcc.size());
            for (Map.Entry<String, double[]> e : windowAcc.entrySet()) {
                String[] p = e.getKey().split(":");
                // p: houseId:householdId:plugId:year:month:day:sliceIndex
                AggregatedRecord rec = new AggregatedRecord(
                    Integer.parseInt(p[0]), Integer.parseInt(p[1]), Integer.parseInt(p[2]),
                    p[3], p[4], p[5], Integer.parseInt(p[6]),
                    e.getValue()[0], e.getValue()[1]
                );
                Long ets = windowEventTs == null ? null : windowEventTs.get(e.getKey());
                rec.eventTsMs = ets == null ? 0L : ets; // [metrics] freshest produced epoch-ms
                records.add(rec);
            }

            AggregatedBatch batch = new AggregatedBatch(config.getGatewayId(), now, windowMin, records);
            publishOrQueue(batch);
            published++;
        }

        // Update capacity metric and record flush duration
        long windowDuration = now - windowStartMs;
        if (metrics != null) {
            metrics.incrementFlushCount(published);
            metrics.updateCapacity(processedInWindow, windowDuration);
            metrics.recordFlushLatency(flushStartNs);
        }
        windowStartMs = now;
        processedInWindow = 0;

        // Clean accumulators older than threshold
        cleanOldSlices(now);

        System.out.printf("[Bolt_ingest-%s] flush: %d windows, total accKeys=%d%n",
            config.getGatewayId(), published,
            accumulators.values().stream().mapToInt(Map::size).sum());
    }

    private void publishOrQueue(AggregatedBatch batch) {
        String json = gson.toJson(batch);
        try {
            byte[] payload = gzip(json.getBytes(StandardCharsets.UTF_8));
            if (cloudClient == null || !cloudClient.isConnected()) {
                initCloudClient();
            }
            MqttMessage msg = new MqttMessage(payload);
            msg.setQos(1);
            msg.setRetained(false);
            cloudClient.publish(config.getAggTopic(), msg);
            if (metrics != null) metrics.incrementMqttPublished();
        } catch (Exception e) {
            System.err.printf("[Bolt_ingest-%s] MQTT publish failed, queuing: %s%n",
                config.getGatewayId(), e.getMessage());
            appendToQueue(json);
            if (metrics != null) metrics.incrementQueueEnqueued();
        }
    }

    private void appendToQueue(String json) {
        File f = queueFile();
        try (FileWriter fw = new FileWriter(f, true)) {
            fw.write(json + "\n");
            if (metrics != null) metrics.addQueueSize(1);
        } catch (IOException ex) {
            System.err.println("[Bolt_ingest] Failed to write queue: " + ex.getMessage());
        }
    }

    private void drainQueue() {
        File f = queueFile();
        if (!f.exists() || f.length() == 0) return;
        if (cloudClient == null || !cloudClient.isConnected()) return;

        List<String> remaining = new ArrayList<>();
        try (BufferedReader br = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;
                try {
                    byte[] payload = gzip(line.getBytes(StandardCharsets.UTF_8));
                    MqttMessage msg = new MqttMessage(payload);
                    msg.setQos(1);
                    cloudClient.publish(config.getAggTopic(), msg);
                    if (metrics != null) {
                        metrics.incrementMqttPublished();
                        metrics.incrementQueueDrained();
                        metrics.addQueueSize(-1);
                    }
                } catch (Exception e) {
                    remaining.add(line);
                }
            }
        } catch (IOException e) {
            System.err.println("[Bolt_ingest] Failed to read queue: " + e.getMessage());
            return;
        }

        // Rewrite queue with only remaining (failed) lines
        try (FileWriter fw = new FileWriter(f, false)) {
            for (String line : remaining) fw.write(line + "\n");
        } catch (IOException e) {
            System.err.println("[Bolt_ingest] Failed to rewrite queue: " + e.getMessage());
        }
        if (metrics != null) metrics.setQueueSize(remaining.size());
    }

    private void cleanOldSlices(long now) {
        for (int windowMin : config.getWindowList()) {
            Map<String, Long> lu = lastUpdate.get(windowMin);
            Map<String, double[]> acc = accumulators.get(windowMin);
            List<String> toRemove = new ArrayList<>();
            for (Map.Entry<String, Long> e : lu.entrySet()) {
                if (now - e.getValue() > CLEAN_THRESHOLD_MS) {
                    toRemove.add(e.getKey());
                }
            }
            Map<String, Long> ets = eventTsAcc.get(windowMin);
            for (String k : toRemove) {
                acc.remove(k);
                lu.remove(k);
                if (ets != null) ets.remove(k);
            }
        }
    }

    private void initCloudClient() {
        try {
            if (cloudClient != null) {
                try { cloudClient.close(true); } catch (Exception ignored) {}
            }
            cloudClient = new MqttClient(config.getCloudMqttUrl(),
                                          "gateway-publisher-" + config.getGatewayId(),
                                          new MemoryPersistence());
            MqttConnectOptions opts = new MqttConnectOptions();
            opts.setAutomaticReconnect(true);
            opts.setConnectionTimeout(10);
            cloudClient.connect(opts);
            System.out.printf("[Bolt_ingest-%s] Connected to Cloud MQTT %s%n",
                config.getGatewayId(), config.getCloudMqttUrl());
        } catch (MqttException e) {
            System.err.printf("[Bolt_ingest-%s] Cloud MQTT connect failed: %s%n",
                config.getGatewayId(), e.getMessage());
        }
    }

    private File queueFile() {
        return new File(config.getQueueDir() + "/" + config.getGatewayId() + "/queue.jsonl");
    }

    private void ensureQueueDir() {
        queueFile().getParentFile().mkdirs();
    }

    private static byte[] gzip(byte[] data) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (GZIPOutputStream gos = new GZIPOutputStream(bos)) {
            gos.write(data);
        }
        return bos.toByteArray();
    }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        // Terminal bolt — publishes to MQTT, emits nothing back into Storm
    }
}
