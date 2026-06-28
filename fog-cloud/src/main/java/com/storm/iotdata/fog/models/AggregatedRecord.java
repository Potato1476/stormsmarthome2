package com.storm.iotdata.fog.models;

public class AggregatedRecord implements java.io.Serializable {
    private static final long serialVersionUID = 1L;
    public int houseId;
    public int householdId;
    public int plugId;
    public String year;
    public String month;
    public String day;
    public int sliceIndex;
    public double count;
    public double sum;
    public long eventTsMs; // [metrics] freshest produced epoch-ms among contributing readings

    public AggregatedRecord() {}

    public AggregatedRecord(int houseId, int householdId, int plugId,
                             String year, String month, String day,
                             int sliceIndex, double count, double sum) {
        this.houseId = houseId;
        this.householdId = householdId;
        this.plugId = plugId;
        this.year = year;
        this.month = month;
        this.day = day;
        this.sliceIndex = sliceIndex;
        this.count = count;
        this.sum = sum;
    }

    public double getAvg() {
        return count == 0 ? 0.0 : sum / count;
    }

    /** Unique device+timeslice key: houseId:householdId:plugId:year:month:day:sliceIndex */
    public String getKey() {
        return houseId + ":" + householdId + ":" + plugId + ":"
             + year + ":" + month + ":" + day + ":" + sliceIndex;
    }
}
