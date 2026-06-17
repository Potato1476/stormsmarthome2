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
                "  PRIMARY KEY (houseId, householdId, deviceId, year, month, day, sliceIndex, sliceGap)" +
                ") ENGINE=InnoDB DEFAULT CHARSET=utf8"
            );
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
    public void upsertDeviceData(Map<String, double[]> acc, int sliceGap) {
        if (acc.isEmpty()) return;
        String sql = "REPLACE INTO fog_device_data " +
                     "(houseId, householdId, deviceId, year, month, day, sliceIndex, sliceGap, sumValue, count, updatedAt) " +
                     "VALUES (?,?,?,?,?,?,?,?,?,?,?)";
        long now = System.currentTimeMillis();
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
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
                ps.setLong(11, now);
                ps.addBatch();
                if (++batch % 500 == 0) ps.executeBatch();
            }
            ps.executeBatch();
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
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
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
                ps.addBatch();
                if (++batch % 500 == 0) ps.executeBatch();
            }
            ps.executeBatch();
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
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
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
                ps.addBatch();
                if (++batch % 500 == 0) ps.executeBatch();
            }
            ps.executeBatch();
        } catch (SQLException ex) {
            System.err.println("[FogDB_store] upsertHouseData failed: " + ex.getMessage());
        }
    }
}
