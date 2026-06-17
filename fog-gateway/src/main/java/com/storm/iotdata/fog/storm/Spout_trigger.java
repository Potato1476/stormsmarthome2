package com.storm.iotdata.fog.storm;

import com.storm.iotdata.fog.GatewayConfig;
import org.apache.storm.spout.SpoutOutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.base.BaseRichSpout;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.tuple.Fields;
import org.apache.storm.tuple.Values;

import java.util.Map;

/**
 * Emits a "trigger" tuple every flushIntervalSec seconds.
 * Bolt_ingest flushes accumulated state to Cloud MQTT on each trigger.
 */
public class Spout_trigger extends BaseRichSpout {

    private final GatewayConfig config;
    private SpoutOutputCollector collector;

    public Spout_trigger(GatewayConfig config) {
        this.config = config;
    }

    @Override
    public void open(Map conf, TopologyContext context, SpoutOutputCollector collector) {
        this.collector = collector;
    }

    @Override
    public void nextTuple() {
        try {
            Thread.sleep(config.getFlushIntervalSec() * 1000L);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        collector.emit("trigger", new Values(config.getFlushIntervalSec()));
    }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        declarer.declareStream("trigger", new Fields("intervalSec"));
    }
}
