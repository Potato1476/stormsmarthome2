package org.apache.storm.metricstore;

import org.apache.storm.metric.StormMetricsRegistry;
import java.util.Map;

/**
 * No-op MetricStore — disables Storm's RocksDB metric persistence.
 * Required on ARM64 (Apple Silicon) where the bundled RocksDB JNI is AMD64-only.
 * Configured via storm.yaml: storm.metricstore.class: "org.apache.storm.metricstore.NullMetricStore"
 */
public class NullMetricStore implements MetricStore {

    @Override
    public void prepare(Map<String, Object> config, StormMetricsRegistry registry) {}

    @Override
    public void insert(Metric metric) {}

    @Override
    public boolean populateValue(Metric metric) { return false; }

    @Override
    public void close() {}

    @Override
    public void scan(FilterOptions filter, MetricStore.ScanCallback callback) {}
}
