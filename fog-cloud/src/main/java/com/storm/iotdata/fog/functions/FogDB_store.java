package com.storm.iotdata.fog.functions;

import com.storm.iotdata.fog.CloudConfig;

import java.sql.*;
import java.util.Map;

/**
 * Database operations for Fog Cloud tier.
 * Writes to fog_device_data, fog_house_data, fog_household_data tables
 * (separate from monolithic tables — keeps baselines independent).
 *
 * Uses REPLACE INTO for idempotent upserts:
 * each Cloud trigger overwrites previous partial aggregates for the same slice,
 * so the DB always holds the latest cumulative state.
 */
public class FogDB_store {

    private final CloudConfig config;

    public FogDB_store(CloudConfig config) {
        this.config = config;
    }

    public Connection getConnection() throws SQLException {
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            throw new SQLException("MySQL driver not found", e);
        }
        return DriverManager.getConnection(config.getDbJdbcUrl(), config.getDbUser(), config.getDbPass());
    }

    /** Creates all fog_ tables if they don't exist. Called once at Cloud startup. */
    public void initFogTables() {
        try (Connection conn = getConnection(); Statement st = conn.createStatement()) {
            st.executeUpdate(
                "CREATE TABLE IF NOT EXISTS fog_device_data (" +
                "  houseId INT NOT NULL," +
                "  householdId INT NOT NULL," +
                "  deviceId INT NOT NULL," +
                "  year VARCHAR(4) NOT NULL," +
                "  month VARCHAR(2) NOT NULL," +
                "  day VARCHAR(2) NOT NULL," +
                "  sliceIndex INT NOT NULL," +
                "  sliceGap INT NOT NULL," +
                "  sumValue DOUBLE DEFAULT 0," +
                "  count DOUBLE DEFAULT 0," +
                "  updatedAt BIGINT," +
                "  event_ts BIGINT DEFAULT 0," +
                "  firstWrittenAt BIGINT DEFAULT 0," +
                "  PRIMARY KEY (houseId, householdId, deviceId, year, month, day, sliceIndex, sliceGap)" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8"
            );
            // [metrics] ensure event_ts / firstWrittenAt exist on pre-existing DBs
            // (MySQL lacks ADD COLUMN IF NOT EXISTS — try/catch is the idiom used here).
            try { st.executeUpdate("ALTER TABLE fog_device_data ADD COLUMN event_ts BIGINT DEFAULT 0"); }
            catch (SQLException ignore) { /* column already present */ }
            try { st.executeUpdate("ALTER TABLE fog_device_data ADD COLUMN firstWrittenAt BIGINT DEFAULT 0"); }
            catch (SQLException ignore) { /* column already present */ }
            st.executeUpdate(
                "CREATE TABLE IF NOT EXISTS fog_household_data (" +
                "  houseId INT NOT NULL," +
                "  householdId INT NOT NULL," +
                "  year VARCHAR(4) NOT NULL," +
                "  month VARCHAR(2) NOT NULL," +
                "  day VARCHAR(2) NOT NULL," +
                "  sliceIndex INT NOT NULL," +
                "  sliceGap INT NOT NULL," +
                "  sumValue DOUBLE DEFAULT 0," +
                "  count DOUBLE DEFAULT 0," +
                "  updatedAt BIGINT," +
                "  PRIMARY KEY (houseId, householdId, year, month, day, sliceIndex, sliceGap)" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8"
            );
            st.executeUpdate(
                "CREATE TABLE IF NOT EXISTS fog_house_data (" +
                "  houseId INT NOT NULL," +
                "  year VARCHAR(4) NOT NULL," +
                "  month VARCHAR(2) NOT NULL," +
                "  day VARCHAR(2) NOT NULL," +
                "  sliceIndex INT NOT NULL," +
                "  sliceGap INT NOT NULL," +
                "  sumValue DOUBLE DEFAULT 0," +
                "  count DOUBLE DEFAULT 0," +
                "  updatedAt BIGINT," +
                "  PRIMARY KEY (houseId, year, month, day, sliceIndex, sliceGap)" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8"
            );
            // Forecast output (parity with monolithic Bolt_forecast). One generic table
            // for device/household/house levels: level + opaque key + window.
            st.executeUpdate(
                "CREATE TABLE IF NOT EXISTS fog_forecast (" +
                "  level VARCHAR(16) NOT NULL," +
                "  keyStr VARCHAR(128) NOT NULL," +
                "  sliceGap INT NOT NULL," +
                "  forecastValue DOUBLE DEFAULT 0," +
                "  updatedAt BIGINT," +
                "  PRIMARY KEY (level, keyStr, sliceGap)" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8"
            );
            System.out.println("[FogDB_store] Fog tables initialized.");
        } catch (SQLException e) {
            System.err.println("[FogDB_store] initFogTables failed: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Upsert device-level aggregates.
     * accKey format: "houseId:householdId:plugId:year:month:day:sliceIndex"
     * acc value: double[]{count, sum}
     */
    public void upsertDeviceData(Map<String, double[]> acc, Map<String, Long> eventTs, int sliceGap) {
        if (acc.isEmpty()) return;
        // INSERT ... ON DUPLICATE KEY UPDATE (not REPLACE) so firstWrittenAt is set
        // ONCE (first insert) and never overwritten — that gives e2e_first_write_latency.
        // updatedAt is always refreshed — that gives e2e_last_write_latency (artifact).
        // The two are distinct metrics (prompt §2.2); the SQL keeps them independent.
        String sql = "INSERT INTO fog_device_data " +
                     "(houseId, householdId, deviceId, year, month, day, sliceIndex, sliceGap, sumValue, count, updatedAt, event_ts, firstWrittenAt) " +
                     "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) " +
                     "ON DUPLICATE KEY UPDATE sumValue=VALUES(sumValue), count=VALUES(count), " +
                     "updatedAt=VALUES(updatedAt), event_ts=VALUES(event_ts)";  // firstWrittenAt intentionally untouched
        boolean perRow = config.isCloudMergePerRow();
        long now = System.currentTimeMillis();
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            conn.setAutoCommit(perRow);   // batched: one txn/flush · perrow: autocommit each row (OLD path)
            int batch = 0;
            for (Map.Entry<String, double[]> e : acc.entrySet()) {
                String[] p = e.getKey().split(":");
                ps.setInt(1, Integer.parseInt(p[0]));  // houseId
                ps.setInt(2, Integer.parseInt(p[1]));  // householdId
                ps.setInt(3, Integer.parseInt(p[2]));  // deviceId (plugId)
                ps.setString(4, p[3]);                 // year
                ps.setString(5, p[4]);                 // month
                ps.setString(6, p[5]);                 // day
                ps.setInt(7, Integer.parseInt(p[6]));  // sliceIndex
                ps.setInt(8, sliceGap);
                ps.setDouble(9, e.getValue()[1]);      // sumValue
                ps.setDouble(10, e.getValue()[0]);     // count
                ps.setLong(11, now);                   // updatedAt (always)
                ps.setLong(12, eventTs == null ? 0L : eventTs.getOrDefault(e.getKey(), 0L)); // event_ts
                ps.setLong(13, now);                   // firstWrittenAt (ignored on dup-key)
                if (perRow) {
                    ps.executeUpdate();                // N round-trips, N commits (reproduces 318.9%)
                } else {
                    ps.addBatch();
                    if (++batch % 500 == 0) ps.executeBatch();
                }
            }
            if (!perRow) { ps.executeBatch(); conn.commit(); }
        } catch (SQLException ex) {
            System.err.println("[FogDB_store] upsertDeviceData failed: " + ex.getMessage());
        }
    }

    /**
     * Upsert household-level aggregates.
     * hhKey format: "houseId:householdId:year:month:day:sliceIndex"
     */
    public void upsertHouseholdData(Map<String, double[]> acc, int sliceGap) {
        if (acc.isEmpty()) return;
        String sql = "REPLACE INTO fog_household_data " +
                     "(houseId, householdId, year, month, day, sliceIndex, sliceGap, sumValue, count, updatedAt) " +
                     "VALUES (?,?,?,?,?,?,?,?,?,?)";
        long now = System.currentTimeMillis();
        boolean perRow = config.isCloudMergePerRow();
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            conn.setAutoCommit(perRow);   // batched: one txn/flush · perrow: autocommit each row
            int batch = 0;
            for (Map.Entry<String, double[]> e : acc.entrySet()) {
                String[] p = e.getKey().split(":");
                ps.setInt(1, Integer.parseInt(p[0]));
                ps.setInt(2, Integer.parseInt(p[1]));
                ps.setString(3, p[2]);
                ps.setString(4, p[3]);
                ps.setString(5, p[4]);
                ps.setInt(6, Integer.parseInt(p[5]));
                ps.setInt(7, sliceGap);
                ps.setDouble(8, e.getValue()[1]);
                ps.setDouble(9, e.getValue()[0]);
                ps.setLong(10, now);
                if (perRow) { ps.executeUpdate(); }
                else { ps.addBatch(); if (++batch % 500 == 0) ps.executeBatch(); }
            }
            if (!perRow) { ps.executeBatch(); conn.commit(); }
        } catch (SQLException ex) {
            System.err.println("[FogDB_store] upsertHouseholdData failed: " + ex.getMessage());
        }
    }

    /**
     * Upsert house-level aggregates.
     * houseKey format: "houseId:year:month:day:sliceIndex"
     */
    public void upsertHouseData(Map<String, double[]> acc, int sliceGap) {
        if (acc.isEmpty()) return;
        String sql = "REPLACE INTO fog_house_data " +
                     "(houseId, year, month, day, sliceIndex, sliceGap, sumValue, count, updatedAt) " +
                     "VALUES (?,?,?,?,?,?,?,?,?)";
        long now = System.currentTimeMillis();
        boolean perRow = config.isCloudMergePerRow();
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            conn.setAutoCommit(perRow);   // batched: one txn/flush · perrow: autocommit each row
            int batch = 0;
            for (Map.Entry<String, double[]> e : acc.entrySet()) {
                String[] p = e.getKey().split(":");
                ps.setInt(1, Integer.parseInt(p[0]));
                ps.setString(2, p[1]);
                ps.setString(3, p[2]);
                ps.setString(4, p[3]);
                ps.setInt(5, Integer.parseInt(p[4]));
                ps.setInt(6, sliceGap);
                ps.setDouble(7, e.getValue()[1]);
                ps.setDouble(8, e.getValue()[0]);
                ps.setLong(9, now);
                if (perRow) { ps.executeUpdate(); }
                else { ps.addBatch(); if (++batch % 500 == 0) ps.executeBatch(); }
            }
            if (!perRow) { ps.executeBatch(); conn.commit(); }
        } catch (SQLException ex) {
            System.err.println("[FogDB_store] upsertHouseData failed: " + ex.getMessage());
        }
    }

    /**
     * Upsert forecast values (one transaction). fc: keyStr -> forecastValue.
     * level ∈ {device, household, house}. Mirrors monolithic forecast persistence
     * so the Fog cloud performs the same write workload.
     */
    public void upsertForecast(Map<String, Double> fc, String level, int sliceGap) {
        if (fc == null || fc.isEmpty()) return;
        String sql = "REPLACE INTO fog_forecast (level, keyStr, sliceGap, forecastValue, updatedAt) " +
                     "VALUES (?,?,?,?,?)";
        long now = System.currentTimeMillis();
        boolean perRow = config.isCloudMergePerRow();
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            conn.setAutoCommit(perRow);   // batched: one txn/flush · perrow: autocommit each row
            int batch = 0;
            for (Map.Entry<String, Double> e : fc.entrySet()) {
                ps.setString(1, level);
                ps.setString(2, e.getKey());
                ps.setInt(3, sliceGap);
                ps.setDouble(4, e.getValue());
                ps.setLong(5, now);
                if (perRow) { ps.executeUpdate(); }
                else { ps.addBatch(); if (++batch % 500 == 0) ps.executeBatch(); }
            }
            if (!perRow) { ps.executeBatch(); conn.commit(); }
        } catch (SQLException ex) {
            System.err.println("[FogDB_store] upsertForecast failed: " + ex.getMessage());
        }
    }
}
