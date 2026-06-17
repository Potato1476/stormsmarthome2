package com.storm.iotdata.fog;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * All configuration read from environment variables.
 * No hardcoded endpoints — change SOURCE_MQTT_HOST to point at any data source.
 */
public class GatewayConfig implements Serializable {

    private static final long serialVersionUID = 1L;

    private final String gatewayId;
    private final List<Integer> houseIds;
    private final String sourceMqttHost;
    private final int sourceMqttPort;
    private final String cloudMqttHost;
    private final int cloudMqttPort;
    private final String mqttDataTopic;
    private final int flushIntervalSec;
    private final List<Integer> windowList;
    private final int metricsPort;
    private final String topologyName;
    private final String queueDir;

    // ── Multi-channel alerting (Slack) + edge anomaly detection ──────────────
    private final boolean alertEnabled;
    private final String slackWebhookUrl;     // admin/default channel (catch-all fallback)
    private final String alertRoutesFile;     // JSON map houseId -> per-house Slack webhook
    private final double alertHardCeilingW;   // absolute power ceiling -> CRITICAL
    private final double alertZThreshold;     // sigma distance -> WARNING
    private final double alertEwmaAlpha;      // EWMA smoothing factor (0..1)
    private final int alertWarmup;            // samples before z-score activates
    private final int alertCooldownSec;       // per-device min gap between alerts
    private final long alertMinIntervalMs;    // global min gap between Slack posts

    public GatewayConfig() {
        gatewayId      = env("GATEWAY_ID", "gw-01");
        houseIds       = parseIntList(env("HOUSE_IDS", "1,2,3,4,5"));
        sourceMqttHost = env("SOURCE_MQTT_HOST", "mqtt-broker");
        sourceMqttPort = Integer.parseInt(env("SOURCE_MQTT_PORT", "1883"));
        cloudMqttHost  = env("CLOUD_MQTT_HOST", "cloud-mqtt");
        cloudMqttPort  = Integer.parseInt(env("CLOUD_MQTT_PORT", "1883"));
        mqttDataTopic  = env("MQTT_DATA_TOPIC", "iot-data");
        flushIntervalSec = Integer.parseInt(env("FLUSH_INTERVAL_SEC", "60"));
        windowList     = parseIntList(env("GATEWAY_WINDOWS", "1,5,10,15,30"));
        metricsPort    = Integer.parseInt(env("METRICS_PORT", "9091"));
        topologyName   = env("TOPOLOGY_NAME", "fog-gateway-" + gatewayId);
        queueDir       = env("QUEUE_DIR", "/var/fog-queue");

        slackWebhookUrl   = env("SLACK_WEBHOOK_URL", "");
        alertRoutesFile   = env("ALERT_ROUTES_FILE", "/config/alert-routes.json");
        // Alerting auto-enables when there is somewhere to send: an admin webhook OR a
        // mounted per-house routes file. ALERT_ENABLED=false forces it off either way.
        boolean routesFilePresent = !alertRoutesFile.isEmpty()
                && java.nio.file.Files.exists(java.nio.file.Paths.get(alertRoutesFile));
        boolean canAlert  = !slackWebhookUrl.isEmpty() || routesFilePresent;
        alertEnabled      = Boolean.parseBoolean(env("ALERT_ENABLED", String.valueOf(canAlert))) && canAlert;
        alertHardCeilingW = Double.parseDouble(env("ALERT_HARD_CEILING_W", "2500"));
        alertZThreshold   = Double.parseDouble(env("ALERT_Z_THRESHOLD", "3.0"));
        alertEwmaAlpha    = Double.parseDouble(env("ALERT_EWMA_ALPHA", "0.3"));
        alertWarmup       = Integer.parseInt(env("ALERT_WARMUP", "20"));
        alertCooldownSec  = Integer.parseInt(env("ALERT_COOLDOWN_SEC", "60"));
        alertMinIntervalMs= Long.parseLong(env("ALERT_MIN_INTERVAL_MS", "1000"));
    }

    private static String env(String name, String def) {
        String v = System.getenv(name);
        return (v != null && !v.isEmpty()) ? v : def;
    }

    private static List<Integer> parseIntList(String csv) {
        List<Integer> list = new ArrayList<>();
        for (String s : csv.split(",")) {
            String t = s.trim();
            if (!t.isEmpty()) list.add(Integer.parseInt(t));
        }
        return list;
    }

    public String getGatewayId()        { return gatewayId; }
    public List<Integer> getHouseIds()  { return houseIds; }
    public String getSourceMqttUrl()    { return "tcp://" + sourceMqttHost + ":" + sourceMqttPort; }
    public String getCloudMqttUrl()     { return "tcp://" + cloudMqttHost + ":" + cloudMqttPort; }
    public String getMqttDataTopic()    { return mqttDataTopic; }
    public int getFlushIntervalSec()    { return flushIntervalSec; }
    public List<Integer> getWindowList(){ return windowList; }
    public int getMetricsPort()         { return metricsPort; }
    public String getTopologyName()     { return topologyName; }
    public String getQueueDir()         { return queueDir; }

    /** MQTT topic for publishing aggregated results to Cloud. */
    public String getAggTopic()         { return "fog/agg/" + gatewayId; }

    public boolean isAlertEnabled()        { return alertEnabled; }
    public String getSlackWebhookUrl()     { return slackWebhookUrl; }
    public String getAlertRoutesFile()     { return alertRoutesFile; }
    public double getAlertHardCeilingW()   { return alertHardCeilingW; }
    public double getAlertZThreshold()     { return alertZThreshold; }
    public double getAlertEwmaAlpha()      { return alertEwmaAlpha; }
    public int getAlertWarmup()            { return alertWarmup; }
    public int getAlertCooldownSec()       { return alertCooldownSec; }
    public long getAlertMinIntervalMs()    { return alertMinIntervalMs; }

    @Override
    public String toString() {
        return "[GatewayConfig] id=" + gatewayId
             + " houses=" + houseIds
             + " src=" + getSourceMqttUrl()
             + " cloud=" + getCloudMqttUrl()
             + " flush=" + flushIntervalSec + "s"
             + " windows=" + windowList
             + " alerts=" + (alertEnabled ? "ON(ceiling=" + alertHardCeilingW + "W,z=" + alertZThreshold + ")" : "OFF");
    }
}
