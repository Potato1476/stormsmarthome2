package com.storm.iotdata.fog.models;

import java.util.List;

/**
 * One MQTT message published by a gateway to the Cloud per (windowSizeMin, flush cycle).
 * Payload is GZIP-compressed JSON of this object.
 *
 * Semantics: CUMULATIVE — each batch contains the full accumulated state for every
 * active slice so far. Cloud must REPLACE (not add) stored values per (gatewayId, key).
 */
public class AggregatedBatch {
    public String gatewayId;
    public long flushTimestamp;   // epoch ms of this flush
    public int windowSizeMin;     // window size in minutes (1, 5, 10, 15, 30)
    public List<AggregatedRecord> deviceRecords;

    public AggregatedBatch() {}

    public AggregatedBatch(String gatewayId, long flushTimestamp, int windowSizeMin,
                            List<AggregatedRecord> deviceRecords) {
        this.gatewayId = gatewayId;
        this.flushTimestamp = flushTimestamp;
        this.windowSizeMin = windowSizeMin;
        this.deviceRecords = deviceRecords;
    }
}
