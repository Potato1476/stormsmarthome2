# Experiment Methodology — Monolithic vs Fog Computing

This document describes how to capture, compare, and report metrics for the two architectures in a reproducible way.

> 📌 **Kịch bản đo bằng tiếng Việt + script tự động** (khuyến nghị dùng cái này):
> xem **[KICH_BAN_DO_LUONG.md](KICH_BAN_DO_LUONG.md)** và `tools/collect_metrics.sh`.
> Tên metric khớp exporter mr4x2/stormexporter (báo cáo): `topology_stats_*`, `bolts_*`.

---

## 1. Experimental Setup

Mô hình triển khai chính (tương ứng "Cách chạy B" trong `HUONG_DAN_CHAY.md`):

| Component | Giá trị |
|-----------|---------|
| Cloud tier | 1× AWS EC2 `t3.large` (2 vCPU / 8 GB, x86_64) — chỉ chạy `Bolt_cloudMerge` |
| Gateway tier | **Giả lập Pi trên máy local**: 8 container, mỗi cái giới hạn 1 GB / 1 vCPU (đúng Raspberry Pi 3 Model B) |
| Data publisher | Repo publisher phát lại dataset REFIT, trỏ vào `52.74.153.60:1883` |
| Monitoring | Prometheus + Grafana chạy phía local, scrape gateway (localhost) + Cloud exporter (public IP) |
| Region | ap-southeast-1 |

> **Về so sánh với Monolithic:** baseline Monolithic đã được **gỡ khỏi repo này** để tập trung vào mô hình Fog. Các con số Monolithic trong bảng "Expected Outcome" bên dưới là **giá trị tham chiếu** đo từ baseline trước đó — dùng làm mốc so sánh trong báo cáo, không chạy lại từ repo này.

---

## 2. Data Workload

The REFIT dataset produces ~5 devices/household × 40 households = 200 devices. At 2 msgs/device/s → **400 raw tuples/s** total ingested by gateways.

Expected Fog traffic to Cloud: 8 gateways × 5 windows × 1 batch/60s = **40 MQTT messages/min** vs 400 raw tuples/s monolithic.

---

## 3. Steady-State Measurement Protocol

1. Start the stack (Monolithic **or** Fog) and allow **5 minutes warm-up** for topology to fully initialize and JVM JIT to stabilize.
2. Start the data publisher sending MQTT for **exactly 30 minutes**.
3. At T+30min, export metrics from Prometheus (or read from Grafana).
4. Repeat for the other architecture under identical load.
5. Record all six key metrics below from the **600-second window** (Storm's all-time rolling window — most stable).

---

## 4. Key Metrics and PromQL Queries

Run these against `http://localhost:9090` (local) or `http://<CLOUD_EC2_IP>:9090` (AWS).

### 4.1 Tuple Throughput (Acked)

Measures how many tuples the topology acknowledges per unit time — direct proxy for processing load.

```promql
-- Fog Cloud (expect: ~40/min)
sum(topology_stats_acked{window="600"})

-- Monolithic (expect: ~400/s × 600s = 240,000 in 600s window)
-- Run against localhost:9090 with monolithic prometheus
sum(topology_stats_acked{window="600"})
```

**Expected reduction: 90–95%**

### 4.2 Tuples Emitted

Fan-out traffic — each raw tuple in Monolithic fans out across 8 window bolts × split bolt.

```promql
sum(topology_stats_emitted{window="600"})
```

**Expected reduction: 95–98%**

### 4.3 Tuples Transferred

Bolt-to-bolt internal transfers — proportional to topology complexity.

```promql
sum(topology_stats_transferred{window="600"})
```

**Expected reduction: >95%**

### 4.4 Bolt Process Latency

Time per tuple inside each bolt's `execute()` — not end-to-end latency.

```promql
-- Per bolt breakdown
bolts_process_latency{window="600"}

-- Max across all bolts
max(bolts_process_latency{window="600"})
```

**Expected: <0.1 ms** (Cloud bolt does one DB upsert per batch, not per raw tuple)

### 4.5 Bolt Capacity

Fraction of time a bolt thread is busy (0.0 = idle, 1.0 = saturated). Above 0.8 = overload risk.

```promql
-- Per bolt
bolts_capacity{window="600"}

-- Max
max(bolts_capacity{window="600"})
```

**Expected: <0.05** (Cloud bolts almost entirely idle between 60s batch arrivals)

### 4.6 Gateway-Specific Metrics (Fog only)

```promql
-- Ingestion rate per gateway (tuples/s)
sum(rate(fog_gateway_tuples_processed_total[1m])) by (gateway_id)

-- MQTT publish rate (should be ~1/60s per window per gateway)
sum(rate(fog_gateway_mqtt_published_total[5m])) by (gateway_id)

-- Store-and-forward queue (should be 0 under normal ops)
fog_gateway_store_queue_size

-- Bolt execute latency EMA on gateway side
fog_gateway_bolt_execute_latency_ms
```

---

## 5. Results Collection Table

Copy and fill in after each run:

### Monolithic Results (T=30min steady-state, 600s window)

| Metric | Value |
|--------|-------|
| topology_stats_acked | |
| topology_stats_emitted | |
| topology_stats_transferred | |
| max bolts_process_latency (ms) | |
| max bolts_capacity | |

### Fog Results (T=30min steady-state, 600s window)

| Metric | Cloud value | Gateway value (avg across 8) |
|--------|-------------|------------------------------|
| topology_stats_acked (Cloud) | | — |
| topology_stats_emitted (Cloud) | | — |
| topology_stats_transferred (Cloud) | | — |
| max bolts_process_latency ms (Cloud) | | — |
| max bolts_capacity (Cloud) | | — |
| fog_gateway_tuples_processed_total rate | — | |
| fog_gateway_mqtt_published_total rate | — | |
| fog_gateway_bolt_execute_latency_ms | — | |
| fog_gateway_store_queue_size | — | 0 (expected) |

### Reduction Calculation

```
reduction_pct = (monolithic_value - fog_cloud_value) / monolithic_value × 100
```

---

## 6. Export Raw Data from Prometheus

```bash
# Prometheus HTTP API — snapshot of a metric at current time
PROM=http://localhost:9090

curl "$PROM/api/v1/query?query=sum(topology_stats_acked{window=\"600\"})"
curl "$PROM/api/v1/query?query=sum(topology_stats_emitted{window=\"600\"})"
curl "$PROM/api/v1/query?query=sum(topology_stats_transferred{window=\"600\"})"
curl "$PROM/api/v1/query?query=max(bolts_process_latency{window=\"600\"})"
curl "$PROM/api/v1/query?query=max(bolts_capacity{window=\"600\"})"

# Gateway metrics (Fog only)
curl "$PROM/api/v1/query?query=sum(rate(fog_gateway_tuples_processed_total[1m]))by(gateway_id)"
curl "$PROM/api/v1/query?query=sum(fog_gateway_store_queue_size)"
```

Save each output to a JSON file:

```bash
mkdir -p results/fog results/monolithic
for metric in acked emitted transferred; do
  curl -s "$PROM/api/v1/query?query=sum(topology_stats_${metric}{window=\"600\"})" \
    > results/fog/${metric}.json
done
```

---

## 7. Expected Outcome Summary

| Metric | Monolithic | Fog Cloud | Reduction |
|--------|-----------|-----------|-----------|
| Acked tuples/600s | ~240,000 | ~500 | ~99.8% |
| Emitted tuples/600s | ~480,000+ | ~1,000 | ~99.8% |
| Transferred tuples/600s | ~480,000+ | ~1,000 | ~99.8% |
| Max process latency (ms) | 1–5 ms | <0.1 ms | >95% |
| Max bolt capacity | 0.5–0.8 | <0.05 | >90% |

*Note: exact values depend on dataset playback speed and hardware. The ratios are robust.*

The core claim: **Fog pre-aggregates 400 raw msgs/s into 40 MQTT batches/min** before reaching Cloud Storm, reducing cloud-tier tuple load by ~99% while producing mathematically equivalent window averages (proven by algebraic merge: `avg = sum/count` is composable across partitions).
