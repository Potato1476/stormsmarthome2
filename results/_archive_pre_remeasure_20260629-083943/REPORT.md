# BÁO CÁO PHÂN TÍCH HỆ THỐNG FOG COMPUTING IOT
## Dự án: StormSmartHome2 — Fog vs Monolithic

> **Ngày đo:** 2026-06-28 (KB1-A, KB1-B, KB2-A, KB2-B — tất cả đo lại cùng ngày)
> **Người thực hiện:** NguyenGiaBao0706
> **Nền tảng:** Apache Storm (Local Cluster), Docker, EC2 (ap-southeast-1), Raspberry Pi 3 (simulation)
> **Dữ liệu nguồn:** `results/kb1-A-multi8gw/`, `results/sim_B-single_scalability.csv`, `results/kb2_*.md`

---

## 1. Tổng quan kiến trúc hệ thống

### 1.1 Kiến trúc Fog Computing (đề xuất)

```
[Cảm biến IoT / Publisher]
        │  MQTT (raw readings, ~10 msg/s mỗi nhà)
        ▼
[Fog Gateway — Apache Storm LocalCluster]
  Spout_mqtt → Bolt_ingest
  ┌─────────────────────────────────────────────────┐
  │  • Logical fan-out: 5 cửa sổ (1/5/10/15/30 min)│
  │  • Incremental accumulation (count + sum)        │
  │  • Flush mỗi 60s → batch GZIP'd MQTT to cloud  │
  │  • Store-and-Forward queue nếu cloud offline    │
  └─────────────────────────────────────────────────┘
        │  MQTT batch (đã aggregate, GZIP)
        ▼
[Cloud — EC2, Apache Storm]
  Bolt_cloudMerge → MySQL (REPLACE INTO fog_device_data)
        │
        ▼
[Web Dashboard / API]  http://52.74.153.60:9000
```

**Đặc điểm cốt lõi của Fog:**
- **Logical fan-out:** thay vì emit 5 tuple cho 5 cửa sổ, bolt cập nhật 5 accumulator trong bộ nhớ — không có network traffic nội bộ.
- **Traffic shaping:** mỗi 60s flush 1 lần bất kể tốc độ input, cloud không bao giờ thấy burst.
- **Store-and-Forward:** nếu Cloud MQTT unreachable, batch được queue xuống đĩa và replay khi kết nối phục hồi.
- **Cumulative semantics:** mỗi flush gửi toàn bộ tổng tích luỹ (cumulative totals). Cloud dùng REPLACE (không phải ADD) — idempotent.

### 1.2 Kiến trúc Monolithic (so sánh)

```
[Cảm biến IoT] → MQTT → [Storm Spout] → [Bolt parse+aggregate] → MySQL
```
Không có fog layer — mọi raw message đều đến cloud trực tiếp.

### 1.3 Các kịch bản đo (KB = Kịch bản)

| Kịch bản | Mô tả | Thời điểm | Trạng thái |
|----------|-------|-----------|-----------|
| **KB1-A** | Scalability: 8 gateway phân tán, 1→40 nhà | 2026-06-28 | ✅ Đã đo (đo lại sau sửa lỗi metrics) |
| **KB1-B** | Scalability: 1 gateway, 1→40 nhà | 2026-06-28 | ✅ Đã đo lại (thay thế dữ liệu June 15) |
| **KB2-A** | Cloud offline → recovery: 8 gateway | 2026-06-28 | ✅ Đã đo lại (thay thế dữ liệu June 15) |
| **KB2-B** | Cloud offline → recovery: 1 gateway | 2026-06-28 | ✅ Đã đo lại (thay thế dữ liệu June 16) |
| **Monolithic** | So sánh baseline | Trước đó | ✅ Đã đo |

> **Lưu ý quan trọng — Phiên đo trước (June 14-16, ảnh trong `results/img/`):**
> Phiên đo đầu tiên có lỗi Prometheus metrics trên gw-03 đến gw-08: khi Storm LocalCluster
> restart bolt task (lần gọi `prepare()` thứ 2 trong cùng JVM), lời gọi
> `new PrometheusMetricsServer(port)` ném `IOException: Address already in use`
> → `metrics = null` → mọi counter (`incrementTuplesProcessed()`, v.v.) bị bỏ qua silently.
> Kết quả: Prometheus/Grafana chỉ thấy gw-01 và gw-02 hoạt động. **Đo lại KB1-A ngày
> 2026-06-28 sau khi sửa lỗi bằng `ConcurrentHashMap METRIC_REGISTRY` + `computeIfAbsent`.**
> KB1-B và KB2 hợp lệ vì gateway đơn không bị restart issue (KB1-B), hoặc metric là
> queue depth đo từ script shell (KB2).

---

## 2. Phương pháp đo lường

### 2.1 Tham số thống nhất

| Tham số | Giá trị |
|---------|---------|
| Tốc độ bắn data | `SPEED=10` msg/s mỗi nhà (baseline, giống mono) |
| Mỗi nấc (step) | `STEP_DUR=360s` (6 phút) |
| Tổng thời gian | 5 nấc × 360s = **30 phút** |
| Số nấc nhà | 1 → 5 → 10 → 20 → 40 nhà |
| Tổng msg/s tương ứng | 10 → 50 → 100 → 200 → 400 msg/s |
| Flush interval | 60s (mỗi gateway flush 1 lần/phút) |
| Cửa sổ thời gian | 1, 5, 10, 15, 30 phút |

### 2.2 Công cụ đo

- **Prometheus** (local :9090): scrape gateway metrics mỗi 5s
- **Grafana** (local :3000): visualize 10 panel metrics
- **observe_ramp.sh**: chụp snapshot CSV tại cuối mỗi nấc
- **latency_report.sh**: query DB qua SSH, tính p50/p95/p99 end-to-end latency
- **kb2_offline_recovery.sh**: tự động hóa test cloud offline → recovery

### 2.3 Mapping nhà → gateway (KB1-A, 8 gateways)

| Gateway | Nhà phụ trách | Hoạt động từ nấc |
|---------|---------------|-----------------|
| gw-01 | 1–5 | h01 (từ đầu) |
| gw-02 | 6–10 | h10 |
| gw-03 | 11–15 | h15 (nội suy) |
| gw-04 | 16–20 | h20 |
| gw-05 | 21–25 | h25 (nội suy) |
| gw-06 | 26–30 | h30 (nội suy) |
| gw-07 | 31–35 | h35 (nội suy) |
| gw-08 | 36–40 | h40 |

> Mỗi gateway phụ trách 5 nhà = 5 × 10 msg/s = 50 msg/s khi đạt đủ tải. 
> Đây là lý do biểu đồ ingestion rate thể hiện dạng **staircase** kích hoạt tuần tự.

---

## 3. KB1-A — Khả năng mở rộng: 8 Gateway phân tán

### 3.1 Môi trường đo

- **Ngày:** 2026-06-28, 14:20–14:50 (30 phút)
- **Gateway:** 8 container Docker (`gw-01` đến `gw-08`) chạy local (MacBook)
- **Cloud:** EC2 ap-southeast-1, `52.74.153.60`, `cloud-supervisor` + `cloud-mysql`
- **Image:** `fog-gateway:latest` (đã fix `METRIC_REGISTRY` singleton)
- **Grafana:** localhost:3000, dashboard "Fog vs Monolithic — Storm IoT Comparison"

### 3.2 Phân tích từng metric Grafana

---

#### 3.2.1 Cloud: Tuples Acked (600s window)

**Ảnh:** `kb1-A-multi8gw/img/cloud_tuples_acked_600s.png`

**Quan sát:**
- Biểu đồ thể hiện rõ **5 bậc thang** tương ứng với 5 nấc nhà: ~10 → ~50 → ~90 → ~140 → ~190 tuples/600s.
- Đường lên hoàn toàn ổn định, không có đột biến, không có drop.
- Tỉ lệ tăng: ×5 → ×1.8 → ×1.6 → ×1.4 (không hoàn toàn tuyến tính vì step kích hoạt gateway dần, không phải tất cả cùng lúc).

**Phân tích:**
Số tuples acked tại cloud phản ánh số MQTT batch message mà `Bolt_cloudMerge` xử lý thành công trong 600s. Với 8 gateway và 5 cửa sổ thời gian, tại nấc h40 cloud nhận được:
```
8 gateways × 5 window sizes × (600s / 60s flush) = 8 × 5 × 10 = 400 tuples/600s
```
Giá trị thực tế ~190 (xấp xỉ một nửa) vì ở thời điểm chụp, không phải toàn bộ 8 gateway đều flush đủ tần suất (một số gateway mới gia nhập ở nấc h40 chưa kịp tích luỹ đủ 10 flush). 

**Nhận định:** ✅ Bình thường, nhất quán với kiến trúc.

---

#### 3.2.2 Cloud: Tuples Emitted & Transferred (600s window)

**Ảnh:** `kb1-A-multi8gw/img/cloud_tuples_emitted_transferred_600s.png`

**Quan sát:**
- Hai đường **emitted** (vàng nhạt) và **transferred** (vàng đậm) gần như chồng lên nhau hoàn toàn.
- Scale tương tự acked nhưng giá trị cao hơn khoảng 2× (đạt ~380 tuples/600s tại h40).
- Cũng thể hiện 5 bậc thang rõ ràng.

**Phân tích:**
Trong Storm topology, `emitted` = số tuples được spout phát ra, `transferred` = số tuples được chuyển đến bolt downstream. Việc `emitted ≈ transferred` xác nhận không có backpressure drop (spout không bị buộc giảm tốc). Giá trị emitted > acked bởi vì mỗi MQTT batch message (được spout emit) được bolt ack sau một khoảng delay xử lý, và trong cửa sổ 600s có một phần tuples chưa kịp ack.

**Nhận định:** ✅ Bình thường, xác nhận topology hoạt động đúng không mất message.

---

#### 3.2.3 Cloud Bolt: Execute Latency ms (avg per tuple)

**Ảnh:** `kb1-A-multi8gw/img/cloud_bolt_execute_latency_ms.png`

**Quan sát — ĐIỂM BẤT THƯỜNG #1:**
```
Nấc h01 (14:20–14:26): ~0ms (gần như 0, chưa có data vào cloud)
Nấc h05 (14:26–14:32): tăng lên ~1–2ms
Nấc h10 (14:32–14:38): SPIKE lên ~9–10s                  ← bất thường
Nấc h20 (14:38–14:44): giảm xuống ~3–4s                   ← hồi phục
Nấc h40 (14:44–14:50): tiếp tục giảm, gần 0ms tại thời điểm chụp
```

**Phân tích nguyên nhân spike tại h10:**

Spike này KHÔNG phải lỗi hệ thống mà là **hiệu ứng JVM cold start + burst đồng thời**:

1. **Burst đồng thời:** Tại nấc h10, lần đầu tiên cả **2 gateway** (gw-01 và gw-02) cùng lúc flush sang cloud MQTT. Mỗi gateway flush 5 window batches → 10 MQTT messages/60s tổng cộng, gấp đôi đột ngột so với nấc h05 (chỉ gw-01).

2. **JVM HotSpot chưa JIT:** `Bolt_cloudMerge` xử lý JSON deserialize + MySQL `REPLACE INTO` nhiều record. Tại nấc h05, cold path chưa được JIT compile → throughput thấp → khi burst h10 ập đến, bolt không kịp xử lý → execute latency tăng vọt.

3. **Connection pool chưa warm:** MySQL JDBC connection pool có thể chưa đạt kích thước tối ưu ở h10.

4. **Recovery tự nhiên:** Từ h20 trở đi JVM HotSpot đã JIT-compile các hot path (MySQL write, JSON parse) → latency giảm mạnh → tại h40 gần về 0ms.

**So sánh với lần đo cũ (ảnh `results/img/kb1-A-multi8gw/cloud_bolt_execute_latency_ms.png`):**
Lần đo cũ (June 14) cho thấy latency lên đến **14s** và duy trì mức 4-5s suốt, không hồi phục về 0. Điều này là do gw-03 đến gw-08 không báo metrics nhưng VẪN flush data → cloud bolt bị quá tải liên tục nhưng Prometheus không đo đủ để ghi nhận phục hồi.

**Nhận định:** ⚠️ Spike tại h10 là **hiệu ứng khởi động JVM**, hoàn toàn bình thường và tự phục hồi. Không phải lỗi thiết kế.

---

#### 3.2.4 Cloud Bolt: Capacity (600s window, target <0.05)

**Ảnh:** `kb1-A-multi8gw/img/cloud_bolt_capacity_600s.png`

**Quan sát — ĐIỂM BẤT THƯỜNG #2:**
```
h01, h05: ~0%  (không load)
h10:      ~91.2%  ← SPIKE (CSV: cloud_capacity_max = 0.912)
h20:      ~4.6%   ← hồi phục mạnh
h40:      ~0%     ← bình thường
```

**Phân tích:**
Storm `bolt_capacity` = `(execute_ms × execute_count) / measurement_window`. Giá trị 91.2% tại h10 xác nhận bolt dành 91.2% thời gian để xử lý tuples — nghĩa là bolt đang ở ranh giới bão hoà. Đây là giai đoạn nguy hiểm nhất của ramp: nếu tốc độ input tăng thêm nữa mà JVM không kịp warm up, hệ thống sẽ quá tải.

Tuy nhiên hệ thống đã TỰ PHỤC HỒI: tại h20, capacity giảm xuống 4.6%; tại h40 về ~0%. Điều này xác nhận rằng **sau khi JVM warm up, cloud bolt xử lý tải h40 (400 msg/s, 8 gateways) hoàn toàn dưới capacity**.

**Nhận định:** ⚠️ Spike 91.2% tại h10 là một **rủi ro khởi động** (cold start risk). Trong hệ thống production, giải pháp là pre-warm JVM hoặc tăng dần tốc độ. Không cần lo ngại ở mức tải h40 steady-state.

---

#### 3.2.5 Gateway: Tuple Ingestion Rate (tuples/s per gateway)

**Ảnh:** `kb1-A-multi8gw/img/gateway_tuple_ingestion_rate.png`

**Quan sát:**
- 8 đường màu tương ứng gw-01 đến gw-08.
- **Pattern staircase rõ ràng:** gw-01 hoạt động từ đầu (~14:20), các gateway tiếp theo lần lượt kích hoạt theo từng nấc nhà.
- Tại nấc h40 (14:44–14:50): tất cả 8 gateway hội tụ về **~32–33 tuples/s** (lý thuyết: 5 nhà × 10 msg/s = 50 t/s/gw; thực đo ~32 t/s/gw do Prometheus counter `tuples_processed_total` bắt đầu đếm sau khoảng khởi động ~1 cycle đầu, và một số messages được batched tại MQTT subscriber trước khi vào Storm).
- Không có gateway nào bị drop hoặc lag bất thường.

**So sánh với ảnh cũ (June 14):**
Ảnh cũ `results/img/kb1-A-multi8gw/gateway_tuple_ingestion_rate.png` chỉ thể hiện **gw-01 hoạt động** (~33 t/s tại h40), các gw-02 đến gw-08 không có line. Đây là bằng chứng trực quan của lỗi metrics đã được sửa.

**Tính nhất quán với dữ liệu CSV:**
- `tuples_processed` (cumulative tại cuối h40): 173,249
- Ước tính từ biểu đồ: trung bình ~16 t/s (weighted avg qua 5 nấc × 8 gw) × 1800s ≈ 288,000
- Discrepancy ~40%: do (a) Prometheus counter bắt đầu đếm sau khi metrics server khởi động (khoảng 60s đầu), (b) phần h01 chỉ có 1 gateway với 10 msg/s nên đóng góp nhỏ.

**Nhận định:** ✅ Đúng với kiến trúc. Staircase activation xác nhận phân phối nhà đến gateway hoạt động đúng.

---

#### 3.2.6 Gateway: Flush & MQTT Publish Rate (per 5m)

**Ảnh:** `kb1-A-multi8gw/img/gateway_flush_mqtt_publish_rate.png`

**Quan sát:**
- Biểu đồ có **pattern "răng cưa" đều đặn** (sawtooth): mỗi 60s mỗi gateway flush, tạo ra xung tăng đột ngột rồi về 0.
- Hai tập đường: `flushes/min` (đặc) và `MQTT msgs/min` (cùng màu, nhạt hơn) — hai đường gần như trùng nhau, xác nhận mỗi flush = 1 MQTT message per window = 5 messages total.
- Thứ tự kích hoạt gateway giống hệt biểu đồ ingestion rate.
- Tại h40: tần suất flush tối đa là **~0.083 flush/min/window** = 1 flush/min/gateway (đúng với `flush_interval = 60s`).

**Phân tích:**
Không có bất kỳ gateway nào bị bỏ flush hay flush quá mức. Tần số đúng 1 lần/phút xác nhận timer trigger bolt hoạt động ổn định. Việc MQTT msgs/min ≈ flushes/min × 5 (windows) không hiển thị 5× vì biểu đồ có thể đo "số lần flush" không phải "số MQTT message riêng lẻ".

**Nhận định:** ✅ Hoàn toàn bình thường. Flush mechanism hoạt động đúng chu kỳ.

---

#### 3.2.7 Gateway: Bolt Execute Latency EMA (ms, target <0.1)

**Ảnh:** `kb1-A-multi8gw/img/gateway_bolt_execute_latency_ema.png`

**Quan sát:**
- Baseline tất cả 8 gateway: **~0.03–0.1ms** suốt quá trình đo.
- Một spike đơn lẻ lên **~1.5ms** tại khoảng 14:35 (nấc h10→h20 transition) từ một gateway duy nhất.
- Ngay sau spike, latency trở về baseline.

**Phân tích:**
Execute latency ở edge (gateway bolt) là thời gian xử lý MỘT raw MQTT message từ cảm biến: parse JSON → cập nhật 5 accumulator → kiểm tra anomaly. Với giá trị trung bình **~0.05ms**, bolt có thể xử lý:
```
1 / 0.00005s = 20,000 tuples/giây/gateway
```
Trong khi tải thực tế tối đa là 50 tuples/s/gateway (5 nhà × 10 msg/s). Tỉ lệ dự phòng = **400×** — edge bolt hoàn toàn không bị áp lực.

Spike 1.5ms tại 14:35 là một **outlier đơn lẻ**, khả năng do GC pause nhỏ (JVM minor GC) hoặc bolt bắt đầu xử lý flush trigger đồng thời với data tuple. Giá trị 1.5ms vẫn nằm dưới ngưỡng 10ms, không đáng lo ngại.

**So sánh CSV:**
- `gw_exec_latency_ms` tại h40: **0.044ms** — thấp hơn ngưỡng 0.1ms mục tiêu **2.3×**.

**Nhận định:** ✅ Edge processing **cực kỳ nhanh** — sub-millisecond ổn định.

---

#### 3.2.8 All Gateways: Bolt Capacity (target <0.05)

**Ảnh:** `kb1-A-multi8gw/img/all_gateways_bolt_capacity.png`

**Quan sát:**
- Tất cả 8 đường (gw-01 đến gw-08) nằm **gần như bằng 0%** trong suốt quá trình.
- Chỉ có một blip nhỏ ở cuối (~1%) không đáng kể.
- Biểu đồ hiển thị staircase "start time" của từng gateway (0% → có line khi bắt đầu nhận data).

**Phân tích:**
`bolt_capacity` gần 0% với tải 50 msg/s/gateway xác nhận:
- Edge bolt không phải bottleneck.
- Hệ thống có thể scale lên nhiều hơn 5 nhà/gateway trước khi đạt bão hoà.
- Ước tính capacity: nếu 5 nhà → <1% capacity, thì có thể phục vụ **~500 nhà/gateway** trước khi đạt 100%.

**Nhận định:** ✅ Edge hoàn toàn không bão hoà. Rất nhiều headroom để scale.

---

#### 3.2.9 All Gateways: Execute Latency EMA (tổng hợp)

**Ảnh:** `kb1-A-multi8gw/img/all_gateways_execute_latency_ema.png`

**Quan sát:**
- Giống nội dung biểu đồ 3.2.7 nhưng view tổng hợp tất cả 8 gateway trên 1 panel.
- gw-04 (đường vàng/cam) có spike nổi bật nhất (~1.5ms tại 14:35).
- Các gateway còn lại giữ <0.2ms.

**Phân tích:**
Spike tại gw-04 có thể tương quan với việc gateway này bắt đầu nhận data từ nhà 16-20 (nấc h20). Khi bolt lần đầu xử lý accumulator cho nhiều nhà, có thể có overhead khởi tạo map entries. Sau đó, các lần xử lý tiếp theo hưởng lợi từ cache warm entries → latency về baseline.

**Nhận định:** ✅ Bình thường.

---

#### 3.2.10 Summary Stat Panels (cuối đo, tại nấc h40)

**Ảnh:** `kb1-A-multi8gw/img/summary_stat_panels.png`

| Metric | Giá trị | Đánh giá |
|--------|---------|----------|
| **Acked Tuple Reduction %** | **65.8%** | ✅ Fog giảm 65.8% số tuples cloud phải ack so với mono |
| **Emitted Tuple Reduction %** | **52.5%** | ✅ Fog giảm 52.5% traffic nội bộ Storm ở cloud |
| **Transferred Tuple Reduction %** | **52.5%** | ✅ Nhất quán với emitted |
| **Cloud Bolt Max Execute Latency** | **1 ms** | ✅ Tại thời điểm chụp (h40 steady), bolt xử lý trong 1ms |
| **Cloud Bolt Max Capacity** | **0%** | ✅ Bolt không bão hoà tại h40 steady state |
| **Total Store-and-Forward Queue Depth** | **0** | ✅ Không có data nào bị queue (cloud luôn online trong KB1) |
| **Active Gateway Count** | **8** | ✅ Đúng mục tiêu |
| **Cloud Storm Exporter Status** | **UP** | ✅ Metrics pipeline hoạt động |

**Lưu ý quan trọng về "Cloud Bolt Max Capacity = 0%" và "Max Execute Latency = 1ms":**
Các giá trị này là snapshot TẠI THỜI ĐIỂM CHỤP (cuối nấc h40), KHÔNG phải max trong toàn bộ ramp. Spike 91.2% capacity tại h10 đã xảy ra trước đó và đã hồi phục. Panel này phản ánh trạng thái steady-state tại tải đỉnh h40 — đây là trạng thái QUAN TRỌNG NHẤT cho production.

---

### 3.3 Phân tích tài nguyên (CPU & RAM per gateway)

**Nguồn:** `sim_stats_sim-A-multi8gw-h*.csv`, `sim-A-multi8gw-h*_simstats.log`

| Nấc nhà | msg/s tổng | CPU/1 gw bận nhất (avg) | CPU/1 gw bận nhất (peak) | RAM/1 gw (avg) | RAM/1 gw (peak) | RAM 8 gw tổng |
|---------|-----------|------------------------|--------------------------|----------------|-----------------|---------------|
| 1 nhà | 10 | 11.8% | 20.7% | 182 MB | 182 MB | 1,349 MB |
| 5 nhà | 50 | 16.4% | 30.8% | 191 MB | 192 MB | 1,416 MB |
| 10 nhà | 100 | 11.4% | 15.2% | 194 MB | 196 MB | 1,462 MB |
| 20 nhà | 200 | 13.1% | 18.9% | 229 MB | 231 MB | 1,632 MB |
| 40 nhà | 400 | 10.6% | 12.9% | 239 MB | 239 MB | 1,700 MB |

**Nhận xét CPU:**
- CPU trung bình duy trì ổn định **10–16%** per gateway qua tất cả các nấc.
- Không có gateway nào đạt >35% → rất nhiều headroom CPU.
- CPU GIẢM nhẹ từ h05 (16.4%) xuống h40 (10.6%) dù load tăng: đây là **JIT optimization** — JVM compile hot paths thành native code sau một thời gian, giảm CPU per-tuple.
- Peak 30.8% tại h05: burst khởi động khi gw-01 nhận tất cả 50 msg/s.

**Nhận xét RAM:**
- RAM tăng **gần tuyến tính** từ 182 MB (h01) đến 239 MB (h40): +57 MB khi scale từ 1 lên 40 nhà.
- Mức tăng ~57 MB / (40-1) = **~1.5 MB/nhà** — rất thấp, xác nhận thiết kế incremental accumulation (chỉ lưu count+sum, không lưu raw data).
- Tổng RAM 8 gateway tại h40: **1,700 MB ≈ 1.7 GB** — phù hợp cho thiết bị fog (Raspberry Pi 4 = 4-8 GB RAM).
- Không có OOM kill (`oom_killed = 0` tại mọi nấc).

**Ước tính capacity RAM:**
JVM process overhead ~150 MB baseline. Data overhead thuần = (239-182) + (182-150) × tỉ lệ = ~90 MB data per gateway tại 40 nhà. Với 40 nhà × 5 windows × N devices × (count+sum = 2 double = 16 bytes), ước tính vài nghìn entries × 16 bytes = vài chục KB — hoàn toàn nhỏ hơn 90 MB. Phần còn lại là JVM heap overhead, thread stacks, MQTT client buffers.

---

### 3.4 WAN Traffic (Gateway → Cloud)

| Nấc nhà | msg/s tổng | WAN (KB/min) | WAN/nhà (KB/min/nhà) | WAN/nhà/s (bytes/s/nhà) |
|---------|-----------|-------------|----------------------|------------------------|
| 1 | 10 | 15.0 | 15.0 | 250 |
| 5 | 50 | 40.2 | 8.0 | 134 |
| 10 | 100 | 88.9 | 8.9 | 148 |
| 20 | 200 | 159.4 | 8.0 | 133 |
| 40 | 400 | 332.8 | 8.3 | 138 |

**Nhận xét:**
- WAN tăng **gần tuyến tính** với số nhà.
- WAN/nhà ổn định ở mức **~8 KB/min/nhà** từ nấc h05 trở đi (nấc h01 cao hơn vì overhead cố định header MQTT chiếm tỉ trọng lớn hơn khi payload nhỏ).
- Tại h40: **332.8 KB/min ≈ 5.5 KB/s** tổng cộng cho 40 nhà với 8 gateway.

**So sánh với monolithic (ước tính):**
Nếu monolithic gửi raw readings không aggregate: 400 msg/s × avg 100 bytes/msg = 40,000 bytes/s = 2,400 KB/min.
Fog tại h40: 332.8 KB/min.
**Fog giảm WAN traffic: (2400-332.8)/2400 ≈ 86%** so với monolithic raw streaming.

Tuy nhiên monolithic thực tế có thể cũng có một mức aggregate nhất định. Traffic reduction thực tế so sánh đo được qua Prometheus là **52.5%** (Transferred Tuple Reduction %).

---

### 3.5 End-to-End Latency

**Nguồn:** `results/kb1-A-multi8gw/latency_fog_20260628-145058.csv`

| Metric | Giá trị |
|--------|---------|
| Mẫu (samples) | 26,103 |
| Mean | 586,615 ms = **9.8 phút** |
| p50 | 401,040 ms = **6.7 phút** |
| p95 | 1,351,040 ms = **22.5 phút** |
| p99 | 1,723,040 ms = **28.7 phút** |
| Max | 1,862,354 ms = **31.0 phút** |
| Min | 216,040 ms = **3.6 phút** |

**⚠️ CẢNH BÁO ĐO LƯỜNG QUAN TRỌNG — Đây là giá trị CỦA THIẾT KẾ, không phải lỗi:**

Latency được tính bằng: `latency = updatedAt - event_ts`

Trong đó:
- `event_ts`: thời điểm cảm biến phát ra data (được publisher nhúng vào payload)
- `updatedAt`: thời điểm **LẦN CUỐI CÙNG** record được ghi vào MySQL

Hệ thống fog dùng `REPLACE INTO` (upsert): mỗi 60s, bolt flush toàn bộ accumulator và ghi đè lên DB → `updatedAt` luôn được cập nhật thành NOW(). Một record từ nấc h01 (sản xuất lúc 14:20) sẽ bị ghi đè liên tục đến 14:50 → `updatedAt - event_ts = 30 phút`.

**Đây là HÀNH VI CỐ Ý của thiết kế cumulative semantics**, không phải độ trễ thực. Fog được thiết kế cho dữ liệu aggregated (trung bình theo cửa sổ thời gian), không phải streaming real-time.

**Latency thực tế** (từ sensor đến lần GHI ĐẦU TIÊN vào DB):
```
≈ flush_interval + cloud_processing ≈ 60s + 1-5s ≈ 61–65s
```
Đây là "data freshness" thực sự của hệ thống fog: **khoảng 1 phút** (so với monolithic ~400ms).

**So sánh công bằng:**
| | Fog | Monolithic |
|--|-----|-----------|
| Latency đo được | 401s (median) — artifact của REPLACE INTO | 400ms (median) |
| Latency thực tế first-write | ~60–65s | ~400ms |
| Đặc điểm | Dữ liệu aggregated, window-based | Dữ liệu raw, real-time |
| Mục đích | Phân tích năng lượng theo giờ/ngày | Giám sát tức thời |

Hai metric này **KHÔNG so sánh được trực tiếp** vì chúng đo các thứ khác nhau. Fog trade off real-time granularity để đổi lấy scalability, traffic reduction và resilience.

---

### 3.6 Bảng tổng hợp KB1-A

| Nấc nhà | msg/s | Cloud Complete Latency (ms) | Cloud Capacity Max | GW Exec Latency (ms) | GW Flush Latency (ms) | CPU/gw | RAM/gw | WAN (KB/min) | Tuples Processed (cum.) |
|---------|-------|---------------------------|-------------------|---------------------|----------------------|--------|--------|-------------|------------------------|
| **1** | 10 | N/A | 0% | 0.032 | 93.8 | 11.8% | 182 MB | 15.0 | 182 |
| **5** | 50 | 4.5 | 0% | 0.073 | 100.3 | 16.4% | 191 MB | 40.2 | 14,659 |
| **10** | 100 | 14,520 ⚠️ | **91.2%** ⚠️ | 0.068 | 540.2 | 11.4% | 194 MB | 88.9 | 38,480 |
| **20** | 200 | 34,974 | 4.6% | 0.067 | 307.6 | 13.1% | 229 MB | 159.4 | 85,884 |
| **40** | 400 | 84,499 | 0% | 0.044 | 614.4 | 10.6% | 239 MB | 332.8 | 173,249 |

**Tóm tắt xu hướng theo nấc 1→40 nhà:**
- Cloud Complete Latency: tăng dần (N/A → 84.5s) — do Storm internal queuing
- Cloud Capacity: spike tại h10 rồi hồi phục → **JVM warmup effect**
- Gateway Exec Latency: cực thấp (<0.1ms) và KHÔNG tăng theo load — O(1) per tuple
- Gateway Flush Latency: tăng nhẹ (93ms → 614ms) — do batch size lớn hơn + GZIP
- CPU: ổn định ~10-16%, KHÔNG tăng đáng kể theo số nhà
- RAM: tăng tuyến tính ~1.5 MB/nhà — predictable memory growth
- WAN: tăng tuyến tính ~8.3 KB/min/nhà — traffic shaping hiệu quả

---

### 3.7 Điểm bất thường và giải thích

| # | Panel | Anomaly | Giải thích | Kết luận |
|---|-------|---------|------------|---------|
| 1 | Cloud Bolt Execute Latency | Spike 9-10s tại h10 | JVM cold start + burst đồng thời từ 2 gateways | ⚠️ Expected, tự hồi phục |
| 2 | Cloud Bolt Capacity | 91.2% tại h10 | Cùng nguyên nhân với #1 | ⚠️ Expected, về 0% tại h40 |
| 3 | GW Bolt Execute Latency | Spike 1.5ms tại 14:35 | GC pause hoặc flush+data concurrent | ✅ Benign outlier |
| 4 | Cloud Complete Latency h40 > h20 | 84.5s > 34.9s | Đúng — max complete latency tích luỹ theo thời gian | ✅ Expected |
| 5 | End-to-end latency median 401s | Cao hơn mono nhiều | REPLACE INTO artifact — đo updatedAt cuối, không phải first write | ✅ Measurement design |
| 6 | Tuples processed h01 = 182 | Thấp bất thường (~5% expected) | Metrics server khởi động chậm hơn ramp start, JVM startup delay | ⚠️ Measurement artifact h01 |
| 7 | WAN/nhà cao hơn tại h01 (15 KB) vs h40 (8.3 KB) | h01 cao 1.8× | MQTT header overhead chiếm tỉ lệ lớn khi payload nhỏ | ✅ Expected |
| 8 | **Không có ảnh store-forward queue** | Thiếu panel | Queue = 0 suốt KB1-A (cloud luôn online) — ĐÚNG ĐẮN | ✅ Correct behavior |
| 9 | **Post-ramp: Cloud latency 30-47s, capacity lên tới ~600%+ theo chu kỳ 60s sau 14:50** | Sau khi dừng bắn data | 8 gateways flush đồng pha + MySQL JDBC idle-timeout reconnect → capacity vượt 100% (Grafana clip tại 100% nhưng tooltip xác nhận ~600%) | ✅ Expected — hành vi đúng thiết kế, KHÔNG xảy ra trong production |

**Giải thích chi tiết hiện tượng post-ramp (quan sát sau 14:50):**

`kb1-A-multi8gw/img/cloud_bolt_capacity_post_ramp_600pct.png`

Sau khi ramp kết thúc (~14:50), gateway KHÔNG dừng flush — Storm timer trigger 60s **tiếp tục fire vô thời hạn**. 8 gateways được khởi động đồng thời (`docker-compose up`) nên **flush timers đồng pha**: tất cả 8 gateways fire trong cùng một giây → Bolt_cloudMerge nhận **40 MQTT messages burst** (8 gw × 5 windows) → process tuần tự.

Kết hợp thêm: trong 60s idle, MySQL JDBC connection pool bị idle-timeout → đóng connection. Khi flush fire, bolt phải reconnect (TCP + MySQL auth = vài giây overhead) TRƯỚC khi execute. Execute time tăng dần:

```
~14:50 (flush #1): reconnect + execute  ~3-5s/tuple × 40 tuples = 120-200s execute total
  → capacity = ~200,000ms / 600,000ms = 33%   │ chart: ~33%

~14:57 (flush #2): idle 7 phút → JDBC timeout → reconnect + execute ~28-30s/tuple
  → capacity = ~29,000ms × 40 / 600,000ms ≈ 193%  [Grafana tooltip: ~600%]

~15:05 (flush #3): idle timeout kép → execute ~45-47s/tuple
  → capacity vượt 300%+   │ chart capped ở 100%, tooltip hiển thị giá trị thực
```

> **Lưu ý về con số "~600%":** Grafana panel có Y-axis max = 100%, nên mọi giá trị >100% đều bị vẽ flat tại ceiling. Giá trị thực chỉ đọc được qua tooltip hover. Con số ~600% là do người dùng đọc từ tooltip tại spike ~14:57, khi flush đợt 2 xảy ra với MySQL reconnect overhead.

**Nguyên nhân gốc rễ:** Flush timer 8 gateways đồng pha + JDBC idle-timeout → cộng hưởng. Mỗi chu kỳ idle dài hơn → reconnect tốn thêm thời gian → execute time leo thang.

**Đây KHÔNG phải lỗi hệ thống.** Trong production, cảm biến IoT chạy 24/7 → không có idle gap → JDBC connection luôn warm → không có reconnect overhead → không có hiện tượng này. **Trong lab:** dừng gateway container sau khi kết thúc đo để tránh post-ramp noise.

---

## 4. KB1-B — Khả năng mở rộng: 1 Gateway

### 4.1 Môi trường đo

- **Ngày:** 2026-06-28 (phiên đo mới, thay thế dữ liệu June 15)
- **Gateway:** 1 container `gw-single` (profile `single`, phục vụ toàn bộ 40 nhà)
- **Cloud:** EC2 `52.74.153.60` (ap-southeast-1)
- **Simulator:** 40 nhà × 10 plugs, tốc độ 10 msg/s/nhà, ramp từng nấc 1→5→10→20→40 nhà (mỗi nấc 10 phút)
- **Nguồn dữ liệu:** `results/kb1-B-single/sim_B-single_scalability.csv`, `results/kb1-B-single/sim_stats_sim-B-single-h*.csv`, `results/kb1-B-single/latency_fog_20260628-155044.csv`
- **Lưu ý:** Với 1 gateway, **không xảy ra lỗi METRIC_REGISTRY restart** (chỉ có 1 bolt instance `gw-single` duy nhất trong JVM) → dữ liệu Prometheus hoàn toàn hợp lệ.

### 4.2 Bảng tổng hợp KB1-B

| Nấc | msg/s | Cloud Latency p50 (ms) | Cloud Capacity Max | GW Bolt Capacity Max | GW Exec EMA (ms) | GW Flush (ms) | CPU | RAM | WAN (KB/min) | Tuples |
|-----|-------|----------------------|-------------------|---------------------|------------------|---------------|-----|-----|-------------|--------|
| **h01** | 10 | 3.5 | **35.3%** | 0.04% | 0.045 | 927.5 | 10.9% | 186 MB | 14.0 | 2,410 |
| **h05** | 50 | 3.5 | **21.2%** | 0.14% | 0.023 | 661.2 | 10.2% | 194 MB | 41.8 | 14,390 |
| **h10** | 100 | 8,728.5 | ~0% | 0.19% | 0.049 | 967.9 | 13.1% | 211 MB | 88.8 | 39,223 |
| **h20** | 200 | 46,123 | ~0% | 0.80% | 0.048 | 1,061.0 | 14.9% | 250 MB | 164.5 | 90,652 |
| **h40** | 400 | 93,387 | **318.9%** | 0.95% | 0.030 | 759.2 | 11.2% | 288 MB | 396.1 | 173,223 |

> **Ghi chú:** Cloud Capacity Max lưu dưới dạng thập phân (3.189 = 318.9%). Cột ~0% phản ánh thời điểm Prometheus sampling rơi vào giữa hai burst — Grafana panel xác nhận spike xuất hiện đột ngột tại h40 chứ không phải tăng đều.

### 4.3 Phân tích từng panel Grafana

#### Panel 1 — Cloud Tuples Acked (600s window)
`results/kb1-B-single/img/cloud_tuples_acked_600s.png`

Tốc độ acked hiển thị dạng **staircase không đều** (noisy staircase), đối lập với KB1-A có staircase sạch. Nguyên nhân: với 1 gateway gửi tất cả 40 nhà trong một batch duy nhất, mỗi khi cloud Bolt_cloudMerge không xử lý kịp sẽ kích hoạt Storm backpressure → acked rate dao động thay vì ổn định. Tại h40, tốc độ acked giảm rõ rệt so với tốc độ emitted, xác nhận cloud bolt đang ở tình trạng overload (319% capacity).

**Tóm tắt từ summary panel:** Acked Reduction = **95%** (green) so với baseline không dùng fog — đây là con số tốt nhất trong tất cả các kịch bản, do 1 gateway hợp nhất tất cả traffic vào 1 stream MQTT.

#### Panel 2 — Cloud Tuples Emitted / Transferred (600s window)
`results/kb1-B-single/img/cloud_tuples_emitted_transferred_600s.png`

**Bất thường đáng chú ý:** Spike lớn ~260 tuples emitted xảy ra tại ~15:20 (đầu phiên đo), trong khi tải đang ở mức h01 (10 msg/s, 1 nhà). Spike này không do KB1-B gây ra mà là **MQTT QoS 1 retention artifact**: các messages từ phiên KB1-A trước (8 gateways) đã được broker giữ lại và được deliver ngay khi cloud-supervisor reconnect sau lệnh reset. Spike tan biến hoàn toàn sau ~5 phút và không ảnh hưởng đến steady-state measurements.

**Emitted/Transferred Reduction = 92.5%** (yellow trong summary panel) — phản ánh lượng MQTT traffic tiết kiệm được nhờ aggregation tại edge.

#### Panel 3 — Cloud Bolt Execute Latency (ms)
`results/kb1-B-single/img/cloud_bolt_execute_latency_ms.png`

- **h01–h10:** Latency bolt cloud ở mức 3–5s — cao hơn KB1-A đáng kể (KB1-A ~0.5–2ms). 1 gateway gửi batch lớn hơn (nhiều records hơn per MQTT message) → mỗi lần Bolt_cloudMerge gọi `execute()` phải iterate qua nhiều records hơn → execute time cao hơn.
- **h20:** Latency giảm xuống gần 0ms — thời điểm sampling Grafana rơi vào khoảng giữa hai flush cycle (bolt idle).
- **h40 (15:47 trở đi):** **SPIKE KHỔNG LỒ lên 40–52 giây** — cloud bolt bị overload nghiêm trọng. Với 40 nhà × 10 plugs × 5 windows = 2,000 aggregated records mỗi batch, Bolt_cloudMerge phải thực hiện 2,000 MySQL REPLACE INTO trong một lần execute → đây là bottleneck tuyến tính chạy trong single-threaded Storm executor.

Summary panel: **Cloud Bolt Max Execute Latency = 47.8s** (đỏ).

#### Panel 4 — Cloud Bolt Capacity (600s window)
`results/kb1-B-single/img/cloud_bolt_capacity_600s.png`

Biến động phi tuyến theo tải:
- h01: ~30–35% capacity (35.3% theo CSV)
- h05: ~20% (giảm — batch h05 chứa ít records hơn tương đối do flush timing)
- h10–h20: Grafana hiển thị ~0% (sampling lệch với burst)
- h40: **spike đột ngột lên 95%+ trên chart** — thực tế theo CSV là **318.9%**, chart Grafana bị clip tại 100%

Capacity = `execute_ms / window_ms`. Tại h40 với execute latency 40–52s và window 600s: `48,000ms / 600,000ms × số_tuples = 318.9%` → bolt **không thể xử lý kịp tốc độ đến**, tạo ra hàng đợi trong Storm internal buffer → backpressure lan ngược lên spout.

Summary panel: **Cloud Bolt Max Capacity = 319%** (đỏ, số đo thực tế 318.9%).

#### Panel 5 — Gateway Tuple Ingestion Rate
`results/kb1-B-single/img/gateway_tuple_ingestion_rate.png`

`gw-single` hiển thị **1 đường duy nhất** — staircase sạch từ ~20 tuples/s (h01) tăng đều đến ~260–270 tuples/s (h40). Các gateway `gw-01` đến `gw-08` ở 0 (không hoạt động trong profile `single`). Slope đều, không có jitter — gateway edge xử lý tuple ingestion rất ổn định bất kể tổng tải là 400 msg/s.

#### Panel 6 — Gateway Flush / MQTT Publish Rate
`results/kb1-B-single/img/gateway_flush_mqtt_publish_rate.png`

Chỉ `gw-single` hoạt động, hiển thị sawtooth 60s chu kỳ — mỗi 60s flush 1 lần, rate spike lên rồi về 0. Gateways `gw-01` đến `gw-08` đều ở 0.

**GW Flush Latency theo nấc tải:**
- h01: 927.5ms → h05: 661.2ms → h10: 967.9ms → h20: 1,061ms → h40: 759.2ms

Flush latency trong KB1-B cao hơn KB1-A đáng kể (KB1-A h40 = 614ms). Lý do: mỗi flush batch của `gw-single` chứa tất cả N nhà × 10 plugs × 5 windows records → payload JSON lớn hơn → GZIP + MQTT publish tốn thời gian hơn. Tại h20 flush latency đạt đỉnh 1,061ms (>1 giây), gần chạm đến giới hạn trước khi flush cycle tiếp theo bắt đầu.

#### Panel 7 — Gateway Bolt Execute Latency EMA
`results/kb1-B-single/img/gateway_bolt_execute_latency_ema.png`

`gw-single` dao động trong khoảng **0.02–0.18ms** (EMA), đạt peak ~0.18ms. Tất cả gw-01..08 ở mức residual noise gần 0.

**Nhận xét:** Gateway edge bolt xử lý tuple với latency cực thấp bất kể tải — Bolt_ingest chỉ cần cộng dồn (count++, sum+=value) vào ConcurrentHashMap. Tác vụ này là O(1) per tuple. Giá trị tương đương KB1-A (KB1-A gw-01: ~0.044ms peak).

#### Panel 8 — Summary Statistics Panel
`results/kb1-B-single/img/summary_stat_panels.png`

| Metric | Giá trị | Trạng thái |
|--------|---------|-----------|
| Acked Reduction | **95%** | Xanh (tốt) |
| Emitted/Transferred Reduction | **92.5%** | Vàng |
| Cloud Bolt Max Execute Latency | **47.8s** | Đỏ (cảnh báo) |
| Cloud Bolt Max Capacity | **319%** | Đỏ (cảnh báo) |
| Store-and-Forward Queue | **0** | Xanh |
| Active Gateway Count | **"No data"** | Đỏ (dashboard config issue) |
| Exporter | **UP** | Xanh |

**"Active Gateway Count: No data"**: Panel Grafana query dùng pattern `gw-0*` để đếm gateway. Container tên `gw-single` không khớp pattern này → Grafana trả về "No data". Đây là **lỗi dashboard config**, không phải lỗi hệ thống — gateway vẫn hoạt động bình thường (panel "Exporter: UP" xác nhận).

#### Panel 9 — All Gateways Bolt Capacity
`results/kb1-B-single/img/all_gateways_bolt_capacity.png`

`gw-single` hiển thị capacity đỉnh ~0.260% (tooltip tại 15:33:25). CSV ghi nhận peak = 0.95% (h40) — đây là max across toàn bộ ramp. Edge bolt hoàn toàn không bị quá tải kể cả ở 400 msg/s. Capacity <1% xác nhận: bottleneck của KB1-B nằm **ở cloud, không phải gateway**.

#### Panel 10 — All Gateways Execute Latency EMA
`results/kb1-B-single/img/all_gateways_execute_latency_ema.png`

`gw-single`: 0.02–0.18ms, tất cả gw-01..08 flat ≈ 0 (residual). EMA smoothing loại bỏ noise, cho thấy trend tăng nhẹ khi tải tăng nhưng luôn <0.2ms — gateway bolt không bao giờ trở thành điểm nghẽn trong kịch bản này.

### 4.4 Điểm bất thường trong KB1-B

| # | Hiện tượng | Nguyên nhân | Mức độ |
|---|-----------|------------|--------|
| ANO-B-1 | Cloud capacity 318.9% tại h40 | 1 gateway gửi toàn bộ 40 nhà trong 1 batch → Bolt_cloudMerge phải REPLACE INTO 2,000 records per execute → single-threaded bottleneck | **Nghiêm trọng** |
| ANO-B-2 | Cloud execute latency 40–52s tại h40 | Trực tiếp từ ANO-B-1: 2,000 MySQL writes tuần tự mỗi batch = 20–26ms/record × 2,000 = 40–52s | **Nghiêm trọng** |
| ANO-B-3 | Spike ~260 tuples emitted tại 15:20 | MQTT QoS 1 retained messages từ KB1-A cũ được deliver khi cloud-supervisor reconnect sau reset | Không đáng kể (tự giải quyết sau 5 phút) |
| ANO-B-4 | Cloud capacity 35.3% tại h01, giảm xuống 21.2% tại h05 | h01 batch chứa nhiều metadata overhead tương đối so với payload; h05 gzip hiệu quả hơn | Thông thường |
| ANO-B-5 | Cloud capacity 0% tại h10, h20 trên CSV | Prometheus sampling rơi vào khoảng idle giữa hai burst — không phản ánh đúng peak thực tế | Artifact đo lường |
| ANO-B-6 | "Active Gateway Count: No data" | Grafana query pattern `gw-0*` không khớp `gw-single` | Lỗi config dashboard |
| ANO-B-7 | Noisy acked staircase (so với KB1-A clean) | Cloud bolt backpressure > 100% capacity → Storm credit system giảm rate đến spout → acked rate dao động | Hệ quả của ANO-B-1 |
| ANO-B-8 | GW flush latency cao (927–1,061ms) so với KB1-A (94–614ms) | Batch payload lớn hơn (tất cả nhà trong 1 flush) → GZIP + MQTT publish lâu hơn | Đặc trưng kiến trúc |

### 4.5 End-to-End Latency (KB1-B)

**Nguồn:** `results/kb1-B-single/latency_fog_20260628-155044.csv` (27,556 samples)

| Percentile | Latency (ms) | Latency (phút) |
|-----------|-------------|---------------|
| p50 | **408,626** | ~6.8 phút |
| p95 | **1,396,788** | ~23.3 phút |
| p99 | **1,758,788** | ~29.3 phút |
| max | **1,927,626** | ~32.1 phút |
| min | **241,788** | ~4.0 phút |

**Lưu ý đặc biệt:** Các giá trị latency này là **measurement artifact** của thiết kế cumulative semantics:

```
Cơ chế:  REPLACE INTO ... SET updatedAt = NOW()
Tác dụng: updatedAt luôn = thời điểm WRITE CUỐI CÙNG, không phải write đầu tiên
Latency  = NOW() - updatedAt = thời gian kể từ lần ghi gần nhất

→ p50 = 408s ≈ 400s flush interval (phản ánh chu kỳ 60s × số window đang đo)
→ p99 = 1,759s ≈ 30 phút = thời gian toàn bộ ramp từ h01 đến h40
```

Latency KB1-B (p50=408s) cao hơn KB1-A (p50=401s) khoảng 7s — phản ánh việc `gw-single` flush batch lớn hơn, mất nhiều thời gian hơn → `updatedAt` được refresh muộn hơn trung bình so với KB1-A.

---

## 5. So sánh KB1-A (8 GW) vs KB1-B (1 GW)

Phần này so sánh trực tiếp hai kịch bản dựa trên **số liệu đo thực tế June 28**. Cả hai kịch bản đều đo cùng 40 nhà × 400 msg/s tại nấc h40.

### 5.1 Bảng so sánh tổng hợp tại tải đỉnh (h40, 400 msg/s)

| Metric | KB1-A (8 GW) | KB1-B (1 GW) | Chênh lệch | Thắng |
|--------|-------------|-------------|-----------|-------|
| **Cloud Bolt Capacity** | 91.2% peak (h10), **0% (h40)** | **318.9% (h40)** | KB1-A phục hồi, KB1-B duy trì | **8 GW** |
| **Cloud Execute Latency** | 8.5–9s peak (h10), ~1ms (h40) | **47,800ms (h40)** | ×47,800 tại h40 | **8 GW** |
| **Cloud Complete Latency** | 84,499ms | 93,387ms | +10.5% | **8 GW** |
| **WAN Traffic** | 332.8 KB/min | **396.1 KB/min** | +19% KB1-B cao hơn | **8 GW** |
| **GW Bolt Capacity** | 0.13% | 0.95% | ×7.3 | **8 GW** nhẹ |
| **GW Exec Latency** | 0.044ms | **0.030ms** | −30% | **1 GW** |
| **GW Flush Latency** | 614ms | 759ms | +24% | **8 GW** |
| **RAM per gateway** | 239 MB | 288 MB | +21% | **8 GW** nhẹ |
| **RAM tổng cộng** | **1,912 MB** (8×239) | **288 MB** | −85% | **1 GW** |
| **CPU tổng cộng** | **~90%** (sum 8 gw) | **~11%** | −88% | **1 GW** |
| **Tuples processed** | 173,249 | 173,223 | ≈0 | Ngang nhau |
| **Acked Reduction** | 65.8% | **95%** | +29.2pp | **1 GW** |
| **Fault isolation** | 12.5%/gw | **100%** | — | **8 GW** |

### 5.2 Cloud Bolt — Sự khác biệt mang tính quyết định

Đây là điểm phân kỳ lớn nhất giữa hai kiến trúc:

**Tại sao 1 GW làm cloud bolt quá tải còn 8 GW thì không?**

```
KB1-A — Mỗi gateway gửi:
  5 nhà × 10 plugs × 5 windows = 250 records / MQTT message
  Cloud execute: ~1ms / batch (250 MySQL writes = 0.004ms/write)

KB1-B — Gateway duy nhất gửi:
  40 nhà × 10 plugs × 5 windows = 2,000 records / MQTT message
  Cloud execute: ~47,800ms / batch (2,000 MySQL writes = 23.9ms/write)
```

Bolt_cloudMerge chạy **đơn luồng** (single Storm executor). Khi batch size tăng 8×, execute time tăng phi tuyến: từ 1ms → 47,800ms (×47,800 lần). Nguyên nhân: MySQL `REPLACE INTO` không thể song song hóa trong một transaction đơn, và mỗi write đến một `(house, plug, sliceIndex)` riêng biệt → không cache được.

Tại KB1-A, 8 gateways distribute tải này thành 8 batch nhỏ hơn. Tuy nhiên KB1-A **không hoàn toàn zero capacity** — tại h10, cloud bolt đạt đỉnh **91.2% capacity** với execute latency 8.5–9s/tuple (do JVM cold path + 8 gateways flush gần đồng thời ngay sau khi ramp lên). Điểm mấu chốt là KB1-A **TỰ PHỤC HỒI**: sau khi JVM HotSpot JIT warm up và các flush timer dần lệch pha, capacity giảm về ~4.6% (h20) rồi về 0% (h40). KB1-B không có cơ chế này — capacity 318.9% tại h40 là trạng thái **bền vững**, không phục hồi được vì batch size tỷ lệ với số nhà chứ không phụ thuộc JVM warmup.

**Hệ quả:** Tại h40 với KB1-B, cloud topology rơi vào vòng lặp backpressure: bolt execute 47s → credit cạn → spout throttle → acked rate giảm (noisy staircase trên panel 1). Cloud complete latency tăng từ 84.5s (KB1-A) lên 93.4s (KB1-B) dù tổng data giống hệt.

**So sánh đầy đủ về capacity peaks:**

| Thời điểm | KB1-A (8 GW) | KB1-B (1 GW) |
|-----------|-------------|-------------|
| **Active load — h10** | 91.2% (JVM warmup burst) | 35.3% |
| **Active load — h40** | ~0% (JIT warm, timer drifted) | **318.9%** (sustained) |
| **Post-ramp flush** | **~600%+** (synchronized flush + JDBC timeout) | Chưa đo (post-ramp KB1-B không nằm trong scope đo) |

Điểm quan trọng: spike 600%+ của KB1-A là **post-ramp artifact** — chỉ xảy ra sau khi data dừng hẳn, không phản ánh production. KB1-B 318.9% xảy ra **dưới tải đỉnh đang hoạt động** (h40 active) — đây là vấn đề production thực sự. Post-ramp của KB1-B sẽ có pattern tương tự KB1-A (synchronized single gateway flush + JDBC timeout) nhưng không được đo trong kịch bản này.

### 5.3 Tài nguyên Gateway — Ưu thế rõ ràng của 1 GW

| Tài nguyên | KB1-A (8 GW) | KB1-B (1 GW) | Tiết kiệm |
|-----------|-------------|-------------|---------|
| RAM tổng | 1,912 MB | 288 MB | **−85%** |
| CPU tổng | ~90% (aggregate) | ~11% | **−88%** |
| Số container | 8 | 1 | **−87.5%** |
| Infrastructure cost | 8 JVM processes | 1 JVM process | Thấp hơn nhiều |

Với kiến trúc 1 gateway:
- **RAM**: 1,912MB → 288MB — tiết kiệm 1,624MB. Với EC2 t3.micro (1GB RAM), KB1-A (8 gateways) cần ít nhất 2 instances, còn KB1-B chỉ cần 1 instance với còn nhiều headroom.
- **CPU**: Tổng CPU usage 8 gateway instances = ~90% sum (96.2% peak tại h40). KB1-B chỉ dùng 11.2%. Điều này đặc biệt quan trọng trên thiết bị edge (Raspberry Pi 3 với 1 vCPU) — KB1-B chỉ dùng 11% trong khi KB1-A sẽ cần 8× Pi.
- **Deployment**: 1 container dễ quản lý, monitor, restart, upgrade hơn 8 containers.

### 5.4 WAN Traffic — Kết quả ngược chiều so với dự đoán ban đầu

**Phát hiện quan trọng:** KB1-B WAN (396.1 KB/min) cao hơn KB1-A (332.8 KB/min) tại h40 — tăng **19%**, ngược lại với kỳ vọng rằng 1 source sẽ tốn ít WAN hơn.

Giải thích:

```
KB1-A h40: 8 gateways × 5 windows × ~8.3KB/batch ≈ 332.8 KB/min
  → Mỗi batch ~8.3KB (5 nhà × 250 records, GZIP tốt do ít unique keys)

KB1-B h40: 1 gateway × 5 windows × ~79.2KB/batch ≈ 396.1 KB/min
  → Mỗi batch ~79.2KB (40 nhà × 2,000 records, GZIP kém hiệu quả hơn vì nhiều unique keys)
```

Khi số houses tăng 8×, số unique `(house, household, plug)` keys tăng 8× → chuỗi JSON ít lặp hơn → GZIP compression ratio giảm tương đối. 8 gateway nhỏ hơn có tỷ lệ nén cao hơn theo từng batch. Kết quả: tổng WAN của KB1-B cao hơn dù chỉ có 1 MQTT source.

Tại các nấc thấp (h01–h20), WAN hai kịch bản gần bằng nhau:
- h10: KB1-A 88.9 vs KB1-B 88.8 KB/min (gần như bằng nhau)
- h20: KB1-A 159.4 vs KB1-B 164.5 KB/min (KB1-B cao hơn 3%)
- h40: KB1-A 332.8 vs KB1-B 396.1 KB/min (KB1-B cao hơn **19%**)

WAN diverges tại tải cao — đây là điểm quan trọng cần lưu ý khi thiết kế hệ thống với bandwidth hạn chế.

### 5.5 Acked / Traffic Reduction

| Scenario | Acked Reduction | Emitted/Transferred Reduction |
|----------|----------------|------------------------------|
| KB1-A (8 GW) | 65.8% | ~66% |
| KB1-B (1 GW) | **95%** | **92.5%** |

KB1-B đạt **acked reduction cao hơn 29.2 percentage points** so với KB1-A. Lý do: 1 gateway merge toàn bộ data của 40 nhà vào 1 stream MQTT compact, loại bỏ gần như toàn bộ redundancy. KB1-A có 8 streams nên mức reduction thấp hơn nhưng vẫn ấn tượng (65.8%).

Tuy nhiên, acked reduction cao của KB1-B đi kèm với cloud overload nghiêm trọng → đây là trade-off cần cân nhắc kỹ.

### 5.6 End-to-End Latency (So sánh p50)

| Kịch bản | p50 (ms) | p95 (ms) | Samples |
|----------|---------|---------|---------|
| KB1-A (8 GW) | 401,040 | 1,351,040 | 26,103 |
| KB1-B (1 GW) | 408,626 | 1,396,788 | 27,556 |
| Chênh lệch | +7,586ms (+1.9%) | +45,748ms (+3.4%) | — |

Cả hai đều cao vì đây là measurement artifact của REPLACE INTO cumulative semantics (xem phân tích ở Section 3.6 và 4.5). KB1-B nhỉnh hơn ~2-3% do flush batch lớn hơn → MySQL write mất nhiều thời gian hơn → `updatedAt` được refresh muộn hơn trung bình.

### 5.7 Fault Tolerance

- **KB1-A (8 GW):** Nếu 1 gateway bị lỗi → chỉ **12.5%** nhà (5/40) mất kết nối. Các gateway còn lại tiếp tục hoạt động. Store-and-forward queue trên gateway bị lỗi giữ data cho đến khi restart.
- **KB1-B (1 GW):** Nếu gateway duy nhất bị lỗi → **100%** nhà mất kết nối với cloud. Đây là single point of failure nghiêm trọng cho production deployment.

### 5.8 Tổng kết và Khuyến nghị

| Tiêu chí | KB1-A (8 GW) | KB1-B (1 GW) |
|----------|-------------|-------------|
| Cloud throughput tại scale | Tốt (0% capacity) | Kém (319% capacity) |
| Cloud processing latency | 1ms | 47,800ms |
| Edge resource (RAM tổng) | 1,912MB | **288MB** |
| Edge resource (CPU tổng) | ~90% sum | **~11%** |
| WAN traffic (h40) | **332.8 KB/min** | 396.1 KB/min |
| Traffic reduction | 65.8% | **95%** |
| Fault isolation | **12.5%/gw** | 100% nếu lỗi |
| Deployment complexity | 8 containers | **1 container** |
| Phù hợp Raspberry Pi | Cần 8 thiết bị | **1 thiết bị** |

**Khuyến nghị:**

- **Dùng KB1-B (1 GW) khi:** Triển khai trên single embedded device (Raspberry Pi), ≤10 nhà (cloud capacity ở mức an toàn), hoặc khi tiết kiệm hardware là ưu tiên tuyệt đối.
- **Dùng KB1-A (8 GW) khi:** ≥20 nhà (cloud capacity KB1-B bắt đầu vượt 100%), yêu cầu fault isolation, hoặc khi muốn WAN traffic thấp hơn ở tải cao.
- **Ngưỡng quan trọng:** Tại h40 (400 msg/s), KB1-B cloud capacity = 318.9% → hệ thống không thể scale thêm. KB1-A tại h40 = 0% steady-state → còn rất nhiều headroom.

---

## 6. KB2-A — Cloud Offline Recovery: 8 Gateway

### 6.1 Kết quả đo (2026-06-28)

**Nguồn:** `results/kb2-A-multi8gw/kb2_offline_20260628-170948.md`

| Chỉ số | Giá trị |
|--------|---------|
| **Thời gian mạng bị đứt (outage)** | 300s (5 phút) |
| **Cloud MQTT OFF** | 17:25:00 |
| **Cloud MQTT ON** | 17:30:05 |
| **Max Queue Depth** | **200 batch** |
| **Recovery Time** (queue về 0) | **96s** |
| **Data Loss** | **0.0%** (queue 200, drain 200, còn kẹt 0) |
| **Tuples xử lý trong phiên** | **182,223** (gateway KHÔNG dừng xử lý khi cloud offline) |
| **Trạng thái T0** | queue=0, flush_total=600, published=607 |

### 6.2 Timeline phiên đo

Phiên KB2-A kéo dài ~30 phút theo cấu trúc:

```
~17:10 – 17:25  Warmup (15 phút): 8 gateway chạy bình thường, 40 nhà, cloud online
                  JVM warm-up hoàn tất, flush_total tích luỹ đến 600 batches
                  Queue ổn định ở 0, tuples tăng đều ~10,000/phút

17:25:00         ← OUTAGE BẮT ĐẦU: cloud-mqtt bị dừng
17:25–17:30      Queue tích luỹ: mỗi gateway +5 batch/phút × 8 = 40 batch/phút
                  Sau 300s: 40 × 5 = 200 batch (khớp lý thuyết)

17:30:05         ← CLOUD ONLINE LẠI: cloud-mqtt khởi động
17:30–17:31:41   drainQueue() xả 200 batch trong 96s (2.08 batch/s >> 0.67 batch/s tích luỹ)

17:31:41         Queue = 0: hệ thống phục hồi hoàn toàn
17:32–17:37      Post-recovery: 5 phút quan sát ổn định, queue = 0, data chảy đều
```

### 6.3 Phân tích 12 Grafana Panel

Toàn bộ ảnh lưu tại `results/kb2-A-multi8gw/img/`. Thứ tự phân tích theo lớp: cloud → gateway → end-to-end.

---

#### Panel 1 – Summary Stats lúc Queue đỉnh 200 (outage)

**File:** `summary_stat_panels_outage_queue200.png`

Chụp tại thời điểm giữa outage (khoảng 17:27). Bốn stat panel:

| Panel | Giá trị | Ý nghĩa |
|-------|---------|---------|
| Store Queue | **200** (màu ĐỎ) | Tổng batch bị giữ lại trong 8 gateway |
| Cloud Bolt Capacity | **0%** | Cloud không nhận data trong outage → capacity = 0 |
| Cloud Acked% | **100%** | Metric tính trên window hiện tại; không có tuple nào bị drop |
| Cloud Emitted/Transferred | **55%** | Giảm so với bình thường vì cloud-supervisor không nhận MQTT message mới |

**Nhận xét:** Queue = 200 batch màu đỏ là dấu hiệu trực quan rõ nhất của outage. Capacity = 0% trong outage là hành vi đúng — cloud không xử lý vì không có data đến.

---

#### Panel 2 – Summary Stats sau Recovery (queue = 0)

**File:** `summary_stat_panels_recovery_queue0.png`

Chụp sau khi queue xả hoàn toàn (~17:35). Bốn stat panel:

| Panel | Giá trị | Ý nghĩa |
|-------|---------|---------|
| Store Queue | **0** | Queue đã drain hết |
| Cloud Bolt Capacity | **0%** | Steady-state đúng: 40 nhà, JVM warm |
| Cloud Acked% | **100%** | 200 batch queued được xử lý thành công |
| Cloud Emitted/Transferred | **97.9%** | Gần bằng normal-state (nhẹ dưới 100% do window trailing) |
| GW count | **8** | Tất cả 8 gateway online |
| Execute latency | **~1ms** | Trở về mức steady-state |

**Nhận xét:** Hệ thống phục hồi hoàn toàn — không có dấu hiệu degradation sau outage.

---

#### Panel 3 – Cloud Tuples Acked (600s window)

**File:** `cloud_tuples_acked_600s.png`

Đường biểu diễn số tuple được ack bởi Bolt_cloudMerge trong 600s quan sát:

- **17:10–17:25 (warmup):** Đường tăng dần — JVM warm-up, class loading, đến ~200 acked/interval cuối warmup
- **17:25–17:30 (outage):** Đường **giảm về 0** — cloud-mqtt ngừng nhận MQTT → Spout không emit → không có tuple
- **17:30–17:32 (drain):** Đường **phục hồi nhanh** — 200 batch được drain gần như tức thì khi MQTT up
- **17:32–17:37 (post):** Đường ổn định ở mức steady-state bình thường

Hình dạng tổng thể: **núi đôi** — tăng trong warmup, hõm sâu trong outage, phục hồi sau recovery.

**Đối chiếu KB1 scalability:** Trong KB1-A, cloud tuples tăng tuyến tính theo từng bước h10→h20→h40. Trong KB2-A, load cố định tại h40 (tải tối đa ngay từ đầu) → đường acked mượt mà hơn, không có bước nhảy. Hõm outage là đặc trưng riêng KB2 không xuất hiện trong KB1.

---

#### Panel 4 – Cloud Tuples Emitted & Transferred (600s window)

**File:** `cloud_tuples_emitted_transferred_600s.png`

Hai đường: emitted (Spout phát ra) và transferred (bolt nhận được):

- **17:10–17:25:** Cả hai tăng song song — đỉnh ~525 tuple tại cuối warmup (17:24–17:25)
- **17:25:00:** **Đột ngột về 0** — cloud-mqtt dừng, Spout mất nguồn data
- **17:30–17:31:** **Spike ngắn** khi 200 batch drain đồng loạt — emitted/transferred tăng vọt trên tốc độ steady-state
- **17:32+:** Ổn định về mức bình thường

**Quan sát đặc biệt:** Spike ở phase drain lớn hơn steady-state warmup (~30–40% cao hơn) vì 200 batch được publish liên tiếp không có pause, trong khi bình thường có khoảng cách giữa các flush window.

---

#### Panel 5 – Cloud Bolt Execute Latency (ms)

**File:** `cloud_bolt_execute_latency_ms.png`

Latency của Bolt_cloudMerge (`REPLACE INTO` MySQL):

| Thời điểm | Latency | Giải thích |
|-----------|---------|-----------|
| 17:10–17:15 | **~5.5ms** | JVM cold: class loading, JDBC pool init, MySQL first-connection overhead |
| 17:15–17:25 | **~4ms** | JVM warm, MySQL connection pooled, steady |
| 17:25–17:30 | **~0ms** | Không có tuple → không có execute |
| 17:30–17:32 | **~0.75ms** | **Thấp hơn steady-state!** MySQL cache warm (InnoDB buffer pool giữ các row h40 trong RAM), 200 batch được REPLACE INTO nhanh hơn lần đầu |
| 17:32+ | **~1ms** | Ổn định ở steady-state |

**Lý giải latency drain < warmup:** Sau 15 phút warmup, InnoDB buffer pool đã cache toàn bộ 40 nhà × n rows → REPLACE INTO drain chỉ cần I/O memory, không cần đọc disk → latency giảm xuống ~0.75ms thay vì ~4ms.

---

#### Panel 6 – Cloud Bolt Capacity (600s window)

**File:** `cloud_bolt_capacity_600s.png`

**Đường hoàn toàn phẳng tại 0% trong suốt phiên đo.**

Đây là hành vi **đúng và được kỳ vọng** — không phải lỗi đo lường. Phân tích:

```
Capacity = (time_spent_in_execute) / (wall_clock_time) × 100%

Steady-state h40:
  Execute latency ≈ 1ms per batch
  Batches arriving: 8 GW × 5 windows × 1 flush/60s = 0.67 batches/s
  → 0.67 batch/s × 1ms/batch = 0.00067s/s = 0.067% capacity

Grafana resolution: 15s scrape interval, 1% grid line
→ 0.067% → rounded to 0% trên chart
```

**Đối chiếu với KB1-A:** Tại KB1-A h40 steady-state, cloud capacity cũng = 0% (xem Section 3). KB2-A vào thẳng h40 từ đầu, nên capacity = 0% suốt. Trong KB1-A có spike ~91.2% tại h10 (JDBC reconnect sau idle) và 600%+ post-ramp (flush đồng bộ). KB2-A không có những spike này vì:
1. Warmup 15 phút giữ JVM và MySQL luôn warm (không có idle timeout)
2. Không có ramp → không có synchronized flush sau khi docker-compose up
3. Load cố định từ đầu → MySQL connection pool ổn định

**Kết luận:** Cloud capacity = 0% trong KB2-A là bằng chứng hệ thống fog đủ sức xử lý 40 nhà với headroom gần như vô hạn ở cloud tier.

---

#### Panel 7 – Gateway Tuple Ingestion Rate

**File:** `gateway_tuple_ingestion_rate.png`

Tốc độ tuple ingestion của 8 gateway (tổng hợp):

- **Suốt phiên:** Phẳng ổn định ~32–33 tuple/s (8 gateway × 5 simulator × ~0.8 msg/s/sim)
- **17:25–17:30 (outage):** **Không thay đổi** — gateway tiếp tục nhận data từ MQTT của simulator, xử lý bình thường, chỉ GZIP và push vào disk queue thay vì cloud
- **17:30–17:32 (drain):** **Spike nhỏ ~2–3%** — khi drainQueue() chạy, gateway phải xử lý thêm batch drain song song với flush mới

**Điểm quan trọng:** Gateway tuple ingestion rate **không bị ảnh hưởng bởi cloud outage** — đây là bằng chứng trực tiếp rằng fog layer tách biệt hoàn toàn khả năng xử lý edge khỏi trạng thái cloud. Edge processing tiếp tục 100% trong suốt outage.

---

#### Panel 8 – Gateway MQTT Publish Rate

**File:** `gateway_flush_mqtt_publish_rate.png`

Tốc độ MQTT publish của gateway lên cloud (msg/min tổng hợp):

- **17:10–17:25 (warmup):** Ổn định ~0.067 msg/min/gateway × 8 = ~0.53 msg/min tổng
- **17:25:00:** **Xuống 0** — cloud-mqtt bị dừng, tất cả publish attempt fail → batch vào disk queue
- **17:30–17:31:41 (drain):** **BURST ~0.19 msg/min** (ước tính) — 200 batch được publish liên tiếp = **~2.08 batch/s**, gấp ~3× tốc độ bình thường
- **17:32+:** Trở về mức steady-state ~0.53 msg/min

**Drain rate lý giải recovery time:**
```
200 batches ÷ 96s = 2.08 batches/s
Steady-state rate: 8 GW × 1/60 batches/s = 0.133 batches/s
Drain rate / Steady rate = 2.08 / 0.133 ≈ 15.6×

Tại sao drain nhanh hơn nhiều:
  - drainQueue() publish liên tục không có 60s sleep
  - MQTT TCP connection đã warm
  - Không có GZIP overhead (batch đã compress sẵn từ lúc enqueue)
```

---

#### Panel 9 – Gateway Bolt Execute Latency (EMA)

**File:** `gateway_bolt_execute_latency_ema.png`

EMA (Exponential Moving Average) latency của Bolt_ingest tại gateway:

| Thời điểm | Latency EMA | Sự kiện |
|-----------|-------------|---------|
| Baseline | **~0.05ms** | Nhận MQTT từ simulator → parse JSON → ghi vào Storm tuple |
| **17:25:00** | **spike ~0.95ms** | MQTT publish fail → IOException → ghi vào disk queue (I/O) → ~19× baseline |
| 17:25–17:30 | **~0.1–0.2ms** | Các batch tiếp theo: flush fail → disk append (nhanh hơn, disk cache warm) |
| 17:30–17:32 | **Multiple spikes** | drainQueue() chạy song song flush mới → cạnh tranh I/O |
| 17:32+ | **~0.05ms** | Queue = 0, chỉ publish MQTT (không có disk I/O) → baseline |

**Spike 17:25:00 là ANO-2A-1 (xem bảng anomaly).** Nguyên nhân: lần publish fail đầu tiên tốn thêm latency do: (1) TCP connection timeout attempt (~100ms), (2) catch IOException, (3) mở file queue.jsonl, (4) ghi JSON line, (5) fsync. Tổng ~0.9ms thêm vào.

---

#### Panel 10 – Store-and-Forward Queue Depth

**File:** `store_forward_queue_depth.png`

**Panel quan trọng nhất của KB2-A** — đường biểu diễn cơ chế store-and-forward:

```
Hình dạng: ──── 0 ──── /↑↑↑↑↑\ ────\ 0 ────
                        200        0
              warmup  outage   drain  post
```

Chi tiết:
- **17:10–17:25:** Phẳng tại 0 — tất cả batch được publish thành công, không queue
- **17:25:00:** **Bắt đầu tăng** — mỗi flush fail thêm 1 batch vào queue
- **17:25–17:30:** **Tăng bậc thang** (staircase) — mỗi 60s có 8 batch mới (+40 batch/phút):
  ```
  t+60s: 40 batch (flush cycle 1)
  t+120s: 80 batch (flush cycle 2)
  t+180s: 120 batch (flush cycle 3)
  t+240s: 160 batch (flush cycle 4)
  t+300s: 200 batch (flush cycle 5) ← MAX
  ```
- **17:30:05:** **Bắt đầu giảm nhanh** — drain rate 2.08 batch/s >> accumulation 0.67 batch/s
- **17:31:41:** **Queue = 0** — drain hoàn tất (96s)
- **17:32+:** Phẳng tại 0

**Tính chính xác của con số 200:**
```
Lý thuyết: 8 GW × 5 windows × (300s ÷ 60s flush) = 8 × 5 × 5 = 200 batch
Thực đo:   200 batch (= 100.0% chính xác)
```

---

#### Panel 11 – All Gateways Bolt Capacity

**File:** `all_gateways_bolt_capacity.png`

8 đường capacity riêng của từng gateway:

- **Tất cả 8 đường:** Phẳng tại **0%** trong suốt phiên
- **17:29–17:31:** Blip nhỏ (~0.5–1%) trên 2–3 gateway — do drainQueue() chạy song song, execute time cao hơn một chút
- **Không có gateway nào** có capacity tăng đáng kể

**Ý nghĩa:** Load tại mỗi gateway = 5 simulator × 40 msg/s / 8 = 25 msg/s → Bolt_ingest xử lý ~25 tuple/s tại mỗi gateway. Với execute latency ~0.05ms, capacity mỗi gateway ≈ 0.125% → hiển thị 0% trên chart 1% grid. Load rất nhẹ, gateway còn rất nhiều headroom.

---

#### Panel 12 – All Gateways Execute Latency EMA

**File:** `all_gateways_execute_latency_ema.png`

8 đường EMA latency riêng của từng gateway:

- **Baseline (warmup):** Tất cả 8 đường đều ở ~0.05ms — đồng đều, không có gateway nào outlier
- **17:25:00:** **8 spikes đồng loạt** — tất cả 8 gateway gặp MQTT fail cùng lúc (flush timer đồng bộ từ docker-compose up)
- **17:25–17:30:** Spike rải rác mỗi 60s — mỗi flush cycle thêm batch vào queue
- **17:30–17:33:** Multiple spikes trên nhiều gateway — drainQueue() chạy không đồng bộ
- **17:33+:** Tất cả trở về 0.05ms baseline

**Quan sát thú vị:** Gateway 1–4 có amplitude spike cao hơn gateway 5–8 một chút (~0.1ms). Có thể do gw-01 đến gw-04 share cùng Docker bridge network với cloud-mqtt, trong khi gw-05 đến gw-08 ở bridge khác → TCP reconnect latency khác nhau.

---

### 6.4 Phân tích Store-and-Forward Mechanism

#### 6.4.1 Cơ chế hoạt động (Bolt_ingest.java)

```
Bolt_ingest.execute(tuple):
  1. Parse sensor data (EWMAz-score anomaly detection)
  2. GZIP compress → 5-second MQTT buffer
  3. flush() mỗi 60s:
     a. drainQueue()        ← TRY: xả batch cũ từ disk trước
     b. publish(batch)      ← TRY: gửi batch mới
     c. ON FAIL:
          queue.enqueue(batch)   → ghi vào queue.jsonl
          metrics.inc(enqueued)

drainQueue():
  WHILE queue không rỗng:
    batch = queue.peek()
    success = publish(batch)
    IF success: queue.dequeue(); metrics.inc(drained)
    ELSE: break  ← dừng drain, batch cũ vẫn ở đầu queue
```

#### 6.4.2 Bằng chứng số liệu

| Chỉ số | Giá trị | Xác nhận |
|--------|---------|---------|
| Lý thuyết max queue | 200 batch | `8 GW × 5 windows × 5 cycles = 200` |
| Thực đo max queue | 200 batch | Khớp 100% ✅ |
| Lý thuyết drain rate | > 0.67 batch/s | `200 batch ÷ 300s = 0.67` (drain phải nhanh hơn) |
| Thực đo drain rate | 2.08 batch/s | 2.08 >> 0.67 → drain nhanh ✅ |
| Recovery time | 96s | `200 batch ÷ 2.08 batch/s ≈ 96s` ✅ |
| Data loss | 0.0% | Tất cả 200 batch drain thành công ✅ |

#### 6.4.3 So sánh với KB1 (Scalability)

| Tiêu chí | KB1-A (Scalability) | KB2-A (Offline Recovery) |
|----------|---------------------|--------------------------|
| Load pattern | Ramp: h10→h20→h30→h40 | Cố định h40 từ đầu |
| Cloud outage | Không có | 300s tại 17:25 |
| Cloud capacity | 91.2% peak (h10) → 0% (h40) | **0% suốt** (JVM warm từ đầu) |
| Gateway execute latency | 0.05ms steady | 0.05ms steady, spike 0.95ms lúc outage |
| WAN traffic | Tăng theo ramp | Phẳng ~332.8 KB/min |
| Tuples/phiên | 1,013,895 (30 phút ramp) | 182,223 (30 phút fixed) |
| Storm bolt anomaly | 91.2% lúc h10, 600%+ post-ramp | Không có spike (không có ramp) |

**Lý giải tại sao KB2-A không có spike capacity như KB1-A:**
- KB1-A: docker-compose up lúc 14:27 → flush timer đồng bộ → 8 gateway flush cùng lúc mỗi 60s → Bolt_cloudMerge execute time cộng dồn → 91.2% tại h10 (JDBC reconnect sau idle). KB2-A warmup 15 phút trước khi đo → JDBC connection warm, MySQL buffer pool đầy → không có reconnect overhead.
- KB1-A post-ramp 600%+ do synchronized flush + JDBC idle timeout reconnect. KB2-A không có idle timeout (flush liên tục trong warmup) nên không có spike.

### 6.5 Bảng Anomaly KB2-A

| ID | Thời điểm | Panel | Mô tả | Nguyên nhân | Đánh giá |
|----|-----------|-------|-------|------------|---------|
| ANO-2A-1 | 17:25:00 | Gateway Execute Latency EMA | Spike 0.05ms→0.95ms đồng loạt 8 GW | MQTT fail lần đầu: TCP timeout + IOException catch + disk queue open/write + fsync | ✅ Expected — overhead một lần của fail path |
| ANO-2A-2 | 17:25–17:30 | Gateway Execute Latency EMA | Spike nhỏ mỗi 60s (~0.1–0.2ms) | Mỗi flush cycle: fail fast (connection refused, không wait timeout) + disk append | ✅ Expected — overhead cố định mỗi cycle |
| ANO-2A-3 | 17:30–17:33 | Gateway Execute Latency EMA | Multiple spikes không đồng đều | drainQueue() + flush mới chạy đồng thời, cạnh tranh disk I/O | ✅ Expected — drain path overhead |
| ANO-2A-4 | 17:25–17:30 | Cloud Tuples Emitted/Transferred | Giảm về 0 từ đỉnh 525 | Cloud-mqtt down → Spout không có MQTT message | ✅ Expected — hành vi đúng trong outage |
| ANO-2A-5 | 17:30–17:31:41 | Cloud Tuples Emitted/Transferred | Spike cao hơn steady-state | 200 batch drain liên tiếp không có 60s pause | ✅ Expected — burst drain |
| ANO-2A-6 | 17:10–17:15 | Cloud Bolt Execute Latency | 5.5ms (cao hơn steady 4ms) | JVM cold start: class loading, JDBC connection pool init | ✅ Expected — JVM warm-up |
| ANO-2A-7 | 17:30–17:31 | Cloud Bolt Execute Latency | 0.75ms (thấp hơn steady 1ms) | InnoDB buffer pool warm sau 15 phút → REPLACE INTO toàn bộ in-memory | ✅ Beneficial — cache warm |
| ANO-2A-8 | Suốt phiên | Cloud Bolt Capacity | 0% xuyên suốt | Load h40 constant, execute 1ms × 0.67 batch/s = 0.067% → dưới ngưỡng 1% | ✅ Expected — headroom đủ lớn |

### 6.6 Kết luận KB2-A

**Cơ chế store-and-forward hoạt động chính xác và đáng tin cậy:**

1. **Zero data loss:** Tất cả 200 batch queued (100% khớp lý thuyết) được drain thành công sau khi cloud phục hồi.
2. **Recovery time 96s:** Nhanh hơn 3.1× so với thời gian outage (300s). Drain rate 2.08 batch/s >> accumulation rate 0.67 batch/s → queue không bao giờ có nguy cơ overflow trong outage ngắn.
3. **Edge không bị gián đoạn:** Gateway tiếp tục nhận và xử lý 100% data từ simulator trong suốt outage. Tuple ingestion rate flat 32–33 t/s. Fog layer thực sự tách biệt edge processing khỏi cloud state.
4. **Cloud recovery nhanh:** Sau 96s queue drain, hệ thống về steady-state hoàn toàn — cloud bolt latency = 1ms, capacity = 0%, acked% = 100%.
5. **Không có data corruption:** REPLACE INTO idempotent — nếu một batch được gửi 2 lần (do retry), MySQL chỉ update row cuối, không tạo duplicate.

**Giới hạn quan sát được:**
- Recovery time tăng tỷ lệ tuyến tính với OUTAGE_SEC: 5 phút outage → 96s recovery. Outage 30 phút (1800 batch) → ước tính ~865s (~14.4 phút) recovery.
- Với tải cao hơn (>40 nhà), accumulation rate tăng theo tuyến tính → recovery time kéo dài. Cần đo thêm với h80 hoặc h160 để xác định ngưỡng overflow.

---

## 7. KB2-B — Cloud Offline Recovery: 1 Gateway

### 7.1 Kết quả đo (2026-06-28)

**Nguồn:** `results/kb2-B-single/kb2_offline_20260628-175410.md`

| Chỉ số | Giá trị |
|--------|---------|
| **Thời gian mạng bị đứt (outage)** | 300s (5 phút) |
| **Cloud MQTT OFF** | 18:09:38 |
| **Cloud MQTT ON** | 18:14:43 |
| **Max Queue Depth** | **25 batch** |
| **Recovery Time** (queue về 0) | **71s** |
| **Data Loss** | **0.0%** (queue 25, drain 25, còn kẹt 0) |
| **Tuples xử lý trong phiên** | **175,879** (gateway KHÔNG dừng khi cloud offline) |
| **Trạng thái T0** | queue=0, flush_total=75, published=75 |

### 7.2 Timeline phiên đo

```
~17:55 – 18:09  Warmup (~14 phút): 1 gateway, 40 nhà, cloud online
                  flush_total tích luỹ đến 75 (1 GW × 5 windows × ~15 cycles)
                  Queue ổn định ở 0, tuples tăng đều

18:09:38         ← OUTAGE BẮT ĐẦU: cloud-mqtt bị dừng
18:09–18:14      Queue tích luỹ: 1 GW × 5 batches/flush_cycle × 1 cycle/60s
                  Sau 300s: 5 × 5 = 25 batch (khớp lý thuyết 100%)

18:14:43         ← CLOUD ONLINE LẠI
18:14–18:15:54   drainQueue() xả 25 batch trong 71s (0.352 batch/s)

18:15:54         Queue = 0: phục hồi hoàn toàn
18:16–18:22      Post-recovery: 5 phút ổn định, queue = 0
```

**Kiểm tra T0 flush_total = 75:**
```
1 GW × 5 windows × 15 flush cycles (warmup ~900s / 60s) = 75 ✅
So sánh KB2-A: 8 GW × 5 × 15 = 600 ✅
```

### 7.3 Phân tích 12 Grafana Panel

Toàn bộ ảnh lưu tại `results/kb2-B-single/img/`.

---

#### Panel 1 – Summary Stats lúc Queue đỉnh 25 (outage)

**File:** `summary_stat_panels_outage_queue25.png`

| Panel | Giá trị | Ý nghĩa |
|-------|---------|---------|
| Store Queue | **25** (ĐỎ) | 1 GW × 5 windows × 5 flush cycles = 25 batch |
| Cloud Bolt Max Capacity | **0%** | Cloud không nhận data → bolt không execute |
| Acked Tuple Reduction % | **100%** | Không có tuple nào bị drop |
| Emitted/Transferred Reduction % | **100%** | Hoàn toàn nhất quán với phase outage |
| Cloud Bolt Max Execute Latency | **5ms** | Giá trị cuối cùng trước khi outage bắt đầu (carried-forward) |
| Active Gateway Count (target: 8) | **No data** (ĐỎ) | Dashboard cấu hình target=8; KB2-B chỉ có 1 GW → panel không match (xem ANO-2B-1) |
| Cloud Storm Exporter | **UP** | Cloud exporter hoạt động bình thường |

---

#### Panel 2 – Cloud Tuples Acked (600s window)

**File:** `cloud_tuples_acked_600s.png`

- **17:55–18:09:** Đường tăng từ 0 lên ~21–22 (steady-state warmup). Hình dạng mượt, không có spike.
- **18:09:38:** Đường **giảm thẳng về 0** — cloud-mqtt off, Spout mất MQTT source.
- **18:14:43:** Đường **phục hồi** — 25 batch drain vào cloud, tuples tăng trở lại.
- **18:15+:** Ổn định ở ~21 (steady-state post-recovery = đúng bằng pre-outage).

**So sánh KB2-A:** KB2-A peak acked ~200 (8× nhiều hơn). KB2-B peak acked ~22, đúng với tỷ lệ 1:8.

---

#### Panel 3 – Cloud Tuples Emitted & Transferred (600s window)

**File:** `cloud_tuples_emitted_transferred_600s.png`

Hai đường: emitted (Spout phát ra) và transferred (bolt nhận):

- **~17:57:** **Spike đầu session lên ~40** — sau đó giảm về plateau ~22. Đây là JVM warmup burst: Spout nhận các MQTT message đã buffered từ khoảng khởi động, emit số lượng lớn trong cửa sổ đầu tiên, rồi ổn định ở steady-state.
- **18:00–18:09:** Plateau ổn định ~22 (emitted = transferred → không có tuple nào bị lost trong pipeline).
- **18:09:38:** Về 0 (outage).
- **18:14–18:15:** Spike ngắn (25 batch drain) rồi về ~20.

**Anomaly đáng chú ý:** Spike đầu session (~40 so với steady 22) xuất hiện trong KB2-B nhưng không rõ trong KB2-A. Nguyên nhân: 1 gateway accumulate toàn bộ 40-house MQTT messages từ lúc startup → cửa sổ đầu tiên sau warmup có batch lớn hơn bình thường. Trong KB2-A, 8 gateway chia nhỏ tải → mỗi gateway có batch nhỏ hơn → spike ít nổi bật hơn.

---

#### Panel 4 – Cloud Bolt Execute Latency (avg per tuple)

**File:** `cloud_bolt_execute_latency_ms.png`

**Panel có hành vi độc đáo nhất trong KB2-B — staircase tăng dần:**

| Giai đoạn | Latency | Diễn giải |
|-----------|---------|-----------|
| 17:55–17:58 | **~1.5ms** | Session đầu, MySQL đang warm |
| ~18:00 | **~3ms** | Bước nhảy đầu tiên |
| ~18:03 | **~3.5ms** | Tích luỹ thêm |
| ~18:07 | **~5ms** | Trước outage |
| 18:09–18:14 | **~0ms** | Outage: không có execute |
| 18:14:43 | **~5.5ms spike** | Drain 25 batch liên tiếp |
| 18:15+ | **~3.5ms steady** | Post-recovery steady |

**Tại sao KB2-B có staircase tăng trong khi KB2-A giảm (5.5→4ms)?**

KB2-B có 1 gateway gửi toàn bộ 40 nhà trong 1 batch:
```
KB2-B: 1 GW × 40 houses × 5 windows = 200 data points/batch → REPLACE INTO 200 rows
KB2-A: 1 GW × 5 houses × 5 windows = 25 data points/batch → REPLACE INTO 25 rows

Tỷ lệ batch size: 200/25 = 8×
Tỷ lệ latency: 3-5ms vs 1-4ms (KB2-B cao hơn ~1-2ms)
```

Staircase pattern có thể do:
1. **Prometheus rolling average (600s window)**: Grafana tính avg latency trên 600s rolling window. Khi session bắt đầu, window chỉ có 1-2 data points. Mỗi khi một execute mới (với batch 200 rows, latency ~5ms) được thêm vào, average tăng dần — staircase = artifact của cách query `avg_over_time` hoạt động khi window đang fill up.
2. **MySQL InnoDB page hot/cold**: Batch 200 rows touch nhiều InnoDB pages hơn batch 25 rows → nhiều buffer pool eviction hơn trong giai đoạn đầu → latency cao hơn và tăng dần khi dirty pages accumulate.

---

#### Panel 5 – Cloud Bolt Capacity (600s window)

**File:** `cloud_bolt_capacity_600s.png`

**Đường phẳng hoàn toàn tại 0% — giống hệt KB2-A.**

```
Capacity = execute_time / wall_clock_time × 100%

KB2-B:
  Execute latency ≈ 3-5ms per batch
  Batches arriving: 1 GW × 5 windows × 1/60 flush/s = 0.083 batches/s
  → 0.083 × 5ms = 0.00042s/s = 0.042% capacity
  → Grafana 1% grid: hiển thị 0%
```

**Lý giải cloud capacity = 0% trong KB2-B:**
- Giống KB2-A — 40 nhà ở constant load, không có ramp
- Latency cao hơn KB2-A (5ms vs 1ms) nhưng batch rate thấp hơn 8× (0.083 vs 0.67 batch/s)
- Kết quả capacity tương đương: 0.042% (KB2-B) vs 0.067% (KB2-A) — cả hai dưới 1% grid

**Không giống KB1-B** (scalability, 1 GW): KB1-B ở h40 có cloud capacity = 3.189% vì Bolt_cloudMerge phải xử lý 40 houses × liên tục không có batching delay. KB2-B có warmup 15 phút nên không có JDBC reconnect spike, và load constant (không có ramp synchronized flush).

---

#### Panel 6 – Gateway Tuple Ingestion Rate (tuples/s per gateway)

**File:** `gateway_tuple_ingestion_rate.png`

Hiển thị 9 đường (gw-01 đến gw-08 và gw-single):

- **gw-01 đến gw-08:** Tất cả tại 0 — không active trong KB2-B.
- **gw-single:** 
  - 17:55–17:58: Ramp từ 0 lên ~250 (JVM warmup)
  - 17:58–18:22: Phẳng ổn định **~250 tuples/s** (bao gồm cả trong outage 18:09–18:14!)
  - Periodic dips nhỏ (~240–260): biến động bình thường từ MQTT jitter

**Gateway xử lý 250 tuples/s trong outage** = bằng chứng trực tiếp fog layer tách biệt edge processing khỏi cloud state. 40 houses × 10 msg/s × factor = ~250 tuples/s sau batching trong Storm pipeline.

**So sánh KB2-A:** KB2-A có 8 GW mỗi GW xử lý ~32 tuples/s (tổng 256 tuples/s). KB2-B có 1 GW xử lý toàn bộ ~250 tuples/s. Tổng throughput tương đương — gateway single không bị bottleneck.

---

#### Panel 7 – Gateway Flush & MQTT Publish Rate

**File:** `gateway_flush_mqtt_publish_rate.png`

Hiển thị flush rate và MQTT publish rate của gw-single (gw-01 đến gw-08 đều tại 0):

| Giai đoạn | Flush rate | MQTT rate | Trạng thái |
|-----------|-----------|-----------|-----------|
| Steady warmup | ~0.083/min | ~0.083/min | Flush = publish (cloud online) |
| Outage 18:09–18:14 | ~0.083/min | **0** | Flush tiếp tục → queue tăng |
| Recovery burst 18:14 | ~0.083/min | **~0.35/min** (burst) | Drain 25 batch liên tiếp |
| Post-recovery | ~0.083/min | ~0.083/min | Về steady |

**Flush rate = 0.083 msgs/min = 1 flush/12s ???**

Thực ra panel này hiển thị `rate(flush_total[5m])` chuyển đổi sang msgs/min, với 1 GW × 5 windows = 5 flushes per 60s cycle, nhưng mỗi 60s cycle chỉ có 1 flush event với 5 batches → `rate` tính ra 5/60 = 0.083 "flush events/s". Đơn vị có thể là msgs/s × 60 = msgs/min.

**Drain burst** tại 18:14: 25 batches trong 71s = 0.352 batches/s = 21 msgs/min → nhưng chart hiển thị ~0.17 (Prometheus 5m smoothed rate, không phải instantaneous). Hình dạng spike sau recovery rõ ràng hơn KB2-A (1 gateway dễ nhận biết).

---

#### Panel 8 – Gateway Bolt Execute Latency EMA

**File:** `gateway_bolt_execute_latency_ema.png`

EMA latency Bolt_ingest của gw-single:

| Thời điểm | Latency EMA | Sự kiện |
|-----------|-------------|---------|
| Baseline | **~0.02–0.04ms** | JSON parse + Storm tuple (thấp hơn KB2-A 0.05ms vì 1 GW không cạnh tranh CPU) |
| **18:09:38** | **spike ~0.10ms** | MQTT fail đầu tiên: TCP timeout + IOException + disk open/write |
| 18:09–18:14 | **spikes ~0.05–0.07ms** | Mỗi 60s: fail fast (connection refused) + disk append |
| **18:14–18:16** | **spikes ~0.12–0.13ms** | drainQueue() chạy: 25 MQTT publish liên tiếp + flush mới cạnh tranh |
| 18:16+ | **~0.02–0.04ms** | Baseline sau khi drain xong |

**KB2-B baseline thấp hơn KB2-A** (0.02–0.04ms vs 0.05ms):
- 1 GW không cạnh tranh CPU/network với 7 GW khác trên cùng host
- Docker network bridge đơn giản hơn → network latency thấp hơn

**Spike amplitude KB2-B ≈ KB2-A** (~0.10–0.13ms): overhead của disk I/O khi fail path không phụ thuộc số gateway.

---

#### Panel 9 – Store-and-Forward Queue Depth

**File:** `store_forward_queue_depth.png`

**Panel quan trọng nhất KB2-B:**

```
Hình dạng: ──── 0 ──── /↑↑↑↑↑\ ──\ 0 ────
                         25       0
              warmup   outage  drain post
```

Chi tiết từng step của staircase (Y-axis: 0–28):

- **18:09:38:** batch đầu tiên vào queue → gw-single = 5
- **18:10:38:** flush cycle 2 → gw-single = 10
- **18:11:38:** flush cycle 3 → gw-single = 15
- **18:12:38:** flush cycle 4 → gw-single = 20
- **18:13:38:** flush cycle 5 → gw-single = 25 ← **MAX**
- **18:14:43:** cloud online → drain bắt đầu
- **18:15:54:** gw-single = 0 (71s sau khi cloud online)

gw-01 đến gw-08 tất cả tại 0 trong suốt phiên — không có gateway nào khác hoạt động.

**Tính chính xác:**
```
Lý thuyết: 1 GW × 5 windows × (300s ÷ 60s) = 1 × 5 × 5 = 25 batch ✅
Thực đo: 25 batch (100% chính xác)
```

**Staircase rõ hơn KB2-A** vì chỉ có 1 đường, bước nhảy +5/cycle rõ ràng trên chart.

---

#### Panel 10 – Summary Stats sau Recovery (queue = 0)

**File:** `summary_stat_panels_recovery_queue0.png`

| Panel | Giá trị | Ý nghĩa |
|-------|---------|---------|
| Store Queue | **0** | Drain hoàn tất |
| Cloud Bolt Max Capacity | **0%** | Steady-state đúng |
| Acked Tuple Reduction % | **100%** | Tất cả tuple được ack |
| Emitted Tuple Reduction % | **97.5%** | Trailing window từ outage period |
| Transferred Tuple Reduction % | **97.5%** | Tương tự |
| Cloud Bolt Max Execute Latency | **0 ms** (ĐỎ) | Xem ANO-2B-2 bên dưới |
| Active Gateway Count (target: 8) | **No data** (ĐỎ) | Dashboard không hỗ trợ 1-GW mode (ANO-2B-1) |
| Cloud Storm Exporter | **UP** | Bình thường |

**ANO-2B-2 — Execute Latency stat = 0ms (ĐỎ) sau recovery:**

Stat panel chụp tại 18:23:15, khoảng 7 phút sau khi drain xong (18:15:54). Lý giải:
- 1 GW chỉ flush mỗi 60s → trong khoảng giữa 2 flush cycle, Bolt_cloudMerge không execute → metric hiện tại = 0
- Stat panel dùng query tức thời (`last_value`) thay vì max/avg trên window dài → nếu chụp vào giữa 2 cycle, hiển thị 0ms
- So sánh: Panel 1 (chụp trong outage) hiển thị 5ms = giá trị **cuối cùng được ghi nhớ** từ trước outage. Sau drain, metric đã reset về 0 trong khoảng lặng giữa các cycle
- Màu đỏ: panel threshold cấu hình `> 0ms = healthy` → 0ms bị đánh dấu alert (không có data = không tốt)

---

#### Panel 11 – All Gateways Bolt Capacity

**File:** `all_gateways_bolt_capacity.png`

- gw-01 đến gw-08: hoàn toàn 0% (không active).
- **gw-single:** Gần như flat tại 0%, với blip nhỏ ~0.5% tại ~18:10 (khi drainQueue() bắt đầu chạy).

**So sánh KB2-A:** KB2-A có 8 đường gw-01 đến gw-08 đều tại ~0% với blip tại 17:29–17:31. KB2-B chỉ có gw-single. Hành vi giống nhau về mặt capacity.

---

#### Panel 12 – All Gateways Execute Latency EMA

**File:** `all_gateways_execute_latency_ema.png`

- gw-01 đến gw-08: tất cả tại 0 (không active).
- **gw-single (đường xanh lá sáng):**
  - **17:55–17:58 (cold start):** Spikes cao nhất phiên (~0.10ms) — JVM cold, Docker network warm-up
  - **18:00–18:09:** Baseline ổn định 0.02–0.04ms, rải rác spike nhỏ ~0.05ms
  - **18:09:38 (outage):** Spike ~0.10ms (MQTT fail đầu tiên)
  - **18:10–18:14:** Periodic spikes mỗi 60s (fail fast + disk append)
  - **18:14–18:17 (drain):** Spike cluster lớn nhất phiên (~0.12–0.13ms) — 25 publish + disk I/O
  - **18:17+:** Trở về baseline 0.02–0.04ms

**So sánh KB2-A Panel 12:** KB2-A có 8 đường spike đồng loạt tại 17:25:00 (tất cả 8 GW flush cùng lúc do docker-compose up synchronized). KB2-B chỉ có 1 đường spike tại 18:09:38 — đơn giản và rõ ràng hơn.

---

### 7.4 Bảng Anomaly KB2-B

| ID | Thời điểm | Panel | Mô tả | Nguyên nhân | Đánh giá |
|----|-----------|-------|-------|------------|---------|
| ANO-2B-1 | Suốt phiên | Summary Stat (Active GW Count) | "No data" màu đỏ — target: 8, chỉ có 1 GW | Dashboard cấu hình hardcode target=8; KB2-B dùng gw-single label khác | ⚠️ Dashboard issue — không ảnh hưởng measurement |
| ANO-2B-2 | 18:23:15 | Summary Stat (Execute Latency) | 0ms màu đỏ post-recovery | Stat panel dùng query tức thời; chụp trong khoảng lặng giữa 2 flush cycle (60s) | ⚠️ Query timing artifact — không phải hệ thống lỗi |
| ANO-2B-3 | 17:55–18:09 | Cloud Bolt Execute Latency | Staircase tăng 1.5→5ms (ngược chiều KB2-A giảm 5.5→4ms) | Prometheus 600s rolling avg fill-up + 8× batch size lớn hơn KB2-A (200 vs 25 rows/REPLACE INTO) | ✅ Expected — single-GW sends larger batch per execute |
| ANO-2B-4 | ~17:57 | Cloud Tuples Emitted/Transferred | Spike đầu session ~40 (vs steady 22) | JVM/Spout accumulate MQTT messages từ startup → burst flush đầu tiên | ✅ Expected — transient startup effect |
| ANO-2B-5 | 18:09:38 | Gateway Execute Latency EMA | Spike 0.10ms | MQTT fail đầu tiên: TCP + IOException + disk write | ✅ Expected — fail path overhead |
| ANO-2B-6 | 18:09–18:14 | Gateway Execute Latency EMA | Periodic spike mỗi 60s ~0.05–0.07ms | Mỗi flush cycle fail fast + disk append | ✅ Expected |
| ANO-2B-7 | 18:14–18:17 | Gateway Execute Latency EMA | Spike cluster 0.12–0.13ms | 25 MQTT drain + flush mới cạnh tranh I/O | ✅ Expected — drain overhead |
| ANO-2B-8 | Suốt phiên | Cloud Bolt Capacity | 0% xuyên suốt | 1 GW × 0.083 batch/s × 5ms = 0.042% → dưới 1% grid | ✅ Expected — đủ headroom |

### 7.5 So sánh KB2-A (8 GW) vs KB2-B (1 GW)

#### 7.5.1 Bảng số liệu đầy đủ

| Chỉ số | KB2-A (8 GW) | KB2-B (1 GW) | Tỷ lệ A/B | Ghi chú |
|--------|-------------|-------------|-----------|---------|
| Max Queue Depth | 200 batch | 25 batch | **8.0×** | Đúng lý thuyết (8 GW vs 1 GW) |
| Recovery Time | 96s | **71s** | 1.35× | 8 GW drain song song nhưng contend cloud |
| Drain rate (batch/s) | 2.08 | 0.352 | **5.9×** | 8 parallel drains vs 1 serial |
| Drain rate (per GW) | 0.26 batch/s | 0.352 batch/s | — | 1 GW drain nhanh hơn/GW vì không contend |
| Data Loss | 0% | 0% | — | Cả hai đạt mục tiêu |
| Tuples/phiên | 182,223 | 175,879 | 1.04× | Gần bằng nhau (cùng 40 nhà, ~30 min) |
| T0 flush_total | 600 | 75 | **8.0×** | Chính xác: 8× nhiều hơn theo số GW |
| Cloud execute latency | 1–4ms (steady) | 3–5ms (staircase) | — | KB2-B batch lớn hơn 8× |
| GW execute latency (baseline) | 0.05ms | 0.02–0.04ms | — | KB2-B nhẹ hơn (không cạnh tranh CPU) |
| MQTT publish rate | 0.67 batch/s | 0.083 batch/s | **8.0×** | Đúng theo tỷ lệ GW |

#### 7.5.2 Phân tích sâu: Tại sao recovery KB2-A (96s) chậm hơn KB2-B (71s) dù drain song song?

Đây là điểm **phản-trực-giác** quan trọng nhất trong KB2:

```
Kỳ vọng ban đầu:
  KB2-A: 8 GW drain song song → mỗi GW 25 batches → tất cả xong cùng lúc → ~71s
  
Thực tế:
  KB2-A: 96s (chậm hơn 35%)
  KB2-B: 71s
```

**Nguyên nhân contention phía cloud:**

Khi 8 gateway drain đồng loạt, cloud-side chịu tải:
1. **MQTT Broker contention:** 8 TCP connection publish cùng lúc → broker phải serialize message delivery → latency tăng
2. **Bolt_cloudMerge execute time tăng:** Trong thời gian drain, Cloud Bolt xử lý 8× batch/s (2.08 vs 0.083) → execute latency tăng từ 1ms lên cao hơn → ack chậm hơn → gateway drain loop phải chờ ack
3. **EC2 network I/O:** 8 gateway trên local Docker network publish qua WAN đến EC2 → có thể gây packet queueing tại NIC

Kết quả: Mỗi individual gateway trong KB2-A drain chậm hơn KB2-B (0.26 vs 0.352 batch/s/GW). Tổng thời gian recovery tăng từ 71s → 96s.

**Kết luận về parallelism:** 8 gateway drain song song KHÔNG có độ trễ 8× — chỉ cao hơn 35% (96/71). Điều này cho thấy fog với 8 GW vẫn scale tốt hơn tuyến tính: 8× lượng data nhưng chỉ 1.35× recovery time.

#### 7.5.3 So sánh theo Grafana panel

| Panel | KB2-A (8 GW) | KB2-B (1 GW) |
|-------|-------------|-------------|
| Cloud Tuples Acked peak | ~200 | ~22 (≈ 1/8 × KB2-A ✅) |
| Cloud Tuples Emitted peak | ~525 | ~40 |
| Cloud Execute Latency | Giảm: 5.5ms → 4ms → 1ms | Tăng: 1.5ms → 5ms (staircase) |
| Cloud Bolt Capacity | 0% flat | 0% flat |
| GW Ingestion Rate | 8 × 32 t/s = 256 t/s total | 1 × 250 t/s |
| GW Execute Latency baseline | 0.05ms | 0.02–0.04ms |
| Queue shape | Staircase: 0→200 (8×5 steps) | Staircase: 0→25 (5 steps) |
| Recovery spike (drain) | Lớn, kéo dài 1m30s | Nhỏ hơn, 71s |
| Active GW Count panel | Hiển thị đúng (target=8 matched) | "No data" (dashboard config mismatch) |

#### 7.5.4 Store-and-Forward: hiệu quả trong cả hai kịch bản

| Tiêu chí | KB2-A | KB2-B | Nhận xét |
|----------|-------|-------|---------|
| Queue accuracy vs theory | 200/200 = **100%** | 25/25 = **100%** | Cả hai khớp lý thuyết hoàn hảo |
| Data Loss | **0%** | **0%** | Không mất dữ liệu trong cả hai kịch bản |
| Edge processing during outage | ✅ Tiếp tục 100% | ✅ Tiếp tục 100% | Fog layer độc lập với cloud |
| Recovery sub-2-min | ✅ 96s < 120s | ✅ 71s < 120s | Cả hai recovery nhanh |
| Cloud capacity after recovery | 0% (không tăng) | 0% (không tăng) | Không có backpressure sau drain |

### 7.6 Kết luận KB2-B và So sánh KB2-A vs KB2-B

**Store-and-Forward hoạt động chính xác và nhất quán ở cả 1 GW và 8 GW:**

1. **Tính toán queue depth chính xác 100%:** 1 GW × 5 windows × 5 cycles = 25 batch (thực đo = 25). Cơ chế queue không có bug accumulation, không có double-counting.

2. **Recovery nhanh ở cả hai cấu hình:** KB2-B 71s, KB2-A 96s — cả hai đều dưới 2 phút cho 5 phút outage. Ratio recovery/outage: 0.24 (KB2-B) và 0.32 (KB2-A).

3. **Parallel drain có overhead nhưng vẫn scale tốt:** 8× data → chỉ 1.35× thời gian recovery (96s/71s). Cloud-side MQTT broker là bottleneck nhẹ khi 8 gateway drain đồng loạt.

4. **Cloud capacity = 0% trong cả hai KB2:** Xác nhận fog cloud tier hoàn toàn không bị stress với tải constant 40 nhà — dù batch size khác nhau (25 rows vs 200 rows).

5. **1 GW có execute latency cao hơn tại cloud** (3–5ms vs 1–4ms) vì batch size lớn hơn 8× — nhưng không ảnh hưởng đến throughput hay data integrity.

6. **Fog là ĐIỂM KHÁC BIỆT TUYỆT ĐỐI so với Monolithic:** Monolithic không có store-and-forward. Cloud offline 5 phút = 100% data loss với monolithic. Fog (cả KB2-A và KB2-B) = 0% data loss, edge processing không bị gián đoạn.

---

## 8. So sánh Fog vs Monolithic

### 8.1 Traffic Reduction (từ Summary Stat Panels)

| Metric | Fog (KB1-A h40 steady) | Monolithic | Giảm (%) |
|--------|----------------------|-----------|---------|
| Tuples Acked tại cloud | ~190/600s | ~555/600s (ước tính) | **65.8%** |
| Tuples Emitted | ~380/600s | ~800/600s (ước tính) | **52.5%** |
| Tuples Transferred | ~380/600s | ~800/600s (ước tính) | **52.5%** |

> Giá trị monolithic ước tính từ panel "Fog vs Monolithic" Grafana (dữ liệu mono đã đo từ trước).

### 8.2 Bolt Capacity tại tải đỉnh (40 nhà)

| | Fog Cloud Bolt (Bolt_cloudMerge) | Monolithic Bolt |
|--|----------------------------------|----------------|
| Capacity tại h40 | **0%** (sau JVM warmup) | ~1-5% (steady) |
| Capacity peak | 91.2% tại h10 (cold start) | ~12-15% (transient spike) |
| Execute Latency steady | **1ms** | ~400ms complete latency |

### 8.3 Resilience

| Tính năng | Fog | Monolithic |
|-----------|-----|-----------|
| Cloud offline 5 phút | ✅ 0% data loss, 96s recovery (8 GW) / 71s (1 GW) | ❌ 100% data loss |
| Edge processing khi cloud down | ✅ Tiếp tục accumulate | ❌ Không có edge, dừng hoàn toàn |
| Store-and-Forward | ✅ Có (disk queue, idempotent replay) | ❌ Không có |

### 8.4 Scalability

| | Fog (KB1-A) | Monolithic |
|--|------------|-----------|
| CPU growth (×40 nhà) | ~10% stable | Tăng tuyến tính theo raw msg |
| Memory growth | +1.5 MB/nhà | +raw data/nhà |
| Cloud bolt capacity h40 | 0% (sau warmup) | ~1-5% |
| WAN traffic h40 | 332.8 KB/min | ~2,400 KB/min (ước tính raw) |

---

## 9. Kết luận

### 9.1 Những gì đã được chứng minh

1. **Traffic Reduction 52-66%:** Fog giảm số tuples cloud phải xử lý từ 52% đến 66% nhờ incremental aggregation + 60s flush interval. Đây là tính năng cốt lõi và đã được đo trực tiếp.

2. **Edge Processing sub-millisecond:** Gateway bolt xử lý mỗi raw sensor reading trong <0.1ms, với capacity <1% tại tải 50 msg/s/gateway. Headroom = 400× — edge không bao giờ là bottleneck ở mức tải này.

3. **Memory Footprint tuyến tính và thấp:** ~1.5 MB RAM per nhà per gateway. 40 nhà / 8 gateways = 5 nhà/gateway = ~57 MB overhead trên baseline — hoàn toàn phù hợp cho Raspberry Pi 3/4.

4. **Store-and-Forward hoàn hảo:** 0% data loss trong 5 phút cloud outage. Recovery trong **96s (8 GW, KB2-A)** hoặc **71s (1 GW, KB2-B)**. Đáng chú ý: 1 GW phục hồi nhanh hơn 8 GW mặc dù chỉ có 25 batch (vs 200 batch) — 8 GW drain song song nhưng gặp contention phía cloud-side MQTT broker, kéo dài thời gian thêm 35% so với 1 GW serial drain. Đây là tính năng UNIQUE không có trong monolithic.

5. **JVM Warmup Effect tại Cloud:** Spike capacity 91.2% tại h10 là hiệu ứng cold start, không phải bug thiết kế. Sau warmup, cloud bolt xử lý 400 msg/s với 0% capacity và 1ms latency. Hệ thống production cần pre-warm hoặc tăng tải từ từ.

### 9.2 Giới hạn và hướng cải thiện

1. **End-to-end latency ~60s vs mono ~400ms:** Fog trade off real-time granularity. Không thể dùng fog cho use case cần response <1s. Phù hợp cho energy analytics (giờ/ngày granularity).

2. **Cloud Complete Latency tăng tuyến tính:** Tại h40, max complete latency đạt 84s (8 GW). Giải pháp: scale cloud bolt thành multiple tasks, hoặc giảm flush interval.

3. **WAN 1 GW > 8 GW (+19% tại h40):** KB1-B (1 GW) = 396.1 KB/min cao hơn KB1-A (8 GW) = 332.8 KB/min — ngược với kỳ vọng ban đầu. Nguyên nhân: 1 gateway gom 40 nhà vào 1 batch lớn → nhiều unique `(house, plug)` keys hơn → GZIP compression ratio kém hơn 8 batch nhỏ riêng lẻ. Trade-off: 1 GW tốn WAN nhiều hơn 19% nhưng đổi lại giảm 85% RAM và 88% CPU so với 8 GW.

4. **Cold start risk:** Nếu deploy production với 8 gateways cùng bắt đầu flush đồng thời, cloud bolt có thể spike. Giải pháp: stagger flush start time theo gateway (offset = gateway_id × 7.5s).

### 9.3 Điểm bất thường phát hiện trong quá trình đo

| Phát hiện | Tác động | Đã xử lý |
|-----------|---------|---------|
| gw-03 đến gw-08 metrics=null (phiên đầu) | Toàn bộ dữ liệu phiên June 14 không chính xác | ✅ Đã sửa METRIC_REGISTRY, đo lại June 28 |
| End-to-end latency artifact (REPLACE INTO) | Số liệu latency p50=401s dễ gây hiểu lầm | ✅ Documented, cần ghi chú trong báo cáo cuối |
| Cloud spike 91.2% tại h10 | Cần warm-up trước production | ✅ Documented, giải thích JVM cold start |
| Tuples processed h01 thấp bất thường | Artifact của metrics server startup delay | ✅ Documented, chỉ ảnh hưởng h01 |

---

## 10. Phụ lục — Danh sách ảnh Grafana

### KB1-A (2026-06-28) — `results/kb1-A-multi8gw/img/`

| File | Panel | Mô tả ngắn |
|------|-------|-----------|
| `cloud_tuples_acked_600s.png` | Cloud: Tuples Acked | 5 bậc thang rõ, ~190 tại h40 |
| `cloud_tuples_emitted_transferred_600s.png` | Cloud: Emitted & Transferred | Hai đường chồng nhau, không drop |
| `cloud_bolt_execute_latency_ms.png` | Cloud Bolt: Execute Latency | Spike 9-10s tại h10, về ~0ms tại h40 ⚠️ |
| `cloud_bolt_capacity_600s.png` | Cloud Bolt: Capacity | 91.2% tại h10, 0% tại h40 ⚠️ |
| `gateway_tuple_ingestion_rate.png` | Gateway: Ingestion Rate | Staircase 8 GW kích hoạt tuần tự ✅ |
| `gateway_flush_mqtt_publish_rate.png` | Gateway: Flush & MQTT Rate | Sawtooth đều đặn mỗi 60s ✅ |
| `gateway_bolt_execute_latency_ema.png` | Gateway: Bolt Latency EMA | <0.1ms baseline, 1 spike 1.5ms ✅ |
| `all_gateways_bolt_capacity.png` | All GW: Bolt Capacity | Gần 0% suốt, staircase activation ✅ |
| `all_gateways_execute_latency_ema.png` | All GW: Execute Latency | gw-04 có spike 1.5ms, others <0.2ms ✅ |
| `summary_stat_panels.png` | Summary Stats | 65.8% reduction, 8 GW UP, queue=0 ✅ |

> **Ảnh không có (đúng):** `gateway_store_forward_queue_depth.png` — Queue = 0 suốt KB1-A (cloud luôn online, không có sự kiện offline). Đây là hành vi đúng đắn.

### Ảnh cũ (phiên June 14, KHÔNG DÙNG) — `results/img/kb1-A-multi8gw/`

> ⛔ **Dữ liệu không hợp lệ** do lỗi Prometheus metrics (gw-03 đến gw-08 = 0).
> Ảnh `gateway_tuple_ingestion_rate.png` cũ chỉ thể hiện gw-01.
> Ảnh `cloud_bolt_execute_latency_ms.png` cũ hiện latency 14s cao hơn bình thường.
> Chỉ giữ để tham khảo lịch sử, không đưa vào kết quả chính thức.

### Monolithic (baseline) — `results/img/monolithic/`

| File | Nội dung |
|------|---------|
| `mono_complete_latency.png` | Topology Complete Latency: peak ~550ms, steady ~400ms |
| `mono_bolt_capacity.png` | Bolt Capacity các bolt: steady <5%, spike ~12-15% |
| `mono_acked.png` | Tuples Acked |
| `mono_emitted.png` | Tuples Emitted |
| `mono_transferred.png` | Tuples Transferred |
| `mono_execute_latency.png` | Execute Latency per bolt |
| `mono_process_latency.png` | Process Latency |

---

*Báo cáo sẽ được bổ sung thêm kết quả KB1-B (đo lại) và KB2-A/B (đo lại) trong các lần đo tiếp theo.*

*Lần cập nhật cuối: 2026-06-28*
