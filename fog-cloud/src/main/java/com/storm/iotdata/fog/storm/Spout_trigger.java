package com.storm.iotdata.fog.storm;

import com.storm.iotdata.fog.CloudConfig;
import org.apache.storm.spout.SpoutOutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.base.BaseRichSpout;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.tuple.Fields;
import org.apache.storm.tuple.Values;

import java.util.Map;

/**
 * Emits a trigger tuple every flushIntervalSec seconds to drive
 * Bolt_cloudMerge's periodic merge-and-save cycle.
 */
public class Spout_trigger extends BaseRichSpout {

    private final CloudConfig config;
    private SpoutOutputCollector collector;
    private long lastEmitMs = 0;

    public Spout_trigger(CloudConfig config) {
        this.config = config;
    }

    @Override
    public void open(Map conf, TopologyContext context, SpoutOutputCollector collector) {
        this.collector = collector;
    }

    @Override
    public void nextTuple() {
        long now = System.currentTimeMillis();
        if (now - lastEmitMs < config.getFlushIntervalSec() * 1000L) {
            try { Thread.sleep(100); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            return;
        }
        lastEmitMs = now;
        collector.emit("trigger", new Values(config.getFlushIntervalSec()));
    }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        declarer.declareStream("trigger", new Fields("intervalSec"));
    }
}
