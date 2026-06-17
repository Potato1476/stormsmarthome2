package com.storm.iotdata.fog.anomaly;

import java.util.HashMap;
import java.util.Map;

/**
 * Lightweight online anomaly detector that runs entirely at the edge (Gateway) —
 * no training job, no cloud round-trip. This is the Fog advantage: detection
 * happens next to the data with sub-millisecond cost and a few bytes of state
 * per device.
 *
 * Two complementary signals:
 *
 *   1. HARD CEILING — an absolute power limit (W). Anything above it is an
 *      immediate CRITICAL, independent of history. Catches dangerous overloads
 *      from the very first reading (no warm-up needed).
 *
 *   2. EWMA Z-SCORE — each device gets an exponentially-weighted moving average
 *      mean and variance (West's incremental EWMVar). A reading more than
 *      `zThreshold` standard deviations from the device's own learned baseline
 *      is a WARNING. This adapts per device: 2 kW is normal for an oven but a
 *      red flag for a phone charger.
 *
 * State is O(devices): two doubles + a counter each. Not thread-safe; intended
 * to be owned by a single Storm bolt instance (fieldsGrouping keeps a device on
 * one instance).
 */
public class AnomalyDetector {

    /** Floor on the std used in the z-score, so a near-constant baseline can't blow the score up to infinity. */
    private static final double MIN_STD = 1.0; // watts

    private final double alpha;        // EWMA smoothing factor (0..1); higher = more reactive
    private final double zThreshold;   // sigma distance that counts as anomalous
    private final double hardCeiling;  // absolute power ceiling (W); <=0 disables
    private final int warmup;          // samples to observe before z-score detection activates

    private final Map<String, State> states = new HashMap<>();

    public AnomalyDetector(double alpha, double zThreshold, double hardCeiling, int warmup) {
        this.alpha = alpha;
        this.zThreshold = zThreshold;
        this.hardCeiling = hardCeiling;
        this.warmup = warmup;
    }

    /**
     * Score one reading for one device and fold it into that device's baseline.
     * Always updates state, even when no anomaly is reported.
     */
    public AnomalyResult update(String deviceKey, double value) {
        State s = states.computeIfAbsent(deviceKey, k -> new State());

        // Snapshot the baseline as it was *before* this reading — that's what we score against.
        double meanBefore = s.mean;
        double stdBefore = Math.sqrt(Math.max(s.variance, 0.0));
        long countBefore = s.count;

        s.observe(value, alpha);

        // 1. Absolute ceiling — fires regardless of warm-up.
        if (hardCeiling > 0 && value >= hardCeiling) {
            return AnomalyResult.hardCeiling(value, meanBefore, hardCeiling);
        }

        // 2. EWMA z-score — only once we have a baseline to compare against.
        if (countBefore >= warmup) {
            double std = Math.max(stdBefore, MIN_STD);
            double z = (value - meanBefore) / std;
            if (Math.abs(z) >= zThreshold) {
                return AnomalyResult.zScore(value, meanBefore, z);
            }
            return AnomalyResult.normal(value, meanBefore, z);
        }

        return AnomalyResult.normal(value, meanBefore, 0.0);
    }

    /** Per-device EWMA mean + variance (West 1979 incremental form). */
    private static final class State {
        double mean = 0.0;
        double variance = 0.0;
        long count = 0;

        void observe(double value, double alpha) {
            if (count == 0) {
                mean = value;        // seed with first reading; variance stays 0
            } else {
                double diff = value - mean;
                double incr = alpha * diff;
                mean += incr;
                variance = (1 - alpha) * (variance + diff * incr);
            }
            count++;
        }
    }
}
