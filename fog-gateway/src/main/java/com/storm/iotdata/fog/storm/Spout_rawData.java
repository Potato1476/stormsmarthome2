package com.storm.iotdata.fog.storm;

import com.storm.iotdata.fog.GatewayConfig;
import org.apache.storm.spout.SpoutOutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.IRichSpout;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.tuple.Fields;
import org.apache.storm.tuple.Values;
import org.eclipse.paho.client.mqttv3.*;

import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * Subscribes to the raw IoT data MQTT topic and emits only messages
 * whose houseId falls within this gateway's assigned house range.
 *
 * Input CSV format: _,timestamp,value,property,plugId,householdId,houseId
 * Filtered on: property == 1 (load readings only) AND houseId in config.getHouseIds()
 */
public class Spout_rawData implements MqttCallback, IRichSpout {

    private final GatewayConfig config;
    private transient SpoutOutputCollector collector;
    private transient MqttClient client;
    private final LinkedBlockingQueue<String> queue = new LinkedBlockingQueue<>(50000);
    private long lastLog = System.currentTimeMillis();
    private long received = 0, emitted = 0, filtered = 0;

    public Spout_rawData(GatewayConfig config) {
        this.config = config;
    }

    @Override
    public void open(Map conf, TopologyContext context, SpoutOutputCollector collector) {
        this.collector = collector;
        connect();
    }

    private void connect() {
        System.out.printf("[Spout_rawData-%s] Connecting to %s ...%n", config.getGatewayId(), config.getSourceMqttUrl());
        try {
            if (client != null) client.close(true);
            client = new MqttClient(config.getSourceMqttUrl(), "gateway-spout-" + config.getGatewayId());
            MqttConnectOptions opts = new MqttConnectOptions();
            opts.setAutomaticReconnect(true);
            opts.setConnectionTimeout(15);
            client.connect(opts);
            client.setCallback(this);
            System.out.printf("[Spout_rawData-%s] Connected.%n", config.getGatewayId());
        } catch (MqttException e) {
            e.printStackTrace();
            try { Thread.sleep(10000); connect(); } catch (InterruptedException ignored) {}
        }
    }

    @Override
    public void activate() {
        try {
            client.subscribe(config.getMqttDataTopic(), 1);
            System.out.printf("[Spout_rawData-%s] Subscribed to %s%n", config.getGatewayId(), config.getMqttDataTopic());
        } catch (MqttException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void deactivate() {
        try { client.unsubscribe(config.getMqttDataTopic()); } catch (MqttException ignored) {}
    }

    @Override
    public void messageArrived(String topic, MqttMessage message) {
        queue.offer(message.toString());
        received++;
    }

    @Override
    public void connectionLost(Throwable cause) {
        System.out.printf("[Spout_rawData-%s] Connection lost: %s%n", config.getGatewayId(), cause.getMessage());
    }

    @Override
    public void deliveryComplete(IMqttDeliveryToken token) {}

    @Override
    public void nextTuple() {
        String msg = queue.poll();
        if (msg == null) return;
        try {
            String[] f = msg.split(",");
            if (f.length < 7) return;
            int property = Integer.parseInt(f[3].trim());
            if (property != 1) return;                                  // load readings only
            int houseId = Integer.parseInt(f[6].trim());
            if (!config.getHouseIds().contains(houseId)) {             // gateway shard filter
                filtered++;
                return;
            }
            // Fields: timestamp, value, property, plugId, householdId, houseId
            collector.emit("data",
                new Values(f[1].trim(), f[2].trim(), f[3].trim(), f[4].trim(), f[5].trim(), f[6].trim()),
                msg);
            emitted++;
        } catch (Exception e) {
            e.printStackTrace();
        }
        if (System.currentTimeMillis() - lastLog > 30000) {
            System.out.printf("[Spout_rawData-%s] received=%d emitted=%d filtered=%d queue=%d%n",
                config.getGatewayId(), received, emitted, filtered, queue.size());
            lastLog = System.currentTimeMillis();
        }
    }

    @Override
    public void ack(Object msgId) {}

    @Override
    public void fail(Object msgId) {}

    @Override
    public void close() {
        try { if (client != null) client.disconnect(); } catch (MqttException ignored) {}
    }

    @Override
    public Map<String, Object> getComponentConfiguration() { return null; }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        declarer.declareStream("data",
            new Fields("timestamp", "value", "property", "plugId", "householdId", "houseId"));
    }
}
