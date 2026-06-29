package com.storm.iotdata.fog;

import com.storm.iotdata.fog.storm.Bolt_cloudMerge;
import com.storm.iotdata.fog.storm.Spout_aggregated;
import com.storm.iotdata.fog.storm.Spout_trigger;
import org.apache.storm.Config;
import org.apache.storm.StormSubmitter;
import org.apache.storm.topology.TopologyBuilder;

/**
 * Cloud tier Storm topology — distributed, ultra-light.
 *
 * Topology:
 *   Spout_aggregated  ──[agg-data, shuffleGrouping]──▶  Bolt_cloudMerge (tagged "cloud")
 *   Spout_trigger     ──[trigger,  shuffleGrouping]──▶  Bolt_cloudMerge
 *
 * Bolt_cloudMerge runs with parallelism=1: all gateways' data flows to one instance,
 * enabling correct cross-gateway merge without distributed coordination.
 *
 * TagAwareScheduler ensures Bolt_cloudMerge is pinned to supervisors tagged "cloud".
 * (Supervisors must have supervisor.scheduler.meta.tags: cloud in their storm.yaml)
 */
public class CloudMainTopo {

    public static void main(String[] args) throws Exception {
        CloudConfig config = new CloudConfig();
        System.out.println(config);
        System.out.println(config.getWorkloadBanner());  // parity proof in the run log (prompt §2.1)

        TopologyBuilder builder = new TopologyBuilder();

        builder.setSpout("spout-aggregated", new Spout_aggregated(config), 1);
        builder.setSpout("spout-trigger",    new Spout_trigger(config),    1);

        // Tagged "cloud" for TagAwareScheduler routing
        builder.setBolt("bolt-cloud-merge", new Bolt_cloudMerge(config), 1)
               .addConfiguration("tags", "cloud")
               .shuffleGrouping("spout-aggregated", "agg-data")
               .shuffleGrouping("spout-trigger", "trigger");

        Config conf = new Config();
        conf.setDebug(false);
        conf.setNumWorkers(1);
        conf.setMaxSpoutPending(2000);
        conf.put(Config.TOPOLOGY_ACKER_EXECUTORS, 1);
        conf.put(Config.TOPOLOGY_MESSAGE_TIMEOUT_SECS, 120);

        System.out.println("[CloudMainTopo] Submitting topology: " + config.getTopologyName());
        StormSubmitter.submitTopology(config.getTopologyName(), conf, builder.createTopology());
        System.out.println("[CloudMainTopo] Submitted successfully.");
    }
}
