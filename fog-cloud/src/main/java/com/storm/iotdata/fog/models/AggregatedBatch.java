package com.storm.iotdata.fog.models;

import java.io.Serializable;
import java.util.List;

public class AggregatedBatch implements Serializable {
    private static final long serialVersionUID = 1L;
    public String gatewayId;
    public long flushTimestamp;
    public int windowSizeMin;
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
