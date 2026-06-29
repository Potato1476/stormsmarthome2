/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */
package com.storm.iotdata;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import org.apache.storm.tuple.Fields;
import java.util.HashSet;

import com.storm.iotdata.functions.*;
import com.storm.iotdata.models.*;
import com.storm.iotdata.storm.*;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.storm.Config;
import org.apache.storm.LocalCluster;
import org.apache.storm.StormSubmitter;
import org.apache.storm.topology.BoltDeclarer;
import org.apache.storm.topology.TopologyBuilder;

public class MainTopo {
    private static BoltDeclarer tagCloud(BoltDeclarer declarer, String type, Integer window, HashSet<String> cloudBolts) {
        if (cloudBolts.contains(type) || cloudBolts.contains(type + "-" + window)) {
            declarer.addConfiguration("tags", "cloud");
        }
        return declarer;
    }

    public static void main(String[] args) throws Exception {
        StormConfig config = new StormConfig();
        System.out.println(config.toString());
        try {
            Options options = new Options();
            Option opt_purge = new Option("p", "purge", false, "Purge data in DB");
            options.addOption(opt_purge);
            Option opt_init = new Option("i", "init", false, "Init DB");
            options.addOption(opt_init);
            Option opt_broker = new Option("b", "broker", true, "Broker URL");
            options.addOption(opt_broker);
            Option opt_topic_list = new Option("t", "topic", true, "Topic list (split by \",\" )");
            options.addOption(opt_topic_list);
            Option opt_windows_list = new Option("w", "windows", true, "Windows list (split by \",\" )");
            options.addOption(opt_windows_list);
            Option opt_develop = new Option("d", "develop", false, "Developing mode");
            options.addOption(opt_develop);
            Option opt_cloudbolts = new Option("c", "cloudbolts", true, "Bolt list tagged \"cloud\" (split by \",\", accepts type or type-window. Default: sum,forecast)");
            options.addOption(opt_cloudbolts);

            CommandLineParser parser = new DefaultParser();
            HelpFormatter formatter = new HelpFormatter();
            CommandLine cmd;

            try {
                cmd = parser.parse(options, args);
                
                if(cmd.hasOption("purge") || config.isCleanDatabase()){
                    DB_store.purgeData();
                }
                else{
                    DB_store.initData();
                }
                
                // Init Broker URL
                if(cmd.hasOption("broker")){
                    config.setSpoutBrokerURL("tcp://" + cmd.getOptionValue("broker"));
                }

                // Init topic list
                if(cmd.hasOption("topic")){
                    config.setSpoutTopicList(Arrays.asList(cmd.getOptionValue("topic").split(",")));
                }

                // Init windows list
                
                if(cmd.hasOption("windows")){
                    Integer[] windowList = new Integer[100];
                    String[] tmp = cmd.getOptionValue("windows").split(",");
                    for(int i = 0; i < tmp.length; i++) {
                        windowList[i] = Integer.parseInt(tmp[i]);
                    }
                    config.setWindowList(Arrays.asList(windowList));
                }
                
                // Init cloud-tagged bolt list (placed on the cloud-tier supervisor by TagAwareScheduler,
                // accepts type ("sum") or type-window ("avg-60"); untagged bolts stay on the gateway tier)
                HashSet<String> cloudBolts = new HashSet<String>(Arrays.asList(
                        (cmd.hasOption("cloudbolts") ? cmd.getOptionValue("cloudbolts") : "sum,forecast").split(",")));

                TopologyBuilder builder = new TopologyBuilder();
                // Bolt_split parallelism is configurable for a FAIR baseline (reviewer A2).
                // Default 1 = exact original baseline. Bolt_split is STATELESS (it only
                // classifies a reading into a time-slice and emits), so it can be scaled
                // safely with fieldsGrouping by houseId. avg/sum/forecast stay serial
                // because they hold per-window state + flush-trigger semantics.
                String _sp = System.getenv("SPLIT_PARALLELISM");
                final int SPLIT_P = (_sp != null && !_sp.isEmpty()) ? Integer.parseInt(_sp) : 1;
                builder.setSpout("spout-trigger", new Spout_trigger(config), 1);

                for (String topic : config.getSpoutTopicList()) {
                    builder.setSpout("spout-data-" + topic, new Spout_data(config, topic), 1);
                }

                HashMap<String, BoltDeclarer> splitList = new HashMap<String, BoltDeclarer>();
                HashMap<String, BoltDeclarer> avgList = new HashMap<String, BoltDeclarer>();
                HashMap<String, BoltDeclarer> sumList = new HashMap<String, BoltDeclarer>();
                HashMap<String, BoltDeclarer> forecastList = new HashMap<String, BoltDeclarer>();
                for (Integer windowSize : config.getWindowList()) {
                    splitList.put("split-" + windowSize,
                            tagCloud(builder.setBolt("split-" + windowSize, new Bolt_split(windowSize, config), SPLIT_P).setNumTasks(Math.max(4, SPLIT_P)), "split", windowSize, cloudBolts));
                    avgList.put("avg-" + windowSize,
                            tagCloud(builder.setBolt("avg-" + windowSize, new Bolt_avg(windowSize, config), 1), "avg", windowSize, cloudBolts));
                    sumList.put("sum-" + windowSize,
                            tagCloud(builder.setBolt("sum-" + windowSize, new Bolt_sum(windowSize, config), 1), "sum", windowSize, cloudBolts));
                    forecastList.put("forecast-" + windowSize,
                            tagCloud(builder.setBolt("forecast-" + windowSize, new Bolt_forecast(windowSize, config), 1), "forecast", windowSize, cloudBolts));
                }
                
                for (Integer windowSize : config.getWindowList()) {
                    for (String topic : config.getSpoutTopicList()){
                        if (SPLIT_P > 1) {
                            // Scaled baseline: partition by houseId so each reading hits ONE
                            // split task (no duplication) — correct because split is stateless.
                            splitList.get("split-" + windowSize).fieldsGrouping("spout-data-" + topic, "data", new Fields("houseId"));
                        } else {
                            // Original baseline (unchanged) — keeps measured numbers reproducible.
                            splitList.get("split-" + windowSize).allGrouping("spout-data-" + topic, "data");
                        }
                    }
                    avgList.get("avg-" + windowSize).shuffleGrouping("split-" + windowSize, "data");
                    avgList.get("avg-" + windowSize).shuffleGrouping("spout-trigger", "trigger");
                    sumList.get("sum-" + windowSize).shuffleGrouping("avg-" + windowSize, "data");
                    sumList.get("sum-" + windowSize).shuffleGrouping("avg-" + windowSize, "trigger");
                    forecastList.get("forecast-" + windowSize).shuffleGrouping("avg-" + windowSize, "data");
                    forecastList.get("forecast-" + windowSize).shuffleGrouping("sum-" + windowSize, "data");
                    forecastList.get("forecast-" + windowSize).shuffleGrouping("sum-" + windowSize, "trigger");
                }

                Config conf = new Config();
                conf.setDebug(true);
                // conf.put(Config.TOPOLOGY_MAX_SPOUT_PENDING, 5000);
                conf.setNumWorkers(2);
                conf.registerSerialization(SpoutProp.class);
                // conf.registerSerialization(com.storm.iotdata.models.SpoutProp.class);

                // Local Cluster Test
                if(cmd.hasOption("develop")){
                    LocalCluster cluster = new LocalCluster(); // create the local cluster
                    cluster.submitTopology(config.getTopologyName(), conf, builder.createTopology());
                }
                else {
                    System.out.println("Sending Topo....");
                    StormSubmitter.submitTopology(config.getTopologyName(), conf, builder.createTopology()); // define the name of
                                                                                                // mylocal cluster, my
                                                                                                // configuration object,
                                                                                                // and my topology
                    System.out.println("Sent");
                }
            } catch (ParseException e) {
                System.out.println(e.getMessage());
                formatter.printHelp("utility-name", options);
                System.exit(1);
            }
        } catch (Exception e) {
            System.out.println(e.toString());
            BufferedWriter log = new BufferedWriter(new FileWriter(new File("Error.log"), true));
            log.write(new Date().toString() + "|" + e.toString() + "\n");
            log.close();
        }
    }
}