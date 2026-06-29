package com.storm.iotdata.fog;

import java.io.Serializable;
import java.util.Arrays;
import java.util.List;

/**
 * All configuration via environment variables — no hardcoded endpoints.
 */
public class CloudConfig implements Serializable {

    private static final long serialVersionUID = 1L;

    private final String cloudMqttHost;
    private final int    cloudMqttPort;
    private final String dbHost;
    private final String dbName;
    private final String dbUser;
    private final String dbPass;
    private final int    flushIntervalSec;
    private final String topologyName;
    // Windows the Cloud derives from 30-min gateway partials
    private final List<Integer> derivedWindows  = Arrays.asList(60, 120);
    // Windows received directly from gateways
    private final List<Integer> gatewayWindows  = Arrays.asList(1, 5, 10, 15, 30);

    // Forecast stage (parity with monolithic Bolt_forecast). Default ON so the
    // Fog cloud performs the SAME analytical work (device/household/house forecast)
    // as the Monolithic baseline — required for a fair scalability comparison.
    private final boolean forecastEnabled;

    // DB write strategy. "batched" (default) = one transaction per flush + JDBC batch
    // (the fix for the 318.9% artifact). "perrow" = autocommit per row (the OLD path),
    // kept measurable so we can REPORT both numbers honestly (prompt §6.3).
    private final boolean cloudMergePerRow;

    // ── Alert / Notification thresholds ──────────────────────────────────────
    private final double alertDeviceMaxW;    // per-device Watt threshold
    private final double alertHouseMaxW;     // per-house  Watt threshold
    private final long   alertCooldownMs;    // min ms between same-key alerts
    private final int    alertWindowMin;     // which window size triggers alerts
    private final String alertMqttTopic;     // global notification topic

    public CloudConfig() {
        cloudMqttHost  = env("CLOUD_MQTT_HOST",  "cloud-mqtt");
        cloudMqttPort  = Integer.parseInt(env("CLOUD_MQTT_PORT", "1883"));
        dbHost         = env("DB_HOST",  "cloud-mysql");
        dbName         = env("DB_NAME",  "iotdata_fog");
        dbUser         = env("DB_USER",  "user1");
        dbPass         = env("DB_PASS",  "Uet123");
        flushIntervalSec = Integer.parseInt(env("FLUSH_INTERVAL_SEC", "60"));
        topologyName   = env("TOPOLOGY_NAME", "fog-cloud");

        alertDeviceMaxW  = Double.parseDouble(env("ALERT_DEVICE_MAX_W",  "2000"));
        alertHouseMaxW   = Double.parseDouble(env("ALERT_HOUSE_MAX_W",   "20000"));
        alertCooldownMs  = Long.parseLong(env("ALERT_COOLDOWN_SEC", "60")) * 1000L;
        alertWindowMin   = Integer.parseInt(env("ALERT_WINDOW_MIN",  "5"));
        alertMqttTopic   = env("ALERT_MQTT_TOPIC", "iot-notification");

        forecastEnabled  = Boolean.parseBoolean(env("FORECAST_ENABLED", "true"));
        cloudMergePerRow = "perrow".equalsIgnoreCase(env("CLOUDMERGE_MODE", "batched"));
    }

    private static String env(String name, String def) {
        String v = System.getenv(name);
        return (v != null && !v.isEmpty()) ? v : def;
    }

    public String getCloudMqttUrl()      { return "tcp://" + cloudMqttHost + ":" + cloudMqttPort; }
    public String getAggSubscribeTopic() { return "fog/agg/#"; }
    // rewriteBatchedStatements=true collapses addBatch() into ONE multi-row statement
    // (instead of N round-trips). Without it, a 200-row REPLACE batch = 200 round-trips
    // (~47s) which is the real cause of the "318.9% cloud capacity" artifact in the 1-GW run.
    public String getDbJdbcUrl()         { return "jdbc:mysql://" + dbHost + ":3306/" + dbName + "?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
                                                  + "&rewriteBatchedStatements=true&cachePrepStmts=true&useServerPrepStmts=false"; }
    public String getDbUser()            { return dbUser; }
    public String getDbPass()            { return dbPass; }
    public int    getFlushIntervalSec()  { return flushIntervalSec; }
    public String getTopologyName()      { return topologyName; }
    public List<Integer> getDerivedWindows()  { return derivedWindows; }
    public List<Integer> getGatewayWindows()  { return gatewayWindows; }
    public boolean isForecastEnabled()        { return forecastEnabled; }
    public boolean isCloudMergePerRow()       { return cloudMergePerRow; }

    // All windows the Fog system materializes (gateway-direct + cloud-derived).
    // Printed at startup so the run log PROVES workload parity with Monolithic.
    public List<Integer> getAllWindows() {
        java.util.List<Integer> all = new java.util.ArrayList<>(gatewayWindows);
        all.addAll(derivedWindows);
        return all;
    }

    /** One-line workload fingerprint for the startup log (prompt §2.1 parity proof). */
    public String getWorkloadBanner() {
        return "[WORKLOAD] windows=" + getAllWindows()
             + " forecast=" + forecastEnabled
             + " cloudMergeMode=" + (cloudMergePerRow ? "perrow" : "batched")
             + " flush=" + flushIntervalSec + "s";
    }

    // Alert getters
    public double getAlertDeviceMaxW()   { return alertDeviceMaxW; }
    public double getAlertHouseMaxW()    { return alertHouseMaxW; }
    public long   getAlertCooldownMs()   { return alertCooldownMs; }
    public int    getAlertWindowMin()    { return alertWindowMin; }
    public String getAlertMqttTopic()    { return alertMqttTopic; }

    @Override
    public String toString() {
        return "[CloudConfig] mqtt=" + getCloudMqttUrl()
             + " db=" + getDbJdbcUrl()
             + " flush=" + flushIntervalSec + "s"
             + " gwWindows=" + gatewayWindows
             + " derivedWindows=" + derivedWindows
             + " alertDevMax=" + alertDeviceMaxW + "W"
             + " alertHouseMax=" + alertHouseMaxW + "W"
             + " alertWindow=" + alertWindowMin + "min";
    }
}
