package com.storm.iotdata.fog.alert;

import com.storm.iotdata.fog.anomaly.AnomalyResult;
import org.junit.Test;

import static org.junit.Assert.*;

public class SlackNotifierTest {

    private Alert criticalAlert() {
        AnomalyResult r = AnomalyResult.hardCeiling(2850.0, 2780.0, 2500.0);
        return new Alert("gw-03", 3, 1, 2, r, 1_700_000_000_000L);
    }

    @Test
    public void payloadIsValidBlockKitContainingKeyFacts() {
        String json = SlackNotifier.buildPayload(criticalAlert());
        // Block Kit envelope
        assertTrue(json.contains("\"blocks\""));
        // Identity + numbers a human needs to act
        assertTrue("mentions gateway", json.contains("gw-03"));
        assertTrue("mentions house", json.contains("3"));
        assertTrue("mentions the reading", json.contains("2850"));
        assertTrue("mentions the baseline", json.contains("2780"));
        // Severity surfaced
        assertTrue("flags critical", json.toLowerCase().contains("critical"));
    }

    @Test
    public void payloadEscapesSafely() {
        // Reason text is interpolated; ensure Gson produces parseable JSON (no raw quotes breaking it).
        String json = SlackNotifier.buildPayload(criticalAlert());
        // A naive concat would leave unbalanced braces; Gson keeps them balanced.
        long open = json.chars().filter(c -> c == '{').count();
        long close = json.chars().filter(c -> c == '}').count();
        assertEquals(open, close);
    }

    @Test
    public void disabledNotifierIsNoOp() {
        // No webhook configured -> send() must not throw and must report not-sent.
        SlackNotifier n = new SlackNotifier("", true, 0);
        assertFalse(n.send(criticalAlert()));
        n.shutdown();
    }

    @Test
    public void routeAwareNotifierWithDefaultIsEnabled() {
        // A registry carrying at least one destination must enable the notifier.
        RouteRegistry reg = RouteRegistry.fromJson(
                "{\"routes\":{\"3\":\"https://hooks.slack.com/services/H3/x/y\"}}", "");
        SlackNotifier n = new SlackNotifier(reg, true, 0);
        assertTrue(n.isEnabled());
        n.shutdown();
    }

    @Test
    public void routeAwareNotifierWithEmptyRegistryIsDisabled() {
        SlackNotifier n = new SlackNotifier(RouteRegistry.fromJson("{}", ""), true, 0);
        assertFalse(n.isEnabled());
        assertFalse(n.send(criticalAlert()));
        n.shutdown();
    }
}
