package com.storm.iotdata.fog.storm;

import com.google.gson.Gson;
import com.storm.iotdata.fog.CloudConfig;
import com.storm.iotdata.fog.models.AggregatedBatch;
import org.apache.storm.spout.SpoutOutputCollector;
import org.apache.storm.task.TopologyContext;
import org.apache.storm.topology.IRichSpout;
import org.apache.storm.topology.OutputFieldsDeclarer;
import org.apache.storm.tuple.Fields;
import org.apache.storm.tuple.Values;
import org.eclipse.paho.client.mqttv3.*;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.zip.GZIPInputStream;

/**
 * Subscribes to "fog/agg/#" and emits AggregatedBatch objects.
 * Payload is GZIP-compressed JSON (produced by Bolt_ingest on gateways).
 *
 * This spout receives ~8 gateways × 5 windows × 1 message/60s ≈ 40 msg/min.
 * Compare to Monolithic which ingests 400 raw msgs/sec — ~96% reduction.
 */
public class Spout_aggregated implements MqttCallback, IRichSpout {

    private final CloudConfig config;
    private SpoutOutputCollector collector;
    private MqttClient client;
    private final LinkedBlockingQueue<AggregatedBatch> batches = new LinkedBlockingQueue<>(10000);
    private transient Gson gson;
    private long received = 0, emitted = 0;
    private long lastLog = System.currentTimeMillis();

    public Spout_aggregated(CloudConfig config) {
        this.config = config;
    }

    @Override
    public void open(Map conf, TopologyContext context, SpoutOutputCollector collector) {
        this.collector = collector;
        this.gson = new Gson();
        connect();
    }

    private void connect() {
        System.out.printf("[Spout_aggregated] Connecting to %s ...%n", config.getCloudMqttUrl());
        try {
            if (client != null) client.close(true);
            client = new MqttClient(config.getCloudMqttUrl(), "cloud-spout-aggregated");
            MqttConnectOptions opts = new MqttConnectOptions();
            opts.setAutomaticReconnect(true);
            opts.setConnectionTimeout(15);
            client.connect(opts);
            client.setCallback(this);
            System.out.println("[Spout_aggregated] Connected.");
        } catch (MqttException e) {
            e.printStackTrace();
            try { Thread.sleep(10000); connect(); } catch (InterruptedException ignored) {}
        }
    }

    @Override
    public void activate() {
        try {
            client.subscribe(config.getAggSubscribeTopic(), 1);
            System.out.printf("[Spout_aggregated] Subscribed to %s%n", config.getAggSubscribeTopic());
        } catch (MqttException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void deactivate() {
        try { client.unsubscribe(config.getAggSubscribeTopic()); } catch (MqttException ignored) {}
    }

    @Override
    public void messageArrived(String topic, MqttMessage message) throws Exception {
        try {
            byte[] decompressed = gunzip(message.getPayload());
            String json = new String(decompressed, "UTF-8");
            AggregatedBatch batch = gson.fromJson(json, AggregatedBatch.class);
            batches.offer(batch);
            received++;
        } catch (Exception e) {
            System.err.println("[Spout_aggregated] Failed to deserialize batch: " + e.getMessage());
        }
    }

    @Override
    public void connectionLost(Throwable cause) {
        System.out.printf("[Spout_aggregated] Connection lost: %s%n", cause.getMessage());
    }

    @Override
    public void deliveryComplete(IMqttDeliveryToken token) {}

    @Override
    public void nextTuple() {
        AggregatedBatch batch = batches.poll();
        if (batch == null) return;

        String msgId = batch.gatewayId + ":" + batch.flushTimestamp + ":" + batch.windowSizeMin;
        collector.emit("agg-data", new Values(batch), msgId);
        emitted++;

        if (System.currentTimeMillis() - lastLog > 30000) {
            System.out.printf("[Spout_aggregated] received=%d emitted=%d queue=%d%n",
                received, emitted, batches.size());
            lastLog = System.currentTimeMillis();
        }
    }

    @Override public void ack(Object msgId)  {}
    @Override public void fail(Object msgId) {}
    @Override public void close() {
        try { if (client != null) client.disconnect(); } catch (MqttException ignored) {}
    }
    @Override public Map<String, Object> getComponentConfiguration() { return null; }

    @Override
    public void declareOutputFields(OutputFieldsDeclarer declarer) {
        declarer.declareStream("agg-data", new Fields("batch"));
    }

    private static byte[] gunzip(byte[] data) throws IOException {
        ByteArrayInputStream bis = new ByteArrayInputStream(data);
        GZIPInputStream gis = new GZIPInputStream(bis);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int len;
        while ((len = gis.read(buf)) != -1) bos.write(buf, 0, len);
        gis.close();
        return bos.toByteArray();
    }
}
