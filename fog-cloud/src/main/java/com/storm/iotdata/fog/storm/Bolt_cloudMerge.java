package com.storm.iotdata.fog.storm;

import com.google.gson.Gson;
import com.storm.iotdata.fog.CloudConfig;
import com.storm.iotdata.fog.functions.FogDB_store;
import com.storm.iotdata.fog.models.AggregatedBatch;
import com.storm.iotdata.fog.models.AggregatedRecord;
import org.apache.storm.task.OutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.topology.base.BaseRichBolt;
import org.apache.storm.tuple.Tuple;
import org.eclipse.paho.client.mqttv3.*;
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence;

import java.util.*;

/**
 * Cloud Fog Computing processing bolt.
 *
 * RESPONSIBILITIES:
 * 1. Accumulate pre-aggregated batches from all 8 gateways
 *    (REPLACE semantics: newer cumulative batch always wins for same key)
 * 2. On trigger: merge across gateways (union, since gateways are disjoint by houseId)
 * 3. Derive long windows (60, 120 min) from 30-min partial aggregates
 *    using algebraic merge: count_60 = Σcount_30 for slices in same 60-min window
 * 4. Roll up device → household → house for each window
 * 5. Write all levels to fog_* MySQL tables
 * 6. [NEW] Detect overload / anomaly thresholds and publish MQTT notifications
 *    → iot-data-api subscribes to these → push to Slack
 *
 * ALGEBRAIC EQUIVALENCE GUARANTEE:
 * For window W, deviceKey K:
 *   Fog:   avg = (Σ sum_i) / (Σ count_i)  where i = gateway batches
 *   Mono:  avg = value / count  (DeviceData.getAvg())
 * Both equal Σ(raw_values) / N_samples  ✓
 */
public class Bolt_cloudMerge extends BaseRichBolt {

    private static final long CLEAN_THRESHOLD_MS = 4L * 60 * 60 * 1000; // 4 h

    // Notification type codes (mirrors iot-data-api frontend)
    private static final int TYPE_OVER_MAX = 1;
    private static final int TYPE_UNDER_MIN = -1;

    private final CloudConfig config;
    private OutputCollector collector;
    private FogDB_store db;

    // Gson for notification JSON serialization
    private transient Gson gson;

    // MQTT client for publishing notifications back to cloud-mqtt
    private transient MqttClient notifClient;

    // Cooldown map: alertKey → lastAlertTimestampMs
    private final Map<String, Long> alertCooldowns = new HashMap<>();

    // Main accumulator: windowMin -> deviceKey -> double[]{count, sum}
    // deviceKey = "houseId:householdId:plugId:year:month:day:sliceIndex"
    // Since gateways are disjoint by houseId, no key conflicts across gateways.
    // Semantics: REPLACE on each batch — latest cumulative values always overwrite.
    private final Map<Integer, Map<String, double[]>> accumulators = new HashMap<>();
    // Track last-update time for cleaning old slices
    private final Map<Integer, Map<String, Long>> lastUpdated = new HashMap<>();
    // [metrics] windowMin -> (deviceKey -> max produced epoch-ms) for end-to-end latency
    private final Map<Integer, Map<String, Long>> eventTsAcc = new HashMap<>();

    private long triggerCount = 0;

    public Bolt_cloudMerge(CloudConfig config) {
        this.config = config;
    }

    @Override
    public void prepare(Map stormConf, TopologyContext context, OutputCollector collector) {
        this.collector = collector;
        this.gson = new Gson();
        this.db = new FogDB_store(config);

        // Initialize maps for all windows (gateway + derived)
        for (int w : config.getGatewayWindows()) {
            accumulators.put(w, new HashMap<>());
            lastUpdated.put(w, new HashMap<>());
            eventTsAcc.put(w, new HashMap<>());
        }

        // Init DB tables (idempotent)
        db.initFogTables();

        // Connect notification MQTT publisher
        initNotifClient();

        System.out.println("[Bolt_cloudMerge] Ready. " + config);
    }

    @Override
    public void execute(Tuple tuple) {
        try {
            if ("agg-data".equals(tuple.getSourceStreamId())) {
                AggregatedBatch batch = (AggregatedBatch) tuple.getValueByField("batch");
                processBatch(batch);
            } else if ("trigger".equals(tuple.getSourceStreamId())) {
                mergeAndSave();
            }
            collector.ack(tuple);
        } catch (Exception e) {
            e.printStackTrace();
            collector.fail(tuple);
        }
    }

    /**
     * Process one batch from a gateway.
     * REPLACE semantics: always overwrite stored values for (windowMin, deviceKey).
     * Safe because batches are cumulative — the latest always contains the most data.
     */
    private void processBatch(AggregatedBatch batch) {
        if (batch.deviceRecords == null || batch.deviceRecords.isEmpty()) return;

        int w = batch.windowSizeMin;
        // Only process windows we have accumulators for (gateway windows)
        if (!accumulators.containsKey(w)) return;

        Map<String, double[]> wAcc = accumulators.get(w);
        Map<String, Long> wTs = lastUpdated.get(w);
        Map<String, Long> wEts = eventTsAcc.get(w);
        long now = System.currentTimeMillis();

        for (AggregatedRecord rec : batch.deviceRecords) {
            // REPLACE: overwrite with latest cumulative values
            wAcc.put(rec.getKey(), new double[]{rec.count, rec.sum});
            wTs.put(rec.getKey(), now);
            if (wEts != null) wEts.merge(rec.getKey(), rec.eventTsMs, Math::max); // [metrics]
        }
    }

    /**
     * On trigger: for each window, compute rollup and write to DB.
     * Also derives 60-min and 120-min windows from 30-min data.
     * Then runs threshold alerting on the configured window.
     */
    private void mergeAndSave() {
        triggerCount++;
        long now = System.currentTimeMillis();

        // Process all gateway windows (1, 5, 10, 15, 30)
        for (int w : config.getGatewayWindows()) {
            Map<String, double[]> devAcc = accumulators.get(w);
            if (devAcc.isEmpty()) continue;

            db.upsertDeviceData(devAcc, eventTsAcc.get(w), w);

            Map<String, double[]> hhAcc = rollupToHousehold(devAcc);
            Map<String, double[]> hAcc  = rollupToHouse(devAcc);
            db.upsertHouseholdData(hhAcc, w);
            db.upsertHouseData(hAcc, w);

            // Forecast stage (parity with monolithic Bolt_forecast):
            // forecast = (currentAvg + median of that key's recent slice avgs) / 2
            if (config.isForecastEnabled()) {
                forecastAndSave(devAcc, "device", w);
                forecastAndSave(hhAcc,  "household", w);
                forecastAndSave(hAcc,   "house", w);
            }
        }

        // Derive and save 60-min and 120-min windows from 30-min data
        Map<String, double[]> base30 = accumulators.get(30);
        if (!base30.isEmpty()) {
            for (int targetW : config.getDerivedWindows()) {
                int ratio = targetW / 30;
                Map<String, double[]> derived = deriveWindow(base30, ratio);
                db.upsertDeviceData(derived, null, targetW); // derived windows: event_ts not tracked
                db.upsertHouseholdData(rollupToHousehold(derived), targetW);
                db.upsertHouseData(rollupToHouse(derived), targetW);
            }
        }

        // ── Alert detection on the configured window ──────────────────────────
        int alertWindow = config.getAlertWindowMin();
        if (accumulators.containsKey(alertWindow)) {
            Map<String, double[]> devAcc = accumulators.get(alertWindow);
            if (!devAcc.isEmpty()) {
                checkDeviceAlerts(devAcc, now);
                checkHouseAlerts(rollupToHouse(devAcc), now);
            }
        }

        // Clean very old slices to prevent unbounded memory growth
        cleanOldSlices(now);

        System.out.printf("[Bolt_cloudMerge] trigger #%d — accKeys: %s%n",
            triggerCount,
            accumulators.entrySet().stream()
                .map(e -> e.getKey() + "=" + e.getValue().size())
                .reduce((a, b) -> a + " " + b).orElse("none"));
    }

    // ── Alert Detection ───────────────────────────────────────────────────────

    /**
     * Check each device's avg against ALERT_DEVICE_MAX_W.
     * Key format: "houseId:householdId:plugId:year:month:day:sliceIndex"
     */
    private void checkDeviceAlerts(Map<String, double[]> devAcc, long now) {
        double maxW = config.getAlertDeviceMaxW();

        // Compute per-device avg baseline (mean over all devices in same house)
        // for contextual info in the notification
        Map<String, Double> houseAvgMap = computeHouseAvgWatt(devAcc);

        for (Map.Entry<String, double[]> e : devAcc.entrySet()) {
            double[] cs = e.getValue(); // [count, sum]
            if (cs[0] == 0) continue;
            double avg = cs[1] / cs[0];

            if (avg > maxW) {
                String[] p = e.getKey().split(":");
                int houseId     = Integer.parseInt(p[0]);
                int householdId = Integer.parseInt(p[1]);
                int deviceId    = Integer.parseInt(p[2]);

                String cooldownKey = "dev-" + houseId + "-" + householdId + "-" + deviceId;
                if (!shouldAlert(cooldownKey, now)) continue;

                double houseAvg = houseAvgMap.getOrDefault(String.valueOf(houseId), avg);

                Map<String, Object> notif = new LinkedHashMap<>();
                notif.put("type",        TYPE_OVER_MAX);
                notif.put("houseId",     houseId);
                notif.put("householdId", householdId);
                notif.put("deviceId",    deviceId);
                notif.put("value",       round2(avg));
                notif.put("max",         maxW);
                notif.put("avg",         round2(houseAvg));
                notif.put("windowMin",   config.getAlertWindowMin());
                notif.put("ts",          now);

                // Publish to specific device topic AND global topic
                String topic = "device-" + houseId + "-" + householdId + "-" + deviceId + "-notification";
                publishNotif(topic, notif);
                publishNotif(config.getAlertMqttTopic(), notif);

                System.out.printf("[ALERT] Device overload — house=%d household=%d device=%d avg=%.1fW (max=%.1fW)%n",
                    houseId, householdId, deviceId, avg, maxW);
            }
        }
    }

    /**
     * Check per-house total avg against ALERT_HOUSE_MAX_W.
     * houseKey: "houseId:year:month:day:sliceIndex"
     */
    private void checkHouseAlerts(Map<String, double[]> houseAcc, long now) {
        double maxW = config.getAlertHouseMaxW();

        for (Map.Entry<String, double[]> e : houseAcc.entrySet()) {
            double[] cs = e.getValue();
            if (cs[0] == 0) continue;
            double total = cs[1]; // For house rollup, sum = sum-of-device-avgs

            if (total > maxW) {
                String[] p = e.getKey().split(":");
                int houseId = Integer.parseInt(p[0]);

                String cooldownKey = "house-" + houseId;
                if (!shouldAlert(cooldownKey, now)) continue;

                Map<String, Object> notif = new LinkedHashMap<>();
                notif.put("type",    TYPE_OVER_MAX);
                notif.put("houseId", houseId);
                notif.put("value",   round2(total));
                notif.put("max",     maxW);
                notif.put("avg",     round2(total));
                notif.put("windowMin", config.getAlertWindowMin());
                notif.put("ts",      now);

                String topic = "house-" + houseId + "-notification";
                publishNotif(topic, notif);
                publishNotif(config.getAlertMqttTopic(), notif);

                System.out.printf("[ALERT] House overload — house=%d total=%.1fW (max=%.1fW)%n",
                    houseId, total, maxW);
            }
        }
    }

    /** Publish a JSON notification to cloud-mqtt. Reconnects on failure. */
    private void publishNotif(String topic, Map<String, Object> notif) {
        try {
            if (notifClient == null || !notifClient.isConnected()) {
                initNotifClient();
            }
            String json = gson.toJson(notif);
            MqttMessage msg = new MqttMessage(json.getBytes("UTF-8"));
            msg.setQos(0);
            msg.setRetained(false);
            notifClient.publish(topic, msg);
        } catch (Exception ex) {
            System.err.printf("[Bolt_cloudMerge] Failed to publish notification to %s: %s%n",
                topic, ex.getMessage());
        }
    }

    /** Returns true if enough time has passed since last alert for this key. */
    private boolean shouldAlert(String key, long now) {
        Long last = alertCooldowns.get(key);
        if (last == null || (now - last) > config.getAlertCooldownMs()) {
            alertCooldowns.put(key, now);
            return true;
        }
        return false;
    }

    /**
     * Computes average watt per house (sum of device avgs / device count).
     * Used for contextual "avg" field in device notification.
     */
    private Map<String, Double> computeHouseAvgWatt(Map<String, double[]> devAcc) {
        Map<String, double[]> sums = new HashMap<>();
        for (Map.Entry<String, double[]> e : devAcc.entrySet()) {
            double[] cs = e.getValue();
            if (cs[0] == 0) continue;
            double devAvg = cs[1] / cs[0];
            String houseId = e.getKey().split(":")[0];
            double[] acc = sums.computeIfAbsent(houseId, k -> new double[]{0, 0});
            acc[0] += 1;
            acc[1] += devAvg;
        }
        Map<String, Double> result = new HashMap<>();
        for (Map.Entry<String, double[]> e : sums.entrySet()) {
            result.put(e.getKey(), e.getValue()[0] == 0 ? 0 : e.getValue()[1] / e.getValue()[0]);
        }
        return result;
    }

    private void initNotifClient() {
        try {
            if (notifClient != null) {
                try { notifClient.close(true); } catch (Exception ignored) {}
            }
            notifClient = new MqttClient(config.getCloudMqttUrl(),
                                         "cloud-bolt-notif-" + UUID.randomUUID().toString().substring(0, 8),
                                         new MemoryPersistence());
            MqttConnectOptions opts = new MqttConnectOptions();
            opts.setAutomaticReconnect(true);
            opts.setConnectionTimeout(10);
            opts.setKeepAliveInterval(30);
            notifClient.connect(opts);
            System.out.println("[Bolt_cloudMerge] Notification MQTT connected → " + config.getCloudMqttUrl());
        } catch (MqttException e) {
            System.err.println("[Bolt_cloudMerge] Notification MQTT connect failed: " + e.getMessage());
        }
    }

    // ── Window derivation & rollup helpers ───────────────────────────────────

    /**
     * Algebraic derivation: from W-min slices, create (W×ratio)-min slices.
     * For ratio=2: 30→60. For ratio=4: 30→120.
     *
     * derivedSliceIndex = floor(sourceSliceIndex / ratio)
     * count and sum are ADDED across all source slices that map to the same derived slice.
     */
    private Map<String, double[]> deriveWindow(Map<String, double[]> source, int ratio) {
        Map<String, double[]> result = new HashMap<>();
        for (Map.Entry<String, double[]> e : source.entrySet()) {
            // key: "houseId:householdId:plugId:year:month:day:sliceIndex"
            String[] p = e.getKey().split(":");
            int srcSlice = Integer.parseInt(p[6]);
            int dstSlice = srcSlice / ratio;
            String dstKey = p[0] + ":" + p[1] + ":" + p[2] + ":"
                          + p[3] + ":" + p[4] + ":" + p[5] + ":" + dstSlice;
            double[] acc = result.computeIfAbsent(dstKey, k -> new double[]{0, 0});
            acc[0] += e.getValue()[0]; // count
            acc[1] += e.getValue()[1]; // sum
        }
        return result;
    }

    /**
     * Roll up device-level to household-level.
     * hhKey: "houseId:householdId:year:month:day:sliceIndex"
     * Sum all device avgs within same household+timeslice (mirrors Bolt_sum logic).
     */
    private Map<String, double[]> rollupToHousehold(Map<String, double[]> devAcc) {
        Map<String, double[]> result = new HashMap<>();
        for (Map.Entry<String, double[]> e : devAcc.entrySet()) {
            String[] p = e.getKey().split(":");
            // device key: houseId:householdId:plugId:year:month:day:sliceIndex
            double devAvg = e.getValue()[0] == 0 ? 0 : e.getValue()[1] / e.getValue()[0];
            String hhKey = p[0] + ":" + p[1] + ":" + p[3] + ":" + p[4] + ":" + p[5] + ":" + p[6];
            double[] acc = result.computeIfAbsent(hhKey, k -> new double[]{0, 0});
            acc[1] += devAvg;  // sum of device avgs (same as monolithic Bolt_sum)
            acc[0] += 1;       // count = number of devices contributing
        }
        return result;
    }

    /**
     * Roll up device-level to house-level.
     * houseKey: "houseId:year:month:day:sliceIndex"
     */
    private Map<String, double[]> rollupToHouse(Map<String, double[]> devAcc) {
        Map<String, double[]> result = new HashMap<>();
        for (Map.Entry<String, double[]> e : devAcc.entrySet()) {
            String[] p = e.getKey().split(":");
            double devAvg = e.getValue()[0] == 0 ? 0 : e.getValue()[1] / e.getValue()[0];
            String hKey = p[0] + ":" + p[3] + ":" + p[4] + ":" + p[5] + ":" + p[6];
            double[] acc = result.computeIfAbsent(hKey, k -> new double[]{0, 0});
            acc[1] += devAvg;
            acc[0] += 1;
        }
        return result;
    }

    /**
     * Forecast stage — mirrors monolithic Bolt_forecast (forecast = (avg + median)/2).
     * Here "median" is taken over the recent slice-avgs of the SAME key prefix
     * (key without its trailing sliceIndex) currently held in the accumulator.
     * Writes one row per key into fog_forecast. Adds the same analytical/DB workload
     * to the Fog cloud as the Monolithic baseline, so the comparison is fair.
     */
    private void forecastAndSave(Map<String, double[]> acc, String level, int w) {
        if (acc == null || acc.isEmpty()) return;
        // Group current slice avgs by entity (key with sliceIndex stripped)
        Map<String, List<Double>> history = new HashMap<>();
        Map<String, Double> curAvg = new HashMap<>();
        for (Map.Entry<String, double[]> e : acc.entrySet()) {
            double[] cs = e.getValue();
            if (cs[0] == 0) continue;
            double avg = cs[1] / cs[0];
            curAvg.put(e.getKey(), avg);
            String entity = entityPrefix(e.getKey());
            history.computeIfAbsent(entity, k -> new ArrayList<>()).add(avg);
        }
        Map<String, Double> forecasts = new HashMap<>();
        for (Map.Entry<String, Double> e : curAvg.entrySet()) {
            double avg = e.getValue();
            double median = median(history.get(entityPrefix(e.getKey())));
            double f = median > 0 ? (avg + median) / 2.0 : avg;
            forecasts.put(e.getKey(), round2(f));
        }
        db.upsertForecast(forecasts, level, w);
    }

    /** Strip the trailing :sliceIndex segment to get the entity key. */
    private static String entityPrefix(String key) {
        int i = key.lastIndexOf(':');
        return i > 0 ? key.substring(0, i) : key;
    }

    /** Median of a list of doubles (0 if empty). */
    private static double median(List<Double> xs) {
        if (xs == null || xs.isEmpty()) return 0;
        List<Double> s = new ArrayList<>(xs);
        Collections.sort(s);
        int n = s.size();
        return (n % 2 == 1) ? s.get(n / 2) : (s.get(n / 2 - 1) + s.get(n / 2)) / 2.0;
    }

    private void cleanOldSlices(long now) {
        for (int w : config.getGatewayWindows()) {
            Map<String, Long> ts  = lastUpdated.get(w);
            Map<String, double[]> acc = accumulators.get(w);
            List<String> toRemove = new ArrayList<>();
            for (Map.Entry<String, Long> e : ts.entrySet()) {
                if (now - e.getValue() > CLEAN_THRESHOLD_MS) toRemove.add(e.getKey());
            }
            Map<String, Long> ets = eventTsAcc.get(w);
            for (String k : toRemove) { acc.remove(k); ts.remove(k); if (ets != null) ets.remove(k); }
        }
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        // Terminal bolt — writes to DB + publishes MQTT, emits nothing
    }
}
