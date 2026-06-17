package com.storm.iotdata.fog.alert;

import org.junit.Test;

import static org.junit.Assert.*;

public class RouteRegistryTest {

    private static final String ADMIN = "https://hooks.slack.com/services/ADMIN/x/y";
    private static final String H0 = "https://hooks.slack.com/services/HOUSE0/x/y";
    private static final String H3 = "https://hooks.slack.com/services/HOUSE3/x/y";

    private static final String JSON =
            "{ \"default\": \"" + ADMIN + "\", " +
            "  \"routes\": { \"0\": \"" + H0 + "\", \"3\": \"" + H3 + "\" } }";

    @Test
    public void mappedHouseResolvesToItsOwnWebhook() {
        RouteRegistry r = RouteRegistry.fromJson(JSON, "");
        assertEquals(H0, r.resolve(0));
        assertEquals(H3, r.resolve(3));
    }

    @Test
    public void unmappedHouseFallsBackToDefault() {
        RouteRegistry r = RouteRegistry.fromJson(JSON, "");
        assertEquals(ADMIN, r.resolve(7));
        assertEquals(ADMIN, r.resolve(99));
    }

    @Test
    public void fallbackDefaultUsedWhenJsonHasNoDefault() {
        // JSON omits "default" -> the constructor-supplied fallback (e.g. SLACK_WEBHOOK_URL) wins.
        String json = "{ \"routes\": { \"1\": \"" + H0 + "\" } }";
        RouteRegistry r = RouteRegistry.fromJson(json, ADMIN);
        assertEquals(H0, r.resolve(1));
        assertEquals(ADMIN, r.resolve(2));
    }

    @Test
    public void blankOrInvalidJsonYieldsFallbackOnlyRegistry() {
        // Missing/garbage config must never throw: it degrades to "everything -> fallback".
        RouteRegistry r1 = RouteRegistry.fromJson(null, ADMIN);
        RouteRegistry r2 = RouteRegistry.fromJson("not json {{{", ADMIN);
        RouteRegistry r3 = RouteRegistry.fromJson("", ADMIN);
        for (RouteRegistry r : new RouteRegistry[]{r1, r2, r3}) {
            assertEquals(ADMIN, r.resolve(0));
            assertEquals(ADMIN, r.resolve(5));
        }
    }

    @Test
    public void emptyWhenNeitherRoutesNorDefaultConfigured() {
        RouteRegistry r = RouteRegistry.fromJson("{}", "");
        assertTrue(r.isEmpty());
        assertEquals("", r.resolve(0));
    }

    @Test
    public void notEmptyWhenAtLeastOneDestinationExists() {
        assertFalse(RouteRegistry.fromJson("{}", ADMIN).isEmpty());
        assertFalse(RouteRegistry.fromJson(JSON, "").isEmpty());
    }

    @Test
    public void missingFileDegradesToFallback() {
        RouteRegistry r = RouteRegistry.fromJsonFile("/no/such/path/alert-routes.json", ADMIN);
        assertEquals(ADMIN, r.resolve(0));
    }
}
