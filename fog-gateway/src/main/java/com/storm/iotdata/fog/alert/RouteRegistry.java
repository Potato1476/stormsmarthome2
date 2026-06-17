package com.storm.iotdata.fog.alert;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

/**
 * Maps a {@code houseId} to the Slack webhook of that house's own channel, so each
 * household only receives alerts for its own devices (multi-tenant data isolation).
 *
 * Config is a small JSON document, mounted read-only into every gateway:
 * <pre>
 * {
 *   "default": "https://hooks.slack.com/services/&lt;admin channel&gt;",
 *   "routes": { "0": "https://.../house0", "1": "https://.../house1" }
 * }
 * </pre>
 * A house with no entry falls back to {@code default} (the admin catch-all), so an
 * alert is never lost silently. Parsing is fail-safe: a missing or malformed file
 * degrades to a fallback-only registry (preserves the legacy single-webhook
 * behaviour) instead of throwing on a Pi-class node at startup.
 */
public class RouteRegistry {

    private final Map<Integer, String> routes;
    private final String defaultUrl;

    RouteRegistry(Map<Integer, String> routes, String defaultUrl) {
        this.routes = routes == null ? new HashMap<>() : routes;
        this.defaultUrl = defaultUrl == null ? "" : defaultUrl.trim();
    }

    /** Webhook for this house, or the default; empty string when nothing is configured. */
    public String resolve(int houseId) {
        String url = routes.get(houseId);
        return (url != null && !url.isEmpty()) ? url : defaultUrl;
    }

    /** True when there is no usable destination at all (routing effectively disabled). */
    public boolean isEmpty() {
        if (!defaultUrl.isEmpty()) return false;
        for (String url : routes.values()) {
            if (url != null && !url.trim().isEmpty()) return false;
        }
        return true;
    }

    /** Number of per-house routes configured (excludes the default). */
    public int size() {
        return routes.size();
    }

    /**
     * Parse a routes JSON string. {@code fallbackDefault} (e.g. SLACK_WEBHOOK_URL) is
     * used when the JSON omits "default". Never throws — bad input yields a
     * fallback-only registry.
     */
    public static RouteRegistry fromJson(String json, String fallbackDefault) {
        Map<Integer, String> routes = new HashMap<>();
        String def = fallbackDefault;
        if (json != null && !json.trim().isEmpty()) {
            try {
                JsonObject root = JsonParser.parseString(json).getAsJsonObject();
                if (root.has("default") && !root.get("default").isJsonNull()) {
                    String d = root.get("default").getAsString().trim();
                    if (!d.isEmpty()) def = d;
                }
                if (root.has("routes") && root.get("routes").isJsonObject()) {
                    JsonObject map = root.getAsJsonObject("routes");
                    for (Map.Entry<String, com.google.gson.JsonElement> e : map.entrySet()) {
                        try {
                            int houseId = Integer.parseInt(e.getKey().trim());
                            String url = e.getValue().getAsString().trim();
                            if (!url.isEmpty()) routes.put(houseId, url);
                        } catch (NumberFormatException ignored) {
                            System.err.println("[RouteRegistry] skipping non-numeric houseId key: " + e.getKey());
                        }
                    }
                }
            } catch (RuntimeException bad) {
                System.err.println("[RouteRegistry] invalid routes JSON, using fallback only: " + bad.getMessage());
                return new RouteRegistry(new HashMap<>(), fallbackDefault);
            }
        }
        return new RouteRegistry(routes, def);
    }

    /** Load routes from a file path; a missing/unreadable file degrades to fallback only. */
    public static RouteRegistry fromJsonFile(String path, String fallbackDefault) {
        if (path == null || path.trim().isEmpty()) {
            return new RouteRegistry(new HashMap<>(), fallbackDefault);
        }
        try {
            byte[] bytes = Files.readAllBytes(Paths.get(path.trim()));
            return fromJson(new String(bytes, StandardCharsets.UTF_8), fallbackDefault);
        } catch (Exception e) {
            System.err.println("[RouteRegistry] could not read " + path + " (" + e.getMessage()
                    + "); falling back to single default webhook.");
            return new RouteRegistry(new HashMap<>(), fallbackDefault);
        }
    }
}
