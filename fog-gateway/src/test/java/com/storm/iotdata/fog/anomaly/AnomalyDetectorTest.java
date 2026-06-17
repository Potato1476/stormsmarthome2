package com.storm.iotdata.fog.anomaly;

import org.junit.Test;

import static org.junit.Assert.*;

/**
 * Unit tests for the edge-side anomaly detector.
 *
 * The detector combines two signals:
 *   - a fixed absolute ceiling (immediate CRITICAL, works even before warm-up), and
 *   - an EWMA z-score that learns each device's baseline online (no training, no cloud).
 */
public class AnomalyDetectorTest {

    private static final String DEV = "3:1:2";

    /** alpha=0.3, z>=3.0, ceiling=2500W, warmup=10 samples. */
    private AnomalyDetector detector() {
        return new AnomalyDetector(0.3, 3.0, 2500.0, 10);
    }

    @Test
    public void hardCeilingFiresCriticalOnFirstSample() {
        AnomalyResult r = detector().update(DEV, 2850.0);
        assertTrue(r.isAnomaly());
        assertEquals(AnomalyResult.Severity.CRITICAL, r.getSeverity());
        assertEquals("HARD_CEILING", r.getType());
        assertEquals(2850.0, r.getValue(), 1e-9);
    }

    @Test
    public void stableValuesDuringWarmupAreNormal() {
        AnomalyDetector d = detector();
        for (int i = 0; i < 9; i++) {
            AnomalyResult r = d.update(DEV, 100.0 + (i % 2)); // ~100W, well under ceiling
            assertFalse("sample " + i + " should be normal during warm-up", r.isAnomaly());
            assertEquals(AnomalyResult.Severity.NONE, r.getSeverity());
        }
    }

    @Test
    public void stableValuesAfterWarmupStayNormal() {
        AnomalyDetector d = detector();
        for (int i = 0; i < 30; i++) {
            AnomalyResult r = d.update(DEV, 100.0 + (i % 3)); // tiny jitter around 100W
            assertFalse("no false positive on stable load (sample " + i + ")", r.isAnomaly());
        }
    }

    @Test
    public void spikeAfterWarmupFiresZScoreAnomaly() {
        AnomalyDetector d = detector();
        // Warm up on a tight ~100W baseline so the std is small.
        for (int i = 0; i < 20; i++) {
            d.update(DEV, 100.0 + (i % 2));
        }
        // A 900W reading is a huge departure from the ~100W baseline, but under the 2500W ceiling.
        AnomalyResult r = d.update(DEV, 900.0);
        assertTrue("a large departure from baseline must flag", r.isAnomaly());
        assertEquals("Z_SCORE", r.getType());
        assertTrue("z-score should exceed threshold, was " + r.getZScore(), r.getZScore() >= 3.0);
    }

    @Test
    public void devicesAreTrackedIndependently() {
        AnomalyDetector d = detector();
        for (int i = 0; i < 20; i++) {
            d.update("a", 100.0 + (i % 2));        // tight ~100W baseline
            d.update("b", 2000.0 + (i % 5) * 100); // naturally swings 2000..2400W
        }
        // 900W is anomalous for device "a" (~100 baseline) but well within "b"'s normal swing.
        assertTrue(d.update("a", 900.0).isAnomaly());
        assertFalse(d.update("b", 2100.0).isAnomaly());
    }

    @Test
    public void moderateZScoreIsWarning() {
        AnomalyDetector d = detector();
        for (int i = 0; i < 20; i++) d.update(DEV, 100.0 + (i % 2));
        // A departure just past the z threshold (but far below the hard ceiling) is a WARNING.
        AnomalyResult r = d.update(DEV, 300.0);
        assertTrue(r.isAnomaly());
        assertEquals("Z_SCORE", r.getType());
        assertEquals(AnomalyResult.Severity.WARNING, r.getSeverity());
    }
}
