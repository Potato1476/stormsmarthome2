#!/usr/bin/env node

/**
 * Fog Smart Home — Automatic Energy Optimizer
 * 
 * This daemon connects to the local MQTT broker, monitors real-time house traffic,
 * and dynamically scales Fog nodes (gateways) up and down using Docker pause/unpause.
 * 
 * Resource conservation rationale:
 *   - Idle Storm JVM nodes consume ~200MB RAM and 2-5% idle CPU ticks.
 *   - By pausing idle gateways, CPU drops to 0.00% and processes freeze, conserving power.
 *   - Unpausing takes < 50ms (cgroups freezer), avoiding JVM boot delay (~10s) and data loss.
 */

const util = require('util');
const exec = util.promisify(require('child_process').exec);
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

// --- Configurations ---
const MQTT_BROKER = process.env.MQTT_BROKER_HOST || 'localhost';
const MQTT_PORT = process.env.MQTT_BROKER_PORT || '1883';
const TOPIC = 'iot-data';
const CHECK_INTERVAL_MS = 3000;       // check every 3s
const INACTIVE_TIMEOUT_MS = 15000;    // pause if idle for 15s
const LOG_FILE = path.join(__dirname, '../results/energy_optimization.log');

// Ensure results directory exists
try { fs.mkdirSync(path.join(__dirname, '../results'), { recursive: true }); } catch (_) {}

function log(msg) {
  const ts = new Date().toISOString();
  const formatted = `[${ts}] ${msg}`;
  console.log(formatted);
  try {
    fs.appendFileSync(LOG_FILE, formatted + '\n');
  } catch (err) {
    console.error(`Failed to write to log file: ${err.message}`);
  }
}

// --- Gateway Mapping ---
// Map houseId (0..39) to gateway names
const gwMap = {};
for (let i = 0; i < 40; i++) {
  const gwNum = Math.floor(i / 5) + 1;
  gwMap[i] = `gw-0${gwNum}`;
}

// Track activity of each gateway (epoch time)
const gwLastSeen = {};
// Initialize all gateways as inactive (epoch 0)
for (let i = 1; i <= 8; i++) {
  gwLastSeen[`gw-0${i}`] = 0;
}

// Track known state of containers to avoid redundant command executions
const gwCurrentState = {}; // 'running' | 'paused' | 'unknown'

log('Starting Fog Energy Optimizer...');
log(`Connecting to MQTT broker at mqtt://${MQTT_BROKER}:${MQTT_PORT}`);

const client = mqtt.connect(`mqtt://${MQTT_BROKER}:${MQTT_PORT}`);

client.on('connect', async () => {
  log(`MQTT connected. Subscribing to topic: ${TOPIC}`);
  client.subscribe(TOPIC);
  
  // Inspect initial states of containers
  await syncContainerStates();
  
  // Start the recursive optimization loop
  runLoop();
});

client.on('message', (topic, message) => {
  try {
    const payload = message.toString();
    const parts = payload.split(',');
    if (parts.length >= 7) {
      const houseId = parseInt(parts[6], 10);
      const gw = gwMap[houseId];
      if (gw) {
        gwLastSeen[gw] = Date.now();
      }
    }
  } catch (err) {
    // Fail-silent on parse errors
  }
});

client.on('error', (err) => {
  log(`MQTT Error: ${err.message}`);
});

/**
 * Fetch docker container status and synchronize our local state cache
 */
async function syncContainerStates() {
  try {
    const { stdout } = await exec("docker ps -a --filter 'name=gw-0' --format '{{.Names}} {{.State}}'");
    const lines = stdout.trim().split('\n');
    lines.forEach(line => {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 2) {
        const name = parts[0];
        const state = parts[1]; // 'running', 'paused', 'exited', etc.
        if (name.startsWith('gw-0')) {
          gwCurrentState[name] = state;
        }
      }
    });
  } catch (err) {
    log(`[ERROR] Failed to sync container states: ${err.message}`);
  }
}

/**
 * Optimization logic: checks timeouts and issues pause/unpause commands
 */
async function checkAndOptimize() {
  const now = Date.now();
  
  // Sync states in case external changes happened (e.g. manual docker commands)
  await syncContainerStates();

  const promises = Object.keys(gwLastSeen).map(async (gw) => {
    const lastActive = gwLastSeen[gw];
    const idleTime = now - lastActive;
    const shouldBeActive = idleTime < INACTIVE_TIMEOUT_MS;
    const currentState = gwCurrentState[gw];

    if (shouldBeActive) {
      // Gateway has active houses: ensure it is running (unpaused)
      if (currentState === 'paused') {
        log(`[ACTIVATE] Gateway ${gw} has active traffic (idle: ${(idleTime/1000).toFixed(1)}s). Unpausing...`);
        gwCurrentState[gw] = 'running'; // optimistic update
        try {
          await exec(`docker compose -f docker-compose.gateway.yml --env-file .env.gateway unpause ${gw}`);
          log(`[SUCCESS] Gateway ${gw} is active.`);
        } catch (err) {
          // If already running or not paused, handle gracefully
          if (err.message.includes('not paused') || err.message.includes('not running')) {
            log(`[INFO] Gateway ${gw} was already running.`);
            gwCurrentState[gw] = 'running';
          } else {
            log(`[ERROR] Failed to unpause ${gw}: ${err.message}`);
            gwCurrentState[gw] = 'paused'; // revert state
          }
        }
      }
    } else {
      // Gateway is idle: pause to conserve energy
      if (currentState === 'running' || currentState === 'unknown') {
        log(`[OPTIMIZE] Gateway ${gw} is idle (idle: ${(idleTime/1000).toFixed(1)}s). Pausing to save energy...`);
        gwCurrentState[gw] = 'paused'; // optimistic update
        try {
          await exec(`docker compose -f docker-compose.gateway.yml --env-file .env.gateway pause ${gw}`);
          log(`[SUCCESS] Gateway ${gw} successfully paused.`);
        } catch (err) {
          // If already paused, handle gracefully
          if (err.message.includes('already paused')) {
            log(`[INFO] Gateway ${gw} was already paused.`);
            gwCurrentState[gw] = 'paused';
          } else {
            log(`[ERROR] Failed to pause ${gw}: ${err.message}`);
            gwCurrentState[gw] = 'running'; // revert state
          }
        }
      }
    }
  });

  await Promise.all(promises);
}

/**
 * Recursive loop to prevent overlapping ticks
 */
async function runLoop() {
  try {
    await checkAndOptimize();
  } catch (err) {
    log(`[ERROR] Optimizer loop error: ${err.message}`);
  } finally {
    setTimeout(runLoop, CHECK_INTERVAL_MS);
  }
}

