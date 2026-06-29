# PROMPT TẠO ĐỒ ÁN LATEX — STORM SMART HOME (FOG vs MONOLITHIC)

Dán toàn bộ nội dung dưới đây vào Claude (claude.ai) hoặc ChatGPT để sinh file LaTeX hoàn chỉnh.

---

## HƯỚNG DẪN SỬ DỤNG PROMPT NÀY

Paste đoạn từ `=== BẮT ĐẦU PROMPT ===` đến `=== KẾT THÚC PROMPT ===` vào cửa sổ chat mới.
Mô hình sẽ sinh ra một file LaTeX duy nhất có thể upload thẳng lên Overleaf.

---

=== BẮT ĐẦU PROMPT ===

Hãy viết **toàn bộ mã nguồn LaTeX** cho một đồ án đại học hoàn chỉnh, **dài 60–80 trang** khi biên dịch trên Overleaf, bằng **tiếng Việt**, về đề tài:

> **"Xây dựng và đánh giá hiệu năng hệ thống Fog Computing cho IoT Nhà Thông Minh: So sánh kiến trúc Monolithic và Fog trên nền tảng Apache Storm"**

---

## YÊU CẦU CHUNG

- Document class: `\documentclass[13pt,a4paper]{report}` với các package: `fontenc[T5]`, `inputenc[utf8]`, `babel[vietnamese]`, `geometry` (margins 3cm trái, 2.5cm phải/trên/dưới), `graphicx`, `booktabs`, `longtable`, `xcolor`, `hyperref`, `pgfplots`, `tikz`, `pgf-pie`, `caption`, `subcaption`, `listings`, `amsmath`, `float`, `setspace` (1.5 line spacing), `fancyhdr`, `titlesec`, `tocloft`, `multirow`, `array`, `makecell`, `siunitx`, `cleveref`.
- **Vẽ TẤT CẢ biểu đồ bằng pgfplots/TikZ** (không dùng \includegraphics cho chart, chỉ dùng \includegraphics cho ảnh Grafana).
- Mọi bảng dùng `booktabs` (`\toprule`, `\midrule`, `\bottomrule`), không dùng `\hline`.
- Đánh số chương theo kiểu CHƯƠNG 1, CHƯƠNG 2... với lệnh `\chapter{...}`.
- Header/footer: trái = tên chương, phải = số trang.
- Trang bìa, trang xác nhận, trang lời cam đoan, tóm tắt tiếng Việt + tiếng Anh.
- Danh mục hình ảnh, danh mục bảng, danh mục từ viết tắt.
- Tài liệu tham khảo theo chuẩn IEEE (dùng `thebibliography`), tối thiểu 20 tài liệu.
- Phần phụ lục.

---

## CẤU TRÚC ĐỒ ÁN

### TRANG BÌA
```
TRƯỜNG ĐẠI HỌC CÔNG NGHỆ THÔNG TIN — ĐHQG TP.HCM
KHOA MẠNG MÁY TÍNH VÀ TRUYỀN THÔNG
ĐỒ ÁN TỐT NGHIỆP

XÂY DỰNG VÀ ĐÁNH GIÁ HIỆU NĂNG HỆ THỐNG
FOG COMPUTING CHO IOT NHÀ THÔNG MINH:
SO SÁNH KIẾN TRÚC MONOLITHIC VÀ FOG
TRÊN NỀN TẢNG APACHE STORM

Sinh viên: Nguyễn Gia Bảo — MSSV: ...
GVHD: ...
TP. Hồ Chí Minh, tháng 6 năm 2026
```

---

### CHƯƠNG 1 — MỞ ĐẦU (5–6 trang)

**1.1 Bối cảnh và động lực nghiên cứu**
Trình bày bùng nổ IoT (50 tỷ thiết bị 2030), thách thức băng thông + độ trễ khi đưa toàn bộ dữ liệu lên Cloud, giới thiệu Fog Computing như giải pháp tầng trung gian. Đề cập bài toán cụ thể: hệ thống giám sát tiêu thụ điện cho 40 ngôi nhà thông minh, mỗi nhà phát 10 msg/s liên tục = 400 msg/s tổng tải, cần xử lý real-time.

**1.2 Vấn đề đặt ra**
Kiến trúc Monolithic (toàn bộ pipeline trên Cloud) gặp điểm bão hòa tại ~200 msg/s (20 nhà), bolt_split vượt 169% capacity, complete latency 5.3s tại 400 msg/s. Cần kiến trúc thay thế.

**1.3 Mục tiêu nghiên cứu**
- Thiết kế và cài đặt kiến trúc Fog Computing với Apache Storm
- Cải tiến 10 thành phần kỹ thuật so với Monolithic
- Đo lường và so sánh 8 chỉ số hiệu năng trên 6 kịch bản thực nghiệm
- Triển khai thực tế trên Raspberry Pi 3

**1.4 Phạm vi và giới hạn**
- Phạm vi: 40 nhà, dataset REFIT-style, nền tảng Apache Storm + MQTT + MySQL
- Giới hạn: không so sánh với Spark Streaming hay Flink; không đo năng lượng tiêu thụ phần cứng Pi

**1.5 Đóng góp chính**
Liệt kê 10 cải tiến kỹ thuật cụ thể (xem Chương 3).

**1.6 Cấu trúc đồ án**
Mô tả ngắn từng chương.

---

### CHƯƠNG 2 — CƠ SỞ LÝ THUYẾT (10–12 trang)

**2.1 Internet of Things và Smart Home**
- Kiến trúc IoT 3 tầng: Perception → Network → Application
- Giao thức MQTT: publish/subscribe, QoS 0/1/2, use case IoT
- Dataset REFIT: 40 ngôi nhà Anh, đo công suất mỗi thiết bị 8 giây/lần

**2.2 Fog Computing**
- Định nghĩa NIST về Fog Computing
- So sánh Edge/Fog/Cloud (bảng 3 cột: thuộc tính, Edge, Fog, Cloud)
- Lợi ích: giảm băng thông, giảm độ trễ, offline resilience
- Mô hình Store-and-Forward: nguyên lý hoạt động khi mạng bị ngắt

**2.3 Apache Storm**
- Kiến trúc: Nimbus, Supervisor, Worker, Executor, Task
- Khái niệm: Topology, Spout, Bolt, Stream, Grouping
- Metric quan trọng: bolt_capacity, complete_latency, execute_latency, acked/emitted
- LocalCluster vs Distributed cluster

**2.4 Các công nghệ liên quan**
- Docker và Docker Compose: container hóa microservice
- Prometheus + Grafana: thu thập và hiển thị metrics
- MySQL: lưu trữ time-series aggregated
- GZIP: nén dữ liệu truyền WAN
- Raspberry Pi 3: thông số kỹ thuật (1.2 GHz ARM Cortex-A53, 1 GB RAM, WiFi)

**2.5 Các chỉ số hiệu năng**
Bảng định nghĩa đầy đủ 8 chỉ số, cách đo, đơn vị, ý nghĩa:

| Chỉ số | Ký hiệu | Đơn vị | Cách đo | Ý nghĩa |
|--------|---------|--------|---------|---------|
| Storm Complete Latency | $L_{complete}$ | ms | Prometheus (StormExporter) | Thời gian 1 tuple từ Spout → Ack |
| Bolt Capacity | $C_{bolt}$ | % | Prometheus | % thời gian bolt xử lý (>100% = overload) |
| Bolt Execute Latency | $L_{exec}$ | ms | Prometheus | Thời gian thực thi 1 lần gọi execute() |
| End-to-End DB Latency | $L_{e2e}$ | s | MySQL query SSH | Thời gian MQTT publish → ghi DB |
| WAN Traffic | $B_{WAN}$ | KB/min | Prometheus (gateway metric) | Băng thông gateway→cloud |
| Gateway RAM | $M_{GW}$ | MB | Docker stats | Bộ nhớ mỗi gateway container |
| Gateway CPU | $P_{GW}$ | % | Docker stats | Tải CPU mỗi gateway |
| Store-Forward Queue | $Q_{depth}$ | batch | Prometheus | Số batch đang chờ trong disk queue |

**2.6 Công trình liên quan**
Trích dẫn 5–8 bài báo về Fog Computing IoT, Edge AI, Apache Storm applications.

---

### CHƯƠNG 3 — THIẾT KẾ VÀ CÀI ĐẶT HỆ THỐNG (15–18 trang)

**3.1 Kiến trúc tổng thể**

Vẽ 2 sơ đồ TikZ so sánh:

*Sơ đồ 1 — Monolithic:*
```
[Sensor/Publisher] --MQTT--> [EC2 t3.large: MQTT Broker + Storm(Spout+Bolt_split+Bolt_avg+Bolt_sum+Bolt_forecast) + MySQL + Prometheus + Grafana]
```

*Sơ đồ 2 — Fog:*
```
[Sensor/Publisher] --MQTT raw--> [Fog Gateway: Storm LocalCluster (Spout_mqtt + Bolt_ingest)] --MQTT GZIP batch--> [EC2: Storm(Spout + Bolt_cloudMerge) + MySQL + Prometheus + Grafana]
                                         |
                               [Disk Queue: queue.jsonl] (Store-and-Forward)
```

**3.2 Kiến trúc Monolithic**

Mô tả chi tiết Storm topology Monolithic (8 cửa sổ thời gian: 1,5,10,15,20,30,60,120 phút):

Vẽ sơ đồ topology TikZ:
```
Spout-data → Bolt_split (phân loại theo time-window) → Bolt_avg (tính trung bình, flush DB)
                                                      → Bolt_sum (tổng hợp household)
                                                      → Bolt_forecast (dự báo)
Spout-trigger → kích hoạt flush định kỳ
```

Schema DB monolithic: `device_data` với primary key `(house_id, household_id, device_id, year, month, day, slice_gap, slice_index)`.

Bottleneck phát hiện: `Bolt_split` xử lý 100% raw messages, không song song được với cấu hình hiện tại → điểm nghẽn khi tải >200 msg/s.

**3.3 Kiến trúc Fog — Thiết kế từng thành phần**

*3.3.1 Fog Gateway (Raspberry Pi 3)*

**Kịch bản 8 gateway (KB1-A, KB2-A):** 7 Docker containers chạy trên MacBook/server + **1 Raspberry Pi 3** thực (tổng cộng 8 gateway, mỗi cái phụ trách 5 nhà). Cấu hình: Pi 3 chạy Docker container `fog-gateway:latest`, kết nối WiFi với MQTT simulator và cloud EC2.

**Kịch bản 1 gateway (KB1-B, KB2-B):** **1 Raspberry Pi 3** duy nhất chạy toàn bộ gateway, phụ trách tất cả 40 nhà. Thể hiện khả năng triển khai trên thiết bị nhúng tài nguyên thấp.

Vẽ sơ đồ TikZ deployment:
- Box "Raspberry Pi 3" với specs: ARM Cortex-A53 1.2GHz, 1GB RAM, Docker
- Box "MacBook/Server" với 7 Docker containers gw-01..gw-07  
- Arrow đến EC2 Cloud

*3.3.2 Storm LocalCluster tại Gateway*

Topology gateway: `Spout_mqtt → Bolt_ingest`

`Bolt_ingest` thực hiện:
1. Subscribe MQTT topic `iot-data`
2. Parse JSON payload: `{house_id, household_id, device_id, value, event_ts}`
3. Cập nhật 5 accumulator (ConcurrentHashMap) theo 5 time-window: 1, 5, 10, 15, 30 phút — **mỗi accumulator lưu (count, sum)** — không lưu raw data
4. Flush mỗi 60s: serialize toàn bộ accumulator → JSON → GZIP → MQTT publish topic `fog-data` lên cloud
5. **Store-and-Forward:** nếu MQTT publish fail → ghi batch vào `queue.jsonl` trên disk

Vẽ sơ đồ luồng xử lý Bolt_ingest (TikZ flowchart).

*3.3.3 Cơ chế Store-and-Forward*

Vẽ sơ đồ state machine TikZ:
```
[MQTT Publish] → SUCCESS → clear batch
              → FAIL → append to queue.jsonl
              
[drainQueue()] → đọc queue.jsonl → publish tuần tự → xóa entry khi thành công
```

Tính toán: 1 GW × 5 windows × 5 flush cycles/5min = 25 batch; 8 GW = 200 batch.

*3.3.4 Energy Optimizer — Tự động tiết kiệm tài nguyên*

Một daemon Node.js (`tools/energy_optimizer.js`) chạy song song với hệ thống Fog, thực hiện **auto-scaling thông minh** ở tầng edge:

**Nguyên lý hoạt động:**
1. Daemon subscribe topic MQTT `iot-data`, parse `houseId` từ mỗi message (field thứ 7 trong CSV payload)
2. Cập nhật `gwLastSeen[gw] = Date.now()` cho gateway phụ trách nhà đó (map: house_id ÷ 5 + 1 = gw_num)
3. Mỗi 3 giây, vòng lặp kiểm tra: nếu `Date.now() - gwLastSeen[gw] > 15,000ms` → gateway idle → `docker pause gw-0N`
4. Nếu traffic quay lại → `docker unpause gw-0N` để tiếp tục xử lý

**Tại sao dùng `docker pause` thay vì `docker stop`?**
- `docker stop` → JVM shutdown → restart mất ~10s, mất accumulator state trong memory
- `docker pause` → Linux cgroups freezer → process frozen, RAM giữ nguyên, CPU = 0% — không mất state
- Unpause latency < 50ms (xác nhận từ log: `[ACTIVATE]` → `[SUCCESS]` trong ~100ms)

**Tiết kiệm tài nguyên:**
- 1 JVM Gateway idle: ~200MB RAM + 2–5% CPU
- 1 JVM Gateway paused: ~200MB RAM + **0% CPU** (frozen)
- Kịch bản thực tế: 6 GW idle (chờ nhà ở nấc h10 chỉ có 2 GW active) → tiết kiệm ~12–30% CPU host

**Test tự động** (`tools/test_energy_optimizer.sh`) xác nhận:
- 8 GW paused trong 18s khi không có traffic ✅
- Publish 1 message cho house-0 → gw-01 unpause trong <4s ✅  
- gw-02..gw-08 vẫn giữ paused ✅

Vẽ sơ đồ TikZ state machine cho gateway lifecycle:
```
RUNNING ──(idle > 15s)──> PAUSED
PAUSED  ──(traffic)────> RUNNING (unpause <50ms)
```
Chú thích: Fog-1GW không dùng energy optimizer (chỉ 1 gateway — không có gì để selective pause).

*3.3.5 Cloud Storm Topology (Fog)*

Đơn giản hơn Monolithic nhiều — chỉ 1 bolt:
```
Spout_mqtt (subscribe "fog-data") → Bolt_cloudMerge (REPLACE INTO MySQL)
```

`Bolt_cloudMerge.execute()`:
1. Nhận MQTT batch (GZIP)
2. Giải nén + parse JSON aggregated records
3. Một lệnh `REPLACE INTO fog_device_data (house_id,...,value,count,updatedAt) VALUES (...)`
4. Idempotent: cùng key được ghi đè, không tạo duplicate

Schema cloud: `fog_device_data` với cột `(house_id, household_id, device_id, slice_gap, slice_index, value, count, updatedAt)`.

**3.4 Mười cải tiến kỹ thuật so với Monolithic**

Trình bày dạng bảng + mô tả chi tiết mỗi cải tiến:

| # | Thành phần | Vấn đề Monolithic | Giải pháp Fog | Tác động đo được |
|---|-----------|------------------|--------------|-----------------|
| 1 | Prometheus METRIC_REGISTRY | Khi Storm LocalCluster restart bolt task trong cùng JVM, `new PrometheusMetricsServer(port)` ném `IOException: Address already in use` → `metrics = null` → mọi counter bị bỏ qua silently → gw-03 đến gw-08 không báo metrics | Dùng `ConcurrentHashMap<Integer, PrometheusMetricsServer>` singleton với `computeIfAbsent` — nếu port đã bind, reuse instance cũ | Toàn bộ 8 gateway báo metrics đúng; phát hiện được lỗi đo trước đó |
| 2 | Xử lý raw data | Bolt_split nhận 100% raw messages (400 msg/s tại h40) → bottleneck 169% capacity | Bolt_ingest tích lũy incrementally (count++, sum+=value) trong memory, không cần fan-out | Gateway bolt capacity <1% tại 50 msg/s |
| 3 | 5 time windows | Monolithic: 8 windows qua 4 bolt layers → O(n×8) tuples | Fog: 5 windows trong 1 bolt, 1 accumulator dict — không tạo tuple nào | Không có internal network traffic |
| 4 | GZIP batch compression | Monolithic: raw JSON từng message lên cloud | Fog: 60s buffer → GZIP batch → MQTT | WAN giảm ~86% vs raw (2,400 → 332 KB/min) |
| 5 | Store-and-Forward disk queue | Monolithic: cloud offline = 100% data loss | Fog: `queue.jsonl` + drainQueue() | 0% data loss, 96s recovery sau 5 phút outage |
| 6 | EWMA Z-score anomaly detection | Không có | Bolt_ingest tính EWMA μ/σ cho mỗi device, trigger alert nếu |z|>3 | Phát hiện anomaly tại edge, không cần gửi lên cloud |
| 7 | Per-house Slack routing | Không có alerting | Mỗi nhà có webhook Slack riêng, Bolt_ingest route đúng channel | Alert trong <1s sau khi phát hiện anomaly |
| 8 | TagAwareScheduler | Storm mặc định không đảm bảo affinity | TagAwareScheduler gán executor của gateway đến đúng supervisor theo tag | Ổn định topology assignment, giảm network hop |
| 9 | REPLACE INTO idempotent | Monolithic INSERT → duplicate risk khi retry | `REPLACE INTO` với composite PK → retry-safe | 0 duplicate row sau drain recovery |
| 10 | Cloud topology đơn giản hóa | Monolithic: 4 bolt layers + 8 window streams | Fog: 1 bolt (Bolt_cloudMerge) | Cloud capacity 0% tại h40 steady-state |
| 11 | **Energy Optimizer daemon** | Không có — idle JVM tiêu 2–5% CPU liên tục | Node.js daemon monitor MQTT traffic, `docker pause` GW idle >15s, `docker unpause` <50ms khi traffic quay lại (cgroups freezer) | CPU Gateway idle = **0%** (từ 2–5%); test tự động xác nhận; chỉ dùng kịch bản 8 GW |

*Giải thích chi tiết mỗi cải tiến trong 3.4.1 đến 3.4.11, mỗi mục 0.5–1 trang, có đoạn code giả (pseudocode) minh họa bằng môi trường `lstlisting`.*

**3.5 Sơ đồ triển khai (Deployment Diagram)**

Vẽ TikZ diagram phân tầng:
- Tầng 1: Sensors/Publishers (40 houses × simulator)
- Tầng 2: Fog Edge — Raspberry Pi 3 (+ 7 Docker containers nếu 8-GW mode)
- Tầng 3: WAN (đường mũi tên MQTT GZIP)
- Tầng 4: AWS EC2 ap-southeast-1 (Storm cluster: Nimbus + Supervisor + ZK + MySQL + Prometheus + Grafana)
- Tầng 5: Web Dashboard (port 9000)

**3.6 Cấu hình phần cứng và phần mềm**

Bảng so sánh môi trường:

| Thành phần | Monolithic | Fog (8 GW) | Fog (1 GW) |
|-----------|-----------|-----------|-----------|
| Cloud instance | EC2 t3.large (2vCPU, 8GB) | EC2 t3.small (2vCPU, 2GB) | EC2 t3.small |
| Edge hardware | — | 7× Docker + 1× Pi 3 (1.2GHz, 1GB) | 1× Pi 3 |
| Apache Storm | 2.1.0 (distributed) | LocalCluster | LocalCluster |
| MySQL | 8.4.2 | 8.4.2 | 8.4.2 |
| MQTT Broker | mosquitto | mosquitto | mosquitto |
| Prometheus | 2.54.1 | 2.54.1 | 2.54.1 |
| Grafana | 11.1.5 | 11.1.5 | 11.1.5 |

---

### CHƯƠNG 4 — PHƯƠNG PHÁP THỰC NGHIỆM (8–10 trang)

**4.1 Tổng quan 6 kịch bản đo**

| Kịch bản | Ký hiệu | Hệ thống | Mục tiêu | Ngày đo |
|---------|---------|---------|---------|---------|
| Ramp Monolithic | MONO-KB1 | Monolithic | Điểm bão hòa | 2026-06-18 |
| Steady Monolithic | MONO-KB2 | Monolithic | Headline metrics | 2026-06-18 |
| Ramp Fog 8 GW | FOG-KB1-A | Fog 8 GW (7 Docker + 1 Pi 3) | Scalability phân tán | 2026-06-28 |
| Ramp Fog 1 GW | FOG-KB1-B | Fog 1 GW (1 Pi 3) | Scalability đơn | 2026-06-28 |
| Recovery Fog 8 GW | FOG-KB2-A | Fog 8 GW | Store-and-Forward | 2026-06-28 |
| Recovery Fog 1 GW | FOG-KB2-B | Fog 1 GW | Store-and-Forward | 2026-06-28 |

**4.2 Dataset và Publisher**

- Nguồn: REFIT dataset (40 ngôi nhà, thiết bị đo công suất mỗi 8 giây)
- Publisher: Node.js, phát MQTT message với `event_ts = Date.now()`
- SPEED=10 msg/s mỗi nhà, topic `iot-data`, QoS=0
- Ramp: 5 nấc × 360s/nấc = h01 → h05 → h10 → h20 → h40
- Steady: 1800s tại 40 nhà

**4.3 Metrics thu thập và công cụ**

| Metric | Nguồn | Script | Tần suất |
|--------|-------|--------|---------|
| Storm Complete Latency | Prometheus StormExporter | `observe_ramp*.sh` | Cuối mỗi nấc |
| Bolt Capacity | Prometheus | `observe_ramp*.sh` | Cuối mỗi nấc |
| Gateway Exec Latency | Prometheus (fog_gateway_*) | `observe_ramp*.sh` | Cuối mỗi nấc |
| WAN KB/min | Prometheus (fog_gateway_flush_total, publish_size) | `observe_ramp*.sh` | Cuối mỗi nấc |
| CPU/RAM | Docker stats → python | `observe_ramp*.sh` | Mỗi 12s |
| End-to-end Latency | MySQL SSH query | `latency_report.sh` | Sau mỗi kịch bản |
| Queue Depth | Prometheus (fog_gateway_store_queue_size) | `kb2_offline_recovery.sh` | Mỗi 5s |

Mô tả chi tiết câu lệnh query Prometheus và SQL query latency.

**4.4 Script tự động hóa**

Mô tả ba script chính:
- `tools/observe_ramp.sh` — ramp scalability (fog), tự động tăng tải và snapshot metrics cuối mỗi nấc
- `tools/kb2_offline_recovery.sh` — offline recovery test: warmup 15 phút → tắt cloud-mqtt 5 phút → bật lại → đo recovery time
- `tools/observe_ramp_mono.sh` — ramp scalability (mono)

**4.5 Hạn chế và biện pháp kiểm soát**

- Biện pháp: chạy lại nếu có outlier, reset Docker giữa các kịch bản
- Hạn chế đo lường "End-to-end latency": do `REPLACE INTO` dùng `NOW()` → `updatedAt` luôn = lần ghi cuối, không phải đầu tiên → giá trị cao (401–655s) là artifact thiết kế, không phải latency thực. Latency ghi đầu tiên ≈ 60–65s (flush interval + cloud processing).

---

### CHƯƠNG 5 — KẾT QUẢ HỆ THỐNG MONOLITHIC (10–12 trang)

**5.1 MONO-KB1 — Ramp Scalability**

**Bảng 5.1 — Số liệu MONO-KB1**

| Số nhà | Msg/s | Complete Latency | Bolt Split Max Capacity | Acked/600s | Emitted/600s | Ack Ratio |
|--------|-------|-----------------|------------------------|-----------|-------------|---------|
| 1 | 10 | 55 ms | 45.5% | 2,840 | 82,460 | 3.4% |
| 5 | 50 | 97 ms | 11.2% | 13,973 | 438,034 | 3.2% |
| 10 | 100 | 290 ms | 3.9% | 30,326 | 1,057,009 | 2.9% |
| 20 | 200 | 1,111 ms ⚠ | 89.8% ⚠ | 22,422 | 1,493,779 | 1.5% |
| 40 | 400 | 5,282 ms 🔴 | 169% 🔴 | 6,873 | 1,547,121 | 0.4% |

**Biểu đồ 5.1 (pgfplots, grouped bar):**
Trục X: số nhà (1, 5, 10, 20, 40)
Trục Y trái: Complete Latency (ms), log scale
Màu: xanh dương
Title: "MONO-KB1: Storm Complete Latency theo số nhà (ms)"
Vẽ đường tham chiếu ngang tại 1000ms (ngưỡng degradation).

**Biểu đồ 5.2 (pgfplots, line+bar combo):**
Bar: Bolt Split Capacity (%), trục Y trái, màu đỏ
Đường: Ack Ratio (%), trục Y phải, màu cam
Title: "MONO-KB1: Bolt Capacity và Ack Ratio"
Annotation: "Điểm bão hòa: 20 nhà" với mũi tên.

**5.2 Phân tích bottleneck Monolithic**

Giải thích chi tiết: Bolt_split nhận toàn bộ 400 msg/s, phải phân loại vào 8 time-window × nhiều device → throughput thực 237 msg/s (= 400 × 1/1.69) → queue tích lũy 163 msg/s → sau 360s tại nấc h40 có 58,680 message chờ trong queue.

Vẽ sơ đồ TikZ minh họa flow: [Spout 400/s] → [Bolt_split 169% cap.] → queue overflow → [Bolt_avg 8.9%] → timeout/drop.

**5.3 MONO-KB2 — Steady State 40 Nhà**

**Bảng 5.2 — Số liệu MONO-KB2 (steady 30 phút)**

| Metric | Giá trị | Ghi chú |
|--------|---------|---------|
| Complete Latency (mean Grafana) | 1.13 s | Bao gồm drain phase |
| Complete Latency (steady ~2.75s) | 2.75 s | Giai đoạn ổn định |
| Complete Latency (max) | 5.09 s | Cuối session khi publisher dừng |
| Split Bolt Capacity (max) | 99–189% | Bottleneck rõ ràng |
| Forecast-1 Execute Latency (max) | 47.8 ms | Bolt nặng nhất ngoài split |
| Spout Emitted Rate (max) | 296 ops/s | Bị throttle từ 400 input |
| DB Rows Written | 26,965 | Trong 30 phút |
| End-to-End Latency p50 | 655 s | Measurement artifact |
| End-to-End Latency p95 | 1,258 s | |

Mô tả hiện tượng bell curve trên Grafana topology throughput, giải thích drain phase sau publisher dừng.

**5.4 Tóm tắt điểm mạnh/yếu Monolithic**

Bảng 2 cột: Ưu điểm | Hạn chế.

---

### CHƯƠNG 6 — KẾT QUẢ HỆ THỐNG FOG COMPUTING (15–18 trang)

**6.1 FOG-KB1-A — Ramp Scalability 8 Gateway**

*Môi trường: 7 Docker containers + 1 Raspberry Pi 3, phụ trách lần lượt 5 nhà/gateway theo thứ tự kích hoạt gw-01→gw-08.*

**Bảng 6.1 — Số liệu FOG-KB1-A**

| Nhà | Msg/s | Cloud Bolt Capacity | Cloud Complete Lat. | GW Exec Lat. | GW Flush Lat. | CPU/GW | RAM/GW | WAN (KB/min) | Tuples |
|-----|-------|--------------------|--------------------|-------------|--------------|--------|--------|-------------|--------|
| 1 | 10 | 0% | N/A | 0.032 ms | 93.8 ms | 11.8% | 182 MB | 15.0 | 2,527 |
| 5 | 50 | 0% | 4.5 ms | 0.073 ms | 100.3 ms | 16.4% | 191 MB | 40.2 | 14,659 |
| 10 | 100 | **91.2%** ⚠ | 14,520 ms | 0.068 ms | 540.2 ms | 11.4% | 194 MB | 88.9 | 38,480 |
| 20 | 200 | 4.6% | 34,974 ms | 0.067 ms | 307.6 ms | 13.1% | 229 MB | 159.4 | 85,884 |
| 40 | 400 | **0%** ✅ | 84,499 ms | 0.044 ms | 614.4 ms | 10.6% | 239 MB | 332.8 | 173,249 |

> Lưu ý: Cloud Complete Latency cao (14–84s) là artifact của REPLACE INTO cumulative semantics — `updatedAt` luôn = lần ghi cuối → đo từ sensor đến lần ghi cuối. Latency thực của lần ghi đầu tiên ≈ 60s (flush interval).

**Biểu đồ 6.1 (pgfplots bar chart):**
- X: số nhà
- Y: Cloud Bolt Capacity (%)
- Màu: xanh lá (lành mạnh) cho h40 (0%), cam cho h10 (91.2%)
- Annotation mũi tên giải thích "JVM cold-start spike tại h10, tự phục hồi về 0% tại h40"
- Title: "FOG-KB1-A: Cloud Bolt Capacity (8 Gateway)"

**Biểu đồ 6.2 (pgfplots line):**
- X: số nhà
- Y: Gateway Exec Latency EMA (ms)
- Hiển thị đường phẳng <0.1ms xuyên suốt
- Title: "FOG-KB1-A: Gateway Bolt Execute Latency (ms) — Sub-millisecond toàn bộ tải"

Giải thích staircase activation: gw-01 (h01) → gw-02 (h10) → ... → gw-08 (h40).

Giải thích anomaly JVM cold-start tại h10: burst đồng thời từ 2 GW + MySQL JDBC cold → spike 91.2% capacity rồi tự phục hồi nhờ JIT compilation.

**6.2 FOG-KB1-B — Ramp Scalability 1 Gateway (Raspberry Pi 3)**

*Môi trường: 1 Raspberry Pi 3 phụ trách toàn bộ 40 nhà.*

**Bảng 6.2 — Số liệu FOG-KB1-B**

| Nhà | Msg/s | Cloud Bolt Capacity | Cloud Complete Lat. | GW Bolt Cap. | GW Exec Lat. | GW Flush Lat. | CPU | RAM | WAN (KB/min) |
|-----|-------|--------------------|--------------------|-------------|-------------|--------------|-----|-----|-------------|
| 1 | 10 | **35.3%** | 3.5 ms | 0.04% | 0.045 ms | 927.5 ms | 10.9% | 186 MB | 14.0 |
| 5 | 50 | **21.2%** | 3.5 ms | 0.14% | 0.023 ms | 661.2 ms | 10.2% | 194 MB | 41.8 |
| 10 | 100 | ~0% | 8,729 ms | 0.19% | 0.049 ms | 967.9 ms | 13.1% | 211 MB | 88.8 |
| 20 | 200 | ~0% | 46,123 ms | 0.80% | 0.048 ms | 1,061 ms | 14.9% | 250 MB | 164.5 |
| 40 | 400 | **318.9%** 🔴 | 93,387 ms | 0.95% | 0.030 ms | 759.2 ms | 11.2% | 288 MB | 396.1 |

Giải thích: 1 GW gửi 40 nhà × 5 windows = 200 records/batch vào Bolt_cloudMerge → REPLACE INTO 200 rows = 47.8s execute → 318.9% capacity. Bottleneck ở cloud, không phải edge (GW capacity <1%).

**Biểu đồ 6.3 (pgfplots bar so sánh KB1-A vs KB1-B):**
Grouped bar, X = số nhà, Y = Cloud Bolt Capacity (%), 2 màu: xanh (8 GW) và cam (1 GW).
Annotation: "8 GW: tự phục hồi về 0% tại h40" và "1 GW: overload 318.9% tại h40".

**Biểu đồ 6.4 (pgfplots bar):**
X: metric category (RAM tổng, CPU tổng, WAN h40)
Y: giá trị tương đối (% so với 8 GW = 100%)
Bars: Fog 8 GW vs Fog 1 GW
Giá trị: RAM (1,912 MB vs 288 MB = 84.9% tiết kiệm), CPU sum (~90% vs 11% = 87.8%), WAN (332.8 vs 396.1 = 1 GW cao hơn 19%)
Title: "FOG KB1-A vs KB1-B: So sánh tài nguyên tại h40"

**6.3 FOG-KB2-A — Cloud Offline Recovery: 8 Gateway**

*Môi trường: 8 GW (7 Docker + 1 Pi 3), tải constant 40 nhà. Timeline: warmup 15 phút → outage 5 phút → drain → post-recovery 5 phút.*

**Bảng 6.3 — Số liệu FOG-KB2-A**

| Chỉ số | Giá trị |
|--------|---------|
| Thời gian outage | 300s (5 phút) |
| Max Queue Depth | **200 batch** (= 8 GW × 5 windows × 5 cycles) |
| Recovery Time | **96s** |
| Data Loss | **0.0%** |
| Drain Rate | 2.08 batch/s |
| Tuples xử lý (30 phút) | 182,223 |

Mô tả timeline chi tiết: staircase tăng queue 0→40→80→120→160→200, sau đó drain về 0 trong 96s.

Vẽ sơ đồ TikZ timeline store-and-forward với trục thời gian:
```
0min     15min        20min  21:36   26:36
|-----warmup-----|----outage----|---drain---|---post---|
queue: 0                       200          0
```

Giải thích tại sao 8 GW drain hơi chậm hơn 1 GW (96s vs 71s): cloud-side MQTT broker contention khi 8 gateway drain đồng loạt.

**6.4 FOG-KB2-B — Cloud Offline Recovery: 1 Gateway (Raspberry Pi 3)**

**Bảng 6.4 — Số liệu FOG-KB2-B**

| Chỉ số | Giá trị |
|--------|---------|
| Max Queue Depth | **25 batch** (= 1 GW × 5 windows × 5 cycles) |
| Recovery Time | **71s** |
| Data Loss | **0.0%** |
| Drain Rate | 0.352 batch/s |
| Tuples xử lý (30 phút) | 175,879 |

Vẽ biểu đồ TikZ bar so sánh KB2-A vs KB2-B cho queue depth, recovery time, drain rate.

**6.5 Phân tích cơ chế Store-and-Forward**

Mô tả công thức toán học:
- Max queue = $N_{GW} \times W_{windows} \times \lfloor T_{outage} / T_{flush} \rfloor$
- Drain rate = $Q_{max} / T_{recovery}$
- Điều kiện hội tụ: drain rate > accumulation rate → $Q_{max}/T_{rec} > N_{GW} \times W / T_{flush}$

Kiểm chứng: KB2-A: 2.08 > 0.67 ✓; KB2-B: 0.352 > 0.083 ✓

---

### CHƯƠNG 7 — SO SÁNH VÀ PHÂN TÍCH (12–15 trang)

**7.1 So sánh Scalability: Monolithic vs Fog**

**Bảng 7.1 — Complete Latency so sánh tại các nấc tải**

| Nhà | Msg/s | MONO Complete Lat. | FOG-8GW Complete Lat. | FOG-1GW Complete Lat. |
|-----|-------|-------------------|-----------------------|-----------------------|
| 1 | 10 | 55 ms | N/A (sub-ms) | 3.5 ms |
| 5 | 50 | 97 ms | 4.5 ms | 3.5 ms |
| 10 | 100 | 290 ms | 14,520 ms* | 8,729 ms* |
| 20 | 200 | 1,111 ms | 34,974 ms* | 46,123 ms* |
| 40 | 400 | 5,282 ms | 84,499 ms* | 93,387 ms* |

> *Chú thích: Complete Latency Fog cao do REPLACE INTO cumulative semantics — đo từ event_ts đến lần ghi cuối. Latency thực ghi đầu tiên ≈ 60s. Hai hệ thống đo các đại lượng khác nhau — xem §7.1.1.

**7.1.1 Tại sao Complete Latency Fog > Mono?**

Trình bày rõ: Mono tính từ MQTT arrive → Bolt_forecast ack (vài giây). Fog tính từ sensor event_ts → updatedAt (lần REPLACE INTO cuối = luôn NOW()). Mỗi lần flush 60s sẽ cập nhật lại updatedAt → record từ 14:20 sẽ có updatedAt = 14:50 → latency = 30 phút.

Bảng so sánh công bằng:

| Tiêu chí | Monolithic | Fog (8 GW) | Fog (1 GW) |
|---------|-----------|-----------|-----------|
| Bolt Capacity tại h40 | **189%** 🔴 | **0%** ✅ | **318.9%** 🔴 |
| Bottleneck | Bolt_split (cloud) | JVM cold-start h10 (tự phục hồi) | Bolt_cloudMerge (cloud, không phục hồi) |
| Spout throttle tại h40 | 199 ops/s (vs 400) | Không bị throttle | Bị throttle do overload |
| Khả năng scale thêm | Không (đã saturate) | Có (0% headroom còn nhiều) | Không (318.9%) |

**Biểu đồ 7.1 (pgfplots, grouped bar — QUAN TRỌNG NHẤT):**
X: số nhà (10, 20, 40)
Y: Cloud Bolt Max Capacity (%)
3 nhóm: MONO (đỏ) | FOG-8GW (xanh lá) | FOG-1GW (cam)
Đường đứt ngang tại 100% (ngưỡng overload)
Giá trị: h10: [3.9%, 91.2%, 0%]; h20: [89.8%, 4.6%, 0%]; h40: [169%, 0%, 318.9%]
Caption: "So sánh Cloud Bolt Capacity: Fog 8 GW duy trì 0% tại h40 trong khi Monolithic và Fog 1 GW đều overload"

**7.2 So sánh Tài nguyên tại h40**

**Bảng 7.2 — Tài nguyên toàn hệ thống tại 400 msg/s**

| Tài nguyên | MONO | FOG-8GW | FOG-1GW | Ghi chú |
|-----------|------|---------|---------|---------|
| Cloud CPU | ~80% | <5% | <5% | Fog nhẹ hơn nhiều ở cloud |
| RAM tổng edge | 0 MB | 1,912 MB | 288 MB | Fog cần edge RAM |
| CPU tổng edge | 0 | ~90% sum | ~11% | Fog cần edge CPU |
| WAN (KB/min) | ~2,400* | 332.8 | 396.1 | Fog giảm WAN 86% |
| Containers | 1 (cloud) | 8 (edge)+cloud | 1 (Pi 3)+cloud | |

*Ước tính raw: 400 msg/s × 100 bytes = 40,000 bytes/s = 2,400 KB/min

**Biểu đồ 7.2 (pgfplots, horizontal bar — WAN comparison):**
X: WAN KB/min
Y: 3 hệ thống (MONO raw ~2400, FOG-8GW 332.8, FOG-1GW 396.1)
Màu gradient từ đỏ → xanh theo giá trị thấp
Caption: "WAN Traffic tại h40: Fog giảm 86% so với Monolithic raw (332.8 KB/min vs ~2,400 KB/min)"

**Biểu đồ 7.3 (pgfplots, stacked bar — RAM breakdown):**
MONO: cloud RAM ~4GB, edge 0
FOG-8GW: cloud RAM ~1GB, edge 1,912MB (8×239)
FOG-1GW: cloud RAM ~1GB, edge 288MB

**7.3 Traffic Reduction**

**Bảng 7.3 — Traffic Reduction so với Monolithic**

| Metric | FOG-KB1-A (8 GW) | FOG-KB1-B (1 GW) |
|--------|-----------------|-----------------|
| Acked Tuple Reduction | 65.8% | **95%** |
| Emitted/Transferred Reduction | 52.5% | **92.5%** |
| WAN Traffic (vs raw 2,400) | **−86.1%** (332.8) | −83.5% (396.1) |

Giải thích tại sao 1 GW có reduction cao hơn 8 GW: 1 stream MQTT duy nhất compact hơn, nhưng WAN tổng lại cao hơn 8 GW 19% do GZIP compression ratio kém hơn với batch lớn (nhiều unique keys).

**Biểu đồ 7.4 (pgfplots, grouped bar — Traffic Reduction):**
X: metric (Acked %, Emitted %, WAN savings %)
Y: %
2 bars: 8 GW (xanh) vs 1 GW (cam)

**7.4 So sánh Fault Tolerance**

**Bảng 7.4 — Khả năng chịu lỗi**

| Tình huống | MONO | FOG-8GW | FOG-1GW |
|-----------|------|---------|---------|
| Cloud MQTT offline 5 phút | ❌ 100% data loss | ✅ 0% loss, 96s recovery | ✅ 0% loss, 71s recovery |
| Edge processing khi cloud down | ❌ Không có edge | ✅ Tiếp tục 100% | ✅ Tiếp tục 100% |
| 1 gateway lỗi | N/A | 12.5% nhà ảnh hưởng | 100% nhà ảnh hưởng |
| Restart gateway | N/A | Queue giữ data, drain sau restart | Queue giữ data |

**Biểu đồ 7.5 (pgfplots, bar — Recovery Metrics KB2):**
X: metric (Max Queue Depth batch, Recovery Time s, Data Loss %)
Y: giá trị
2 bars: KB2-A 8GW (xanh) vs KB2-B 1GW (cam)
Values: Queue [200, 25], Recovery [96s, 71s], Loss [0%, 0%]

**7.5 Bảng tổng hợp cuối — Ma trận so sánh toàn diện**

**Bảng 7.5 — Ma trận so sánh MONO vs FOG-8GW vs FOG-1GW**

| Tiêu chí | Trọng số | MONO | FOG-8GW | FOG-1GW |
|---------|---------|------|---------|---------|
| Scalability (cloud capacity h40) | 25% | 🔴 Tệ (169%) | 🟢 Tốt (0%) | 🔴 Tệ (318.9%) |
| Traffic Reduction WAN | 20% | 🔴 0% | 🟡 −86.1% | 🟡 −83.5% |
| Fault Tolerance | 20% | 🔴 0% loss prevention | 🟢 0% loss, 96s | 🟢 0% loss, 71s |
| Edge Resource (RAM+CPU) | 15% | 🟢 Không cần | 🔴 1,912MB, ~90% | 🟡 288MB, 11% |
| Deployment Complexity | 10% | 🟢 Đơn giản nhất | 🔴 Phức tạp (8 nodes) | 🟡 Trung bình |
| Bottleneck Risk | 10% | 🔴 Bolt_split | 🟢 Không (h40 steady) | 🔴 Bolt_cloudMerge |
| Energy Optimization | bonus | 🔴 Không có | 🟢 Auto-pause idle GW (CPU 0%), wake <50ms | 🟡 N/A (1 GW) |

**7.6 Ngưỡng và Khuyến nghị**

- **Dùng FOG-8GW khi:** ≥20 nhà, yêu cầu fault isolation, WAN bandwidth hạn chế, có nhiều Raspberry Pi
- **Dùng FOG-1GW khi:** ≤10 nhà (cloud capacity <35% an toàn), 1 Pi 3 duy nhất, đơn giản hóa deployment
- **Không dùng MONO khi:** >10 nhà — bắt đầu degradation, >20 nhà — overload nghiêm trọng

**Biểu đồ 7.6 (pgfplots, line chart — Scalability roadmap):**
X: số nhà (1, 5, 10, 20, 40, 80*, 160*)
Y: Cloud Bolt Capacity (%)
3 đường: MONO (đỏ, extrapolated), FOG-8GW (xanh), FOG-1GW (cam)
Đường ngang tại 100% = giới hạn
Vùng xanh <100% = healthy, vùng đỏ >100% = overload

---

### CHƯƠNG 8 — KẾT LUẬN VÀ HƯỚNG PHÁT TRIỂN (4–5 trang)

**8.1 Kết quả đạt được**

Liệt kê rõ ràng 5 kết quả chính:
1. Thiết kế và triển khai thành công hệ Fog Computing với 10 cải tiến kỹ thuật so với Monolithic
2. Chứng minh Fog-8GW đạt 0% cloud bolt capacity tại h40 vs Monolithic 169% — cải thiện vô hạn
3. Store-and-Forward đạt 0% data loss trong 5 phút outage, recovery trong 71–96s
4. WAN traffic giảm 86% (332.8 vs 2,400 KB/min ước tính raw)
5. Gateway Raspberry Pi 3 xử lý 50 msg/s với <0.1ms execute latency, <1% bolt capacity — headroom 400×

**8.2 Hạn chế và điểm chưa hoàn thiện**

1. Fog-1GW bị overload tại h40 (318.9%) — cần cải thiện Bolt_cloudMerge (batch transaction)
2. End-to-end latency measurement artifact — cần cơ chế event_ts riêng cho lần ghi đầu tiên
3. Chưa đo trên Raspberry Pi 3 physical với 8 instances (chỉ 1 Pi + 7 Docker)
4. Chưa đánh giá tiêu thụ điện của Raspberry Pi 3

**8.3 Hướng phát triển**

1. Tối ưu Bolt_cloudMerge: batch INSERT nhiều row trong 1 transaction để giảm per-row overhead
2. Thêm time-window 5-minute và 1-hour để so sánh với Monolithic 8-window
3. Auto-scaling gateway: tự động tăng số GW khi tải tăng
4. Triển khai hoàn toàn trên cluster Raspberry Pi 3 (Kubernetes k3s)
5. Mã hóa MQTT payload (TLS) và GZIP trong môi trường production
6. So sánh thêm với Apache Flink và Spark Streaming

---

### TÀI LIỆU THAM KHẢO

Tối thiểu 20 tài liệu theo chuẩn IEEE bao gồm:
- NIST Fog Computing definition (NIST SP 500-325)
- OpenFog Consortium Reference Architecture
- Apache Storm documentation
- Bài báo về Edge Computing IoT (IEEE IoT Journal)
- REFIT dataset paper
- Bài báo về MQTT performance
- Bài báo về store-and-forward IoT
- Prometheus monitoring documentation

---

### PHỤ LỤC

**Phụ lục A — Giải thích artifact End-to-End Latency**
Chi tiết về `REPLACE INTO ... SET updatedAt = NOW()` và tại sao p50=655s không phải latency thực.

**Phụ lục B — Code snippets quan trọng**
Pseudocode Java cho: Bolt_ingest.flush(), drainQueue(), Bolt_cloudMerge.execute(), EWMA z-score anomaly detection.

**Phụ lục C — Cấu hình Docker Compose**
Tóm tắt các service và cổng trong docker-compose.yml cho cả 3 hệ thống.

**Phụ lục D — Prometheus Queries**
Các PromQL query dùng để đo metrics chính.

**Phụ lục E — Danh sách ảnh Grafana**
Bảng map tên file → metric → kịch bản đo, tổng hợp tất cả ảnh chụp màn hình.

---

## SỐ LIỆU QUAN TRỌNG CẦN NHÚNG ĐẦY ĐỦ VÀO VĂN BẢN

### Monolithic (stormsmarthome)
- KB1 ramp data: houses=[1,5,10,20,40], msg/s=[10,50,100,200,400], complete_latency_ms=[55,97,290,1111,5282], acked_600s=[2840,13973,30326,22422,6873]
- Bolt_split capacity tại h40: split-1=125%, split-5=135%, split-10=148%, split-20=159%, split-30=169%
- KB2 steady: complete_lat_mean=1.13s, complete_lat_max=5.09s, split_bolt_max=189%, spout_max=296 ops/s, db_rows=26965, e2e_p50=655s, e2e_p95=1258s
- Saturation: ~20 nhà (200 msg/s), ack ratio giảm từ 3.4% xuống 0.4%

### Fog KB1-A (8 GW, 7 Docker + 1 Pi 3)
- Cloud capacity: [0,0,91.2%,4.6%,0%] theo [h1,h5,h10,h20,h40]
- GW exec latency (ms): [0.032,0.073,0.068,0.067,0.044]
- RAM per GW (MB): [182,191,194,229,239]
- WAN KB/min: [15.0,40.2,88.9,159.4,332.8]
- Acked reduction: 65.8%, Traffic reduction: 52.5%
- h40 CPU busiest GW avg: 10.6%, peak sum: 96.2%

### Fog KB1-B (1 GW, 1 Pi 3)
- Cloud capacity: [35.3%,21.2%,~0%,~0%,318.9%]
- Cloud execute latency at h40: 47,800ms
- WAN KB/min: [14.0,41.8,88.8,164.5,396.1]
- Acked reduction: 95%, Traffic reduction: 92.5%
- RAM: 288 MB, CPU: 11.2%
- e2e p50: 408,626ms (artifact)

### Fog KB2-A (8 GW)
- Outage: 17:25:00–17:30:05 (300s)
- Max Queue: 200 batch = 8×5×5 (exact match theory)
- Recovery: 96s, Drain rate: 2.08 batch/s
- Data Loss: 0%, Tuples: 182,223

### Fog KB2-B (1 GW, Pi 3)
- Outage: 18:09:38–18:14:43 (300s)
- Max Queue: 25 batch = 1×5×5 (exact match theory)
- Recovery: 71s, Drain rate: 0.352 batch/s
- Data Loss: 0%, Tuples: 175,879

---

## YÊU CẦU ĐẶC BIỆT VỀ BIỂU ĐỒ

Tạo ÍT NHẤT 12 biểu đồ pgfplots sau (mô tả chính xác):

1. **grouped bar**: Cloud Bolt Capacity tại h40 — 3 nhóm (MONO/FOG-8GW/FOG-1GW), Y=%, màu đỏ/xanh/cam
2. **line**: Complete Latency vs houses — 3 đường, Y log scale ms
3. **bar**: WAN KB/min so sánh tại h40 — horizontal bar 3 hệ thống
4. **line**: Gateway Execute Latency EMA (ms) — FOG-KB1-A, 5 điểm h1 đến h40, phẳng <0.1ms
5. **bar**: RAM per GW (MB) theo số nhà — FOG-KB1-A, staircase 182→239
6. **grouped bar**: Acked Reduction % — FOG-8GW vs FOG-1GW (65.8% vs 95%)
7. **bar**: Store-Forward Queue Max — KB2-A (200) vs KB2-B (25), so sánh + lý thuyết vs thực đo
8. **bar**: Recovery Time (s) — KB2-A (96) vs KB2-B (71)
8b. **grouped bar — Energy Optimizer**: CPU per GW trong 3 trạng thái: Running+traffic (~13%), Running idle (~3%), Paused (0%). Annotation: "cgroups freezer, wake <50ms". Chỉ áp dụng FOG-8GW.
9. **line**: Monolithic Complete Latency vs houses — log scale, mark điểm saturation
10. **grouped bar**: Cloud Capacity tại mỗi nấc — MONO vs FOG-1GW (cả hai bị overload ở h40, cùng vấn đề)
11. **bar**: GW CPU total — FOG-8GW (~90% sum) vs FOG-1GW (11%) — hiển thị trade-off
12. **stacked bar**: Tổng tài nguyên phần cứng — Cloud RAM + Edge RAM + Số thiết bị
13. **bar chart — Energy Optimizer**: So sánh CPU per gateway trong 3 trạng thái: Running với traffic (10–17%), Running idle (~3%), Paused (0%). Highlight tiết kiệm khi 6/8 GW idle tại nấc h10 (chỉ 2 GW có nhà active). Title: "Energy Optimizer: CPU Gateway theo trạng thái hoạt động"

---

## YÊU CẦU VỀ SƠ ĐỒ TIKZ

Vẽ ÍT NHẤT 6 sơ đồ TikZ kiến trúc:

1. **Architecture comparison** — Monolithic vs Fog side-by-side (boxes và arrows)
2. **Fog Storm Topology** — Spout_mqtt → Bolt_ingest → MQTT GZIP → Cloud → Bolt_cloudMerge → MySQL
3. **Bolt_ingest flowchart** — parse → accumulate → check flush timer → [success path / fail → queue path]
4. **Store-and-Forward state machine** — states: ONLINE/OFFLINE, transitions: MQTT ok / MQTT fail / drainQueue
5. **Deployment diagram** — 3 tầng: Pi 3 edge (8-GW mode và 1-GW mode), WAN, EC2 cloud
6. **Timeline KB2 outage** — trục thời gian: warmup / outage (queue 0→200) / drain (200→0) / post-recovery

---

## LƯU Ý BẮT BUỘC

1. Dùng `\begin{figure}[H]` cho TẤT CẢ figure
2. Mọi table phải có `\caption` và `\label` đầy đủ
3. Mọi figure phải được nhắc đến trong văn bản bằng `\ref{}`
4. Các con số quan trọng phải được **in đậm** trong table
5. Đề tài PI 3: trong các kịch bản Fog, luôn nhắc đến "Raspberry Pi 3" như là thiết bị edge thực tế, không phải container giả lập. Câu viết mẫu: "Trong kịch bản FOG-KB1-A, hệ thống bao gồm 7 container Docker chạy trên máy chủ phát triển và **1 Raspberry Pi 3** chạy gateway gw-08, phụ trách 5 ngôi nhà cuối cùng (house-35 đến house-39)."
6. Viết nhất quán: "hệ thống Monolithic" (không viết tắt đầu bài), sau đó có thể viết "Mono"
7. Độ dài: đảm bảo mỗi chương đủ text, giải thích sâu, không chỉ bảng số liệu. Tổng 60–80 trang A4

=== KẾT THÚC PROMPT ===

---

## GHI CHÚ SỬ DỤNG

Sau khi sinh LaTeX, cần làm thêm:
1. Upload ảnh Grafana vào Overleaf theo đường dẫn: `images/fog/kb1a/`, `images/fog/kb2a/`, `images/mono/`
2. Các ảnh cần upload: tất cả file .png trong `results/kb1-A-multi8gw/img/`, `results/kb1-B-single/img/`, `results/kb2-A-multi8gw/img/`, `results/kb2-B-single/img/`, `stormsmarthome/results/s1-ramp/img/`, `stormsmarthome/results/s2-steady/`
3. Thêm thông tin GVHD và MSSV vào trang bìa
4. Biên dịch bằng `pdflatex` (hoặc XeLaTeX nếu cần font tiếng Việt đặc biệt)
5. Nếu báo lỗi font tiếng Việt: thêm `\usepackage[utf8]{vntex}` hoặc dùng XeLaTeX với font Times New Roman

## DANH SÁCH ẢNH GRAFANA CẦN UPLOAD LÊN OVERLEAF

### Monolithic
- `s1-ramp/img/s1_ramp_bolt_capacity.png`
- `s1-ramp/img/s1_ramp_bolt_exec_latency.png`
- `s1-ramp/img/s1_ramp_complete_latency.png`
- `s1-ramp/img/s1_ramp_spout_emitted_rate.png`
- `s1-ramp/img/s1_ramp_topology_throughput.png`
- `s2-steady/s2_steady_bolt_capacity.png`
- `s2-steady/s2_steady_bolt_exec_latency.png`
- `s2-steady/s2_steady_complete_latency.png`
- `s2-steady/s2_steady_spout_emitted_rate.png`
- `s2-steady/s2_steady_topology_throughput.png`

### Fog KB1-A (8 GW)
- `kb1-A-multi8gw/img/cloud_tuples_acked_600s.png`
- `kb1-A-multi8gw/img/cloud_bolt_capacity_600s.png`
- `kb1-A-multi8gw/img/cloud_bolt_execute_latency_ms.png`
- `kb1-A-multi8gw/img/gateway_tuple_ingestion_rate.png`
- `kb1-A-multi8gw/img/gateway_flush_mqtt_publish_rate.png`
- `kb1-A-multi8gw/img/all_gateways_bolt_capacity.png`
- `kb1-A-multi8gw/img/summary_stat_panels.png`
- `kb1-A-multi8gw/img/cloud_bolt_capacity_post_ramp_600pct.png`

### Fog KB1-B (1 GW)
- `kb1-B-single/img/cloud_bolt_capacity_600s.png`
- `kb1-B-single/img/cloud_bolt_execute_latency_ms.png`
- `kb1-B-single/img/gateway_tuple_ingestion_rate.png`
- `kb1-B-single/img/summary_stat_panels.png`

### Fog KB2-A (8 GW)
- `kb2-A-multi8gw/img/summary_stat_panels_outage_queue200.png`
- `kb2-A-multi8gw/img/summary_stat_panels_recovery_queue0.png`
- `kb2-A-multi8gw/img/store_forward_queue_depth.png`
- `kb2-A-multi8gw/img/cloud_bolt_capacity_600s.png`
- `kb2-A-multi8gw/img/gateway_flush_mqtt_publish_rate.png`

### Fog KB2-B (1 GW)
- `kb2-B-single/img/summary_stat_panels_outage_queue25.png`
- `kb2-B-single/img/summary_stat_panels_recovery_queue0.png`
- `kb2-B-single/img/store_forward_queue_depth.png`
