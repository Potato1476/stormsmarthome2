#!/usr/bin/env node
/* ===========================================================================
 * ANOMALY EVAL — phát luồng có NHÃN để đánh giá định lượng bộ phát hiện bất
 * thường EWMA z-score ở gateway (giải quyết phản biện C12).
 *
 * Cách hoạt động:
 *   1. Với mỗi thiết bị (house:household:plug), phát baseline ~BASE_W + nhiễu
 *      Gaussian trong suốt phiên (để EWMA học μ/σ).
 *   2. Tại các thời điểm định trước, TIÊM spike (value = BASE_W × SPIKE_FACTOR)
 *      vào một thiết bị → đây là anomaly "ground-truth".
 *   3. Ghi ground-truth ra GT_FILE (JSON) để chấm điểm sau.
 *
 * Payload khớp Spout_rawData: "_,timestamp,value,property,plugId,householdId,houseId"
 * (property=1 = load reading).
 *
 * Dùng:
 *   BROKER=mqtt://localhost:1883 DURATION=600 N_SPIKES=20 \
 *   HOUSES=0,1,2 BASE_W=120 SPIKE_FACTOR=6 GT_FILE=results/remeasure/anomaly_gt.json \
 *   node tools/anomaly_eval.js
 * =========================================================================== */
const mqtt = require('mqtt');
const fs = require('fs');

const BROKER       = process.env.BROKER       || 'mqtt://localhost:1883';
const TOPIC        = process.env.TOPIC        || 'iot-data';
const DURATION     = parseInt(process.env.DURATION   || '600', 10);   // giây
const TICK_MS      = parseInt(process.env.TICK_MS    || '1000', 10);  // phát mỗi 1s/thiết bị
const N_SPIKES     = parseInt(process.env.N_SPIKES   || '20', 10);
const WARMUP       = parseInt(process.env.WARMUP     || '60', 10);    // không tiêm trong WARMUP đầu
const BASE_W       = parseFloat(process.env.BASE_W   || '120');
const NOISE_W      = parseFloat(process.env.NOISE_W  || '8');         // std nhiễu nền
const SPIKE_FACTOR = parseFloat(process.env.SPIKE_FACTOR || '6');     // spike = BASE×factor
const HOUSES       = (process.env.HOUSES || '0,1,2').split(',').map(s => parseInt(s, 10));
const HOUSEHOLDS   = parseInt(process.env.HOUSEHOLDS || '1', 10);
const PLUGS        = parseInt(process.env.PLUGS       || '3', 10);
const GT_FILE      = process.env.GT_FILE || 'results/remeasure/anomaly_gt.json';

// Danh sách thiết bị
const devices = [];
for (const h of HOUSES)
  for (let hh = 0; hh < HOUSEHOLDS; hh++)
    for (let p = 0; p < PLUGS; p++) devices.push({ h, hh, p });

// Lịch tiêm spike: chọn ngẫu nhiên thời điểm (sau WARMUP) và thiết bị
const spikeSchedule = [];
for (let i = 0; i < N_SPIKES; i++) {
  const at = WARMUP + Math.floor(Math.random() * (DURATION - WARMUP - 2)) + 1;
  const dev = devices[Math.floor(Math.random() * devices.length)];
  spikeSchedule.push({ at, ...dev });
}
const gt = []; // ground-truth events

function gauss(mean, std) {
  // Box–Muller
  const u = 1 - Math.random(), v = Math.random();
  return mean + std * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

const client = mqtt.connect(BROKER);
client.on('connect', () => {
  console.log(`[anomaly_eval] connected ${BROKER}; devices=${devices.length} spikes=${N_SPIKES} dur=${DURATION}s`);
  let sec = 0;
  const timer = setInterval(() => {
    const nowSec = Math.floor(Date.now() / 1000);
    const dueSpikes = spikeSchedule.filter(s => s.at === sec);
    for (const dev of devices) {
      let value = Math.max(0, gauss(BASE_W, NOISE_W));
      const hit = dueSpikes.find(s => s.h === dev.h && s.hh === dev.hh && s.p === dev.p);
      if (hit) {
        value = BASE_W * SPIKE_FACTOR;
        gt.push({ ts: nowSec, houseId: dev.h, householdId: dev.hh, plugId: dev.p, value: Math.round(value) });
        console.log(`[INJECT] t=${sec}s house=${dev.h} hh=${dev.hh} plug=${dev.p} value=${Math.round(value)}W`);
      }
      const payload = ['0', nowSec, value.toFixed(1), '1', dev.p, dev.hh, dev.h].join(',');
      client.publish(TOPIC, payload, { qos: 0 });
    }
    sec++;
    if (sec > DURATION) {
      clearInterval(timer);
      fs.mkdirSync(require('path').dirname(GT_FILE), { recursive: true });
      fs.writeFileSync(GT_FILE, JSON.stringify({ start: nowSec - DURATION, end: nowSec, spikes: gt }, null, 2));
      console.log(`[anomaly_eval] DONE. ground-truth (${gt.length} spikes) → ${GT_FILE}`);
      client.end();
    }
  }, TICK_MS);
});
client.on('error', e => { console.error('[anomaly_eval] MQTT error:', e.message); process.exit(1); });
