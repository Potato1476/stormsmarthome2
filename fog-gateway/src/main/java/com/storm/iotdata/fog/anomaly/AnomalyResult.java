package com.storm.iotdata.fog.anomaly;

/**
 * Outcome of scoring a single reading against a device's learned baseline.
 * Immutable value object — safe to pass to the alert pipeline.
 */
public class AnomalyResult {

    public enum Severity { NONE, WARNING, CRITICAL }

    private final boolean anomaly;
    private final Severity severity;
    private final String type;     // NORMAL | HARD_CEILING | Z_SCORE
    private final double value;    // the reading that was scored (W)
    private final double mean;     // device's EWMA baseline at scoring time (W)
    private final double zScore;   // standardised distance from baseline
    private final String reason;   // human-readable explanation

    private AnomalyResult(boolean anomaly, Severity severity, String type,
                          double value, double mean, double zScore, String reason) {
        this.anomaly = anomaly;
        this.severity = severity;
        this.type = type;
        this.value = value;
        this.mean = mean;
        this.zScore = zScore;
        this.reason = reason;
    }

    public static AnomalyResult normal(double value, double mean, double zScore) {
        return new AnomalyResult(false, Severity.NONE, "NORMAL", value, mean, zScore, "within baseline");
    }

    public static AnomalyResult hardCeiling(double value, double mean, double ceiling) {
        return new AnomalyResult(true, Severity.CRITICAL, "HARD_CEILING", value, mean, 0.0,
                String.format("reading %.0fW exceeds absolute ceiling %.0fW", value, ceiling));
    }

    public static AnomalyResult zScore(double value, double mean, double zScore) {
        return new AnomalyResult(true, Severity.WARNING, "Z_SCORE", value, mean, zScore,
                String.format("reading %.0fW is %.1f sigma from baseline %.0fW", value, zScore, mean));
    }

    public boolean isAnomaly()    { return anomaly; }
    public Severity getSeverity() { return severity; }
    public String getType()       { return type; }
    public double getValue()      { return value; }
    public double getMean()       { return mean; }
    public double getZScore()     { return zScore; }
    public String getReason()     { return reason; }

    @Override
    public String toString() {
        return "AnomalyResult{" + severity + " " + type + " value=" + value
             + " mean=" + mean + " z=" + zScore + " : " + reason + "}";
    }
}
