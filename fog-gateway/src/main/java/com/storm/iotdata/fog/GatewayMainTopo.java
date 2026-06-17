package com.storm.iotdata.fog;

import com.storm.iotdata.fog.storm.Bolt_ingest;
import com.storm.iotdata.fog.storm.Spout_rawData;
import com.storm.iotdata.fog.storm.Spout_trigger;
import org.apache.storm.Config;
import org.apache.storm.LocalCluster;
import org.apache.storm.topology.TopologyBuilder;
import org.apache.storm.tuple.Fields;

/**
 * Gateway Storm topology running as a LocalCluster (single JVM, no Zookeeper/Nimbus).
 *
 * Topology:
 *   Spout_rawData  ──[data, Fields(houseId,householdId,plugId)]──▶  Bolt_ingest
 *   Spout_trigger  ──[trigger, shuffleGrouping]──────────────────▶  Bolt_ingest
 *
 * Resource targets (matching Raspberry Pi 3 Model B):
 *   JVM heap:  -Xmx384m (set via JAVA_OPTS env var or Docker CMD)
 *   GC:        -XX:+UseSerialGC
 *   Workers:   1 (LocalCluster uses in-process threading)
 */
public class GatewayMainTopo {

    public static void main(String[] args) throws Exception {
        GatewayConfig config = new GatewayConfig();
        System.out.println(config);

        TopologyBuilder builder = new TopologyBuilder();

        builder.setSpout("spout-rawdata", new Spout_rawData(config), 1);
        builder.setSpout("spout-trigger",  new Spout_trigger(config),  1);

        builder.setBolt("bolt-ingest", new Bolt_ingest(config), 1)
               // Fields grouping: same device always hits same Bolt_ingest instance
               // (safe with parallelism=1; correct with parallelism>1 for future scaling)
               .fieldsGrouping("spout-rawdata", "data",
                               new Fields("houseId", "householdId", "plugId"))
               .shuffleGrouping("spout-trigger", "trigger");

        Config conf = new Config();
        conf.setDebug(false);
        conf.setNumWorkers(1);
        conf.setMaxSpoutPending(5000);

        LocalCluster cluster = new LocalCluster();
        cluster.submitTopology(config.getTopologyName(), conf, builder.createTopology());
        System.out.printf("[GatewayMainTopo] Topology '%s' submitted.%n", config.getTopologyName());

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("[GatewayMainTopo] Shutting down...");
            try { cluster.shutdown(); } catch (Exception ignored) {}
        }));

        // Block forever — gateway runs as a long-lived process
        Thread.currentThread().join();
    }
}
