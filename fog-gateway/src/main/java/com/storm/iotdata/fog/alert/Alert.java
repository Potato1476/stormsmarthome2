package com.storm.iotdata.fog.alert;

import com.storm.iotdata.fog.anomaly.AnomalyResult;

/**
 * A single device alert ready to be delivered over any channel (Slack today,
 * Telegram/FCM/email tomorrow). Built from an {@link AnomalyResult} plus the
 * identity of the device that produced it.
 */
public class Alert {

    private final String gatewayId;
    private final int houseId;
    private final int householdId;
    private final int plugId;
    private final double value;
    private final double baseline;
    private final double zScore;
    private final AnomalyResult.Severity severity;
    private final String type;
    private final String reason;
    private final long timestampMs;

    public Alert(String gatewayId, int houseId, int householdId, int plugId,
                 AnomalyResult result, long timestampMs) {
        this.gatewayId = gatewayId;
        this.houseId = houseId;
        this.householdId = householdId;
        this.plugId = plugId;
        this.value = result.getValue();
        this.baseline = result.getMean();
        this.zScore = result.getZScore();
        this.severity = result.getSeverity();
        this.type = result.getType();
        this.reason = result.getReason();
        this.timestampMs = timestampMs;
    }

    public String getGatewayId()                { return gatewayId; }
    public int getHouseId()                     { return houseId; }
    public int getHouseholdId()                 { return householdId; }
    public int getPlugId()                      { return plugId; }
    public double getValue()                    { return value; }
    public double getBaseline()                 { return baseline; }
    public double getZScore()                   { return zScore; }
    public AnomalyResult.Severity getSeverity() { return severity; }
    public String getType()                     { return type; }
    public String getReason()                   { return reason; }
    public long getTimestampMs()                { return timestampMs; }

    /** Stable identity of the device, used for per-device alert cool-down. */
    public String deviceKey() {
        return houseId + ":" + householdId + ":" + plugId;
    }
}
