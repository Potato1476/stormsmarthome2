# Kịch bản Test & Đo — So sánh Monolithic (cũ) vs Fog (mới)

Mục tiêu: đo hệ **Fog** (mới) rồi so với hệ **Monolithic** (cũ — bắn cả 40 nhà raw thẳng
lên Cloud) theo cách **có giá trị so sánh khoa học** (apples-to-apples).

---

## 0. Nguyên tắc so sánh công bằng (đọc trước)

Một phép so sánh chỉ có giá trị khi **chỉ thay đổi đúng 1 biến** (kiến trúc), còn mọi
thứ khác giữ **y hệt**. Đây là thí nghiệm có đối chứng:

| Loại biến | Thành phần | Quy định |
|-----------|-----------|----------|
| **Biến độc lập** (thứ ta đổi) | Kiến trúc | Monolithic ↔ Fog |
| **Biến kiểm soát** (giữ cố định) | Dataset | **Cùng bộ data** báo cáo đã dùng (bạn đã có) |
| | Tốc độ phát (rate) | ~400 msg/giây (như báo cáo) |
| | Tổng thời lượng | 30 phút + 5 phút warm-up (như báo cáo) |
| | Công cụ đo | Cùng `mr4x2/stormexporter` + Prometheus, scrape 5s |
| | Cửa sổ đo | Cùng `window` (all-time / 600) như báo cáo |
| | Phần cứng Cloud | Khác cấu hình cũng OK với throughput; latency/capacity chỉ xem định tính |
| **Biến phụ thuộc** (thứ ta đo) | 5 metric Storm ở **tầng Cloud** | acked / emitted / transferred / process_latency / capacity |

> **Điểm mấu chốt:** *đầu vào của HỆ THỐNG* phải giống hệt = **luồng raw 40 nhà**.
> Cái khác nhau (đúng theo thiết kế) là raw đó đi **thẳng lên Cloud** (Monolithic)
> hay **qua Gateway gom lại rồi mới lên Cloud** (Fog). Ta đo *tải đến được Cloud Storm*
> trong cả hai trường hợp → đó chính là giá trị so sánh.

> **KHÔNG đo lại hệ cũ.** Hệ Monolithic đã được đo và viết thành báo cáo rồi → ta dùng
> thẳng số liệu trong báo cáo làm cột đối chứng. Để phép so sánh **vẫn hợp lệ**, chỉ cần
> **1 điều kiện**: chạy hệ Fog với **đúng bộ dữ liệu mà báo cáo đã dùng** (bạn đã có sẵn),
> phát ở mức tương đương. Cùng data → cùng "đầu vào hệ thống" → so sánh đứng vững.

---

## 1. Workload (dùng chính bộ data + publisher của báo cáo)

Dùng **đúng bộ dữ liệu + publisher bạn đã có** ở `~/iot-data-publisher` (cũng là bộ mà báo
cáo Monolithic đã chạy). Data 40 nhà `house-0.csv .. house-39.csv`, định dạng REFIT 7 cột:

```
idx,timestamp,value,property,plugId,householdId,houseId   # property∈{0,1}, houseId 0..39
```

- Gateway lọc `property==1` và chia theo `houseId`: gw-01→nhà 0-4, gw-02→5-9, …, gw-08→35-39.
- Phát ở mức **tương đương báo cáo**: ~**400 msg/giây tổng** (báo cáo: "~400 raw tuple/s"),
  trong **30 phút**. `send_all.sh` đã chỉnh: `SPEED` là msg/s **mỗi nhà** → 40 nhà × 10 = 400/s.

```bash
cd ~/iot-data-publisher
npm install                              # chỉ lần đầu
SPEED=10 DURATION=1800 ./send_all.sh     # 40 nhà × 10 = ~400 msg/s, tự dừng sau 30 phút
```

> Publisher bắn vào **localhost:1883 = local-mqtt** của hệ Fog (KHÔNG phải Cloud IP). Đây là
> điểm khác cốt lõi: raw ở lại biên, chỉ kết quả tổng hợp mới lên Cloud.
> `send_all.sh` tự xoá `.publish.stat` mỗi lần chạy để bắt đầu từ đầu data (tái lập được).

---

## 2. 5 metric đo (đúng tên trong báo cáo)

Đo trên **tầng Cloud Storm** của hệ Fog (số Monolithic đã có sẵn trong báo cáo, cùng exporter):

| # | Metric (tên Prometheus) | Ý nghĩa | window dùng |
|---|--------------------------|---------|-------------|
| 1 | `topology_stats_acked` | Số root tuple Cloud hoàn tất | `all-time` (tổng), `600` (rate) |
| 2 | `topology_stats_emitted` | Tổng tuple phát ra (fan-out) | `all-time`, `600` |
| 3 | `topology_stats_transferred` | Tổng tuple truyền giữa task | `all-time`, `600` |
| 4 | `bolts_process_latency` | Độ trễ xử lý Bolt (ms) | `600` (lấy `max`) |
| 5 | `bolts_capacity` | Mức chiếm dụng Executor (nghẽn nếu >1) | `600` (lấy `max`) |

> **Throughput (1–3) là so sánh mạnh nhất** vì là *đếm số tuple*, không phụ thuộc phần
> cứng → kết luận vững dù máy khác nhau. **Latency/capacity (4–5) phụ thuộc phần cứng**
> → muốn so chặt thì chạy Cloud cùng loại EC2 cho cả hai.

PromQL (chạy ở Prometheus tương ứng mỗi hệ):

```promql
sum(topology_stats_acked{window="all-time"})
sum(topology_stats_emitted{window="all-time"})
sum(topology_stats_transferred{window="all-time"})
max(bolts_process_latency{window="600"})
max(bolts_capacity{window="600"})
```

> Kiểm tra tên metric thực tế của exporter trước khi đo:
> `curl http://52.74.153.60:8000/metrics | grep -E "topology_stats|bolts_"`
> (nếu exporter của bạn có tiền tố khác thì chỉnh lại cho khớp ở `tools/collect_metrics.sh`).

---

## 3. Quy trình đo HỆ FOG (mới) — step by step

```bash
# 3.1 Cloud (AWS) đang chạy + topology fog-cloud đã nộp (xem HUONG_DAN_CHAY.md mục 5).
#     Gateway (giả lập Pi) + Prometheus + Grafana đang chạy ở local.

# 3.2 (tuỳ chọn) reset mốc all-time về 0: nộp lại topology fog-cloud
#   ssh ... 'docker exec cloud-nimbus storm kill fog-cloud -w 5' && bật lại cloud-topo-submit

# 3.3 BẮN DATA + tự dừng sau 30 phút (đã gồm cả warm-up):
cd ~/iot-data-publisher
SPEED=10 DURATION=1800 ./send_all.sh

# 3.4 WARM-UP: bỏ 5 phút đầu — chốt baseline tại T+5 để trừ về sau:
#   (chạy ở repo stormsmarthome2)
./tools/collect_metrics.sh fog_t5     # tại T+5 phút

# 3.5 Tại T+30 (lúc publisher tự dừng), CHỐT số cuối:
./tools/collect_metrics.sh fog_t30
#   → results/fog_t30_<timestamp>.csv  (giá trị đo = throughput(t30) − throughput(t5))
```

Kiểm tra phụ trong lúc đo (kể câu chuyện "công việc dời về biên"):
```bash
# Tầng Gateway gánh phần nặng — tổng hợp cục bộ:
curl -s http://localhost:9091/metrics | grep -E "tuples_processed|mqtt_published"
# Storm UI Cloud cho thấy topology nhẹ tênh:
open http://52.74.153.60:8080
```

---

## 4. Số đối chứng Monolithic — lấy từ báo cáo (KHÔNG đo lại)

Hệ cũ đã đo và viết báo cáo, nên dùng thẳng số headline của báo cáo làm cột đối chứng:

| Metric (tầng Cloud) | Monolithic (theo báo cáo, window `all-time`) |
|---------------------|---------------------------------------------|
| acked | ~11.000 |
| emitted | ~6.500.000 |
| transferred | ~11.000.000 |
| max process_latency | < 1 ms (spike 1.6 ms khi dồn tải) |
| max bolt_capacity | **14.5** (Bolt avg-1 — nghẽn nặng) |

> Điều kiện để dùng số này hợp lệ: hệ Fog chạy ở mục 3 phải dùng **cùng bộ data** mà báo
> cáo đã đo (bạn đã có). Với cùng luồng raw 40 nhà, chênh lệch số Cloud chính là *hiệu quả
> của kiến trúc* — thứ cần chứng minh.

---

## 5. Bảng kết quả & cách tính

Cột Monolithic điền sẵn từ báo cáo (mục 4); cột Fog điền từ `results/fog_*.csv` (mục 3):

| Metric (tầng Cloud) | Monolithic (báo cáo) | Fog (đo được) | % giảm |
|---------------------|----------------------|---------------|--------|
| acked (all-time) | ~11.000 | | |
| emitted (all-time) | ~6.500.000 | | |
| transferred (all-time) | ~11.000.000 | | |
| max process_latency (ms, w=600) | <1 (spike 1.6) | | |
| max bolt_capacity (w=600) | 14.5 | | |

Công thức:
```
% giảm = (Monolithic − Fog) / Monolithic × 100
```

Bổ sung cho Fog (không có ở Monolithic) — chứng minh tải dời về biên chứ không biến mất:
| Metric tầng Gateway | Giá trị |
|---------------------|---------|
| tổng tuples_processed (8 gw) | |
| tổng mqtt_published lên Cloud | |
| store_queue_size (kỳ vọng ≈ 0) | |

**Kỳ vọng (theo báo cáo):** acked giảm 90–95%, emitted giảm 95–98%, transferred giảm
>95%, process_latency về <0.1ms phẳng, capacity từ ~14.5 xuống <0.05 (hết nghẽn).

---

## 6. Đảm bảo tính hợp lệ (validity checklist)

- [ ] **Cùng bộ data**: hệ Fog phải chạy đúng dataset mà báo cáo Monolithic đã đo.
- [ ] **Rate & thời lượng tương đương báo cáo**: ~400 msg/s, 30 phút.
- [ ] **Warm-up 5 phút** trước khi tính, để loại nhiễu khởi động JVM/JIT.
- [ ] **Chốt số cùng `window`** với báo cáo (all-time cho throughput, 600 cho latency/capacity).
- [ ] **Cùng exporter** (mr4x2/stormexporter) — đảm bảo tên metric trùng báo cáo.
- [ ] **Lặp ≥ 3 lần** phía Fog, báo cáo trung bình ± độ lệch chuẩn (tránh kết luận từ 1 lần chạy).
- [ ] **Reset giữa các lần** (kill + nộp lại topology fog-cloud, hoặc trừ baseline all-time).
- [ ] **Ghi lại** rate, kích thước data, giờ chạy để tái lập.

> **Mạnh nhất là 3 metric throughput** (acked/emitted/transferred): chúng *đếm tuple*,
> không phụ thuộc CPU → so sánh vững kể cả khi Cloud cũ (trong báo cáo) và Cloud Fog khác
> cấu hình phần cứng. Còn latency/capacity phụ thuộc phần cứng nên chỉ nên xem là **chỉ báo
> định tính** (vd: capacity từ 14.5 → ~0 cho thấy hết nghẽn), đừng diễn giải %giảm tuyệt đối.
