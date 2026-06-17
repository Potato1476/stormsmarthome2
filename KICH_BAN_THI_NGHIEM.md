# KỊCH BẢN THÍ NGHIỆM — Fog Smart Home

Kiến trúc Fog v2: gateway biên (Bolt_ingest + **Store-and-Forward queue**) +
1 Cloud EC2 (topology fog-cloud + MySQL + Storm exporter). Data bắn từ repo
**`~/iot-data-publisher`** (xem README bên đó, mục "Bắn data theo kịch bản").

Tài liệu gồm **2 phần**:

**PHẦN I — Hạ tầng đầy đủ (8 gateway giả lập trên laptop + Cloud EC2):** dùng
khi muốn số liệu "đẹp" nhất, tài nguyên dư dả.

| KB | Chứng minh | Chỉ số | Lệnh |
|---|---|---|---|
| 1 — Scalability ramp 1→40 nhà | Hệ mở rộng được | Complete Latency, Capacity, WAN | `ENV=A ./tools/sim_scalability.sh` |
| 2 — Cloud Offline 5' → Recovery | Store-and-Forward chạy thật | Max Queue Depth, Recovery Time, Data Loss % | `./tools/kb2_offline_recovery.sh` |

**PHẦN II — Giả lập thiết bị biên RAM nhỏ (trọng tâm):** mỗi gateway giới hạn
1GB/1vCPU (cỡ Raspberry Pi 3) bằng Docker — không cần Pi phần cứng. 2 cách
deploy (A: 8 gateway phân tán, B: 1 gateway ôm hết 40 nhà), mỗi cách chạy
KB1 + KB2 để trả lời *thiết bị biên RAM nhỏ có chạy ngon không*. **Một
lệnh/môi trường, tự động hết:**

| Lệnh | Làm gì |
|---|---|
| `ENV=A ./tools/run_sim_experiments.sh` | 8 gateway giả lập: scalability + cloud-off, đo CPU/RAM mỗi node |
| `ENV=B ./tools/run_sim_experiments.sh` | 1 gateway giả lập ôm 40 nhà: như trên |

**Quy ước chung:** SPEED=10 msg/s/nhà (40 nhà ≈ 400 msg/s); warmup 5'. Mọi số
liệu vào `results/`, ảnh vào `results/img/`. Đặt biến 1 lần cho cả phiên:
`export CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem`.

---

## Chuẩn bị chung (cả 2 phần đều cần Cloud EC2)

```bash
# 1. Build jar + image (nếu chưa)
cd ~/stormsmarthome2
(cd fog-gateway && mvn package -DskipTests) && docker build -t fog-gateway:latest ./fog-gateway
(cd fog-cloud && mvn package -DskipTests && cd tagawarescheduler && mvn package -DskipTests)

# 2. Cloud EC2 — ĐÃ BẬT, IP = 52.74.153.60
export CLOUD_IP=52.74.153.60
# (nếu dựng lại từ đầu: cd infrastructure/terraform && terraform apply
#  rồi CLOUD_IP=$(terraform output -raw cloud_public_ip))

# 3. Deploy tầng cloud lên EC2 (rsync + compose up + topo-submit — xem HUONG_DAN_CHAY.md §5)

# 4. Publisher
cd ~/iot-data-publisher && npm install
```

**Chỉ PHẦN I cần thêm** — stack 8 gateway (profile `multi`) + monitoring:
```bash
cd ~/stormsmarthome2
./infrastructure/scripts/set-cloud-ip.sh "$CLOUD_IP"   # điền IP vào .env.gateway + prometheus
docker compose -f docker-compose.gateway.yml --profile multi --env-file .env.gateway up -d
```
(**PHẦN II** dùng cùng compose này nhưng do `run_sim_experiments.sh` tự up/tắt
đúng profile — xem "Chuẩn bị" ở KB3&4. Một stack `docker-compose.gateway.yml`
duy nhất phục vụ cả 2 phần qua profile `multi`/`single`.)

Kiểm tra sẵn sàng: `http://localhost:3000` (admin/admin) → dashboard
*Fog vs Monolithic* — panel "Active Gateway Count" = 8, "Cloud Storm Exporter
Status" = 1.

> Mẹo: các lệnh dưới đều cần `CLOUD_IP` và `KEY` —
> `export CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem` một lần cho cả phiên.

---

## KỊCH BẢN 1 — Scalability kiểu RAMP (1→5→10→20→40 nhà, liên tục)

**Mục tiêu:** khi số nhà tăng 40×, chứng minh hệ vẫn ổn định: Complete Latency
không phình, Capacity còn xa ngưỡng 1.0, WAN tăng chậm hơn nhiều so với raw
traffic (vì gateway tổng hợp trước).

**MỘT phiên liên tục, KHÔNG restart giữa chừng:** bắt đầu 1 nhà, vài phút sau
**thêm** thành 5 nhà, rồi 10 → 20 → 40. Mỗi nấc giữ `STEP_DUR` giây (mặc định
5'), ~60s cuối nấc tự đo. Tổng ~25 phút (không phải 3 tiếng):

```bash
cd ~/stormsmarthome2
ENV=A ./tools/sim_scalability.sh          # 8 gateway (môi trường A)
# nhanh hơn để chạy thử:  STEP_DUR=120 ENV=A ./tools/sim_scalability.sh   (~10')
# đổi các mốc nhà:         HOUSES="1 5 10 20 40" ENV=A ./tools/sim_scalability.sh
```

> Mỗi nhà mới là 1 process publisher chạy ở thư mục riêng → **thêm** vào tải
> đang chạy, không reset các nhà cũ. Gateway giữ nguyên suốt phiên → biểu đồ
> Grafana là đường **bậc thang đi lên** theo tải.

**Kết quả tự động:**
- `results/sim_A-multi8gw_scalability.csv` — mỗi nấc 1 dòng (snapshot ~60s cuối nấc):

| houses | msg/s | complete_latency_ms | gw_capacity_max | gw_cpu_busiest_avg_pct | wan_kb_per_min |
|---|---|---|---|---|---|
| 1,5,10,20,40 | 10→400 | *(từ CSV)* | … | … | … |

- Ảnh: tự chụp panel *Gateway: Tuple Ingestion Rate* (bậc thang) → lưu `results/img/kb1-A-multi8gw/` (script in URL + nhắc khi xong).
- `results/sim_stats_sim-A-*-hNN.csv` — CPU/RAM container từng nấc.

**Cách đọc:** trục hoành = thời gian (tải tăng dần). Luận điểm:
(a) Complete Latency gần như phẳng khi tải tăng → cloud không phải nút thắt;
(b) Capacity tăng nhưng ở mức thấp → còn dư địa mở rộng;
(c) WAN KB/phút tăng theo số nhà nhưng nhỏ hơn nhiều lần raw (raw = N×10 msg/s
× ~50B; WAN đo được chỉ là batch tổng hợp đã gzip).

> Lưu ý: `complete_latency` cửa sổ 600s (10') của exporter **trễ ~vài phút** sau
> khi đổi nấc nếu nấc ngắn — xem đường Grafana để thấy xu hướng, hoặc đặt
> `STEP_DUR=600` nếu cần con số snapshot chính xác tuyệt đối từng nấc.

---

## KỊCH BẢN 2 — Cloud Offline 5 phút → Recovery (Store-and-Forward)

**Mục tiêu:** *"Store-and-Forward không chỉ tồn tại trong mã nguồn mà còn hoạt
động đúng khi có lỗi mạng"* — một mục Evaluation riêng.

```
Cloud Online → cloud-mqtt OFF (5') → Queue tăng → cloud-mqtt ON → Queue về 0
```

**Bước 1 — bắn data nền ổn định ≥45'** (terminal 1):
```bash
cd ~/iot-data-publisher
SPEED=10 DURATION=2700 ./send_all.sh
```

**Bước 2 — sau khi hệ chạy ổn ~5', chạy test** (terminal 2):
```bash
cd ~/stormsmarthome2
CLOUD_IP=$CLOUD_IP KEY=$KEY ./tools/kb2_offline_recovery.sh
# Tùy chọn: OUTAGE_SEC=300 (mặc định 5'), RECOVERY_TIMEOUT=900
```

Script tự: tắt `cloud-mqtt` qua SSH → theo dõi queue 5s/lần (in trực tiếp) →
bật lại → đo thời gian queue về 0 → tính 3 chỉ số → xuất ảnh → PASS/FAIL.

**Kết quả tự động:** `results/kb2_offline_<ts>.md` chứa đúng bảng cần đưa vào
báo cáo:

| Chỉ số | Ý nghĩa |
|---|---|
| Max Queue Depth | đỉnh số batch xếp hàng tại 8 gateway trong 5' offline |
| Recovery Time | giây từ lúc cloud online đến lúc queue = 0 |
| Data Loss % | (đã thử gửi − gửi thành công − còn trong queue)/đã thử — kỳ vọng **0%** |

kèm dòng "Tuples xử lý tại gateway trong phiên" — chứng minh gateway **không
dừng xử lý** khi mất cloud (tính liên tục tại biên).

Ảnh đắt giá nhất cho mục này: tự chụp panel *Gateway: Store-and-Forward Queue
Depth* — đường queue **tăng dần trong 5' rồi đổ dốc về 0** sau khi cloud online
(script in URL Grafana đã ghim đúng đoạn; lưu vào `results/img/kb2-<A|B>-*/`).

> Vì sao Data Loss kỳ vọng 0%: queue ghi file JSONL trên volume (sống qua cả
> restart container), gửi lại với QoS 1, còn phía cloud ghi DB bằng
> REPLACE-upsert → gửi trùng không sao (idempotent).

---

## KỊCH BẢN 3 & 4 — Giả lập thiết bị biên RAM nhỏ (2 môi trường × 2 kịch bản)

**Bối cảnh:** thay vì Pi phần cứng thật (Pi 3 cần màn hình HDMI rời để setup,
bất tiện), ta **giả lập thiết bị biên bằng Docker** — mỗi gateway bị giới hạn
**1GB RAM / 1 vCPU** đúng cỡ Raspberry Pi 3. Thử **2 cách deploy** để trả lời:
*thiết bị biên RAM nhỏ có chạy ngon không?*

| Môi trường | Chạy gì | Ý nghĩa |
|---|---|---|
| **A — multi-gateway** (profile `multi`) | 8 gateway giả lập, mỗi cái 1GB/1vCPU, mỗi cái 5 nhà | Fog **phân tán** — chia tải nhiều node biên |
| **B — single-gateway** (profile `single`) | 1 gateway giả lập 1GB/1vCPU xử lý CẢ 40 nhà | Single Fog-Assisted Cloud — 1 thiết bị nhỏ ôm hết |

Mỗi môi trường chạy **2 kịch bản**: KB1 tăng dần số nhà (1,3,5,10,20,40) và
KB2 cloud off 5'. So A↔B: 1 thiết bị 1GB ôm 40 nhà có nghẽn không (B), và phân
tán 8 node có gỡ nghẽn không (A) — chính là luận điểm "cần phân tán tầng Fog".

> Tất cả chạy trên laptop bằng Docker; Cloud vẫn là EC2. Mỗi môi trường **một
> lệnh tự động hết** (up đúng profile, quét nấc nhà, tắt/bật cloud-mqtt, đo
> CPU/RAM container + Complete Latency/Capacity/WAN, xuất ảnh). Bạn chỉ vào
> `results/` lấy số.

### Chuẩn bị (một lần)

```bash
cd ~/stormsmarthome2
docker build -t fog-gateway:latest ./fog-gateway          # image x86 cho laptop
export CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem         # (Cloud EC2 vẫn cần cho WAN + KB2)
./infrastructure/scripts/set-cloud-ip.sh 52.74.153.60    # điền IP cloud vào .env.gateway + prometheus (đã sẵn)
```

> **Ép RAM nhỏ hơn để tìm điểm nghẽn:** mặc định heap mỗi gateway `-Xmx384m`
> trong giới hạn 1GB. Muốn thử "thiết bị càng yếu", hạ heap:
> `export JAVA_OPTS='-Xmx256m -XX:+UseSerialGC -Djava.awt.headless=true'`.
> Nếu B (1 gateway) OOM ở 40 nhà → **đó là kết quả**: 1 thiết bị nhỏ không ôm
> nổi, cần phân tán (A). Cột `oom_killed` trong CSV ghi lại.

### Chạy trọn môi trường A rồi B

```bash
cd ~/stormsmarthome2

# Môi trường A — 8 gateway giả lập (KB1 + KB2)
ENV=A ./tools/run_sim_experiments.sh

# Môi trường B — 1 gateway giả lập (KB1 + KB2)
ENV=B ./tools/run_sim_experiments.sh
```

Chạy thử nhanh trước khi đo thật:
```bash
ENV=B HOUSES="1 10 40" STEP_DUR=120 OUTAGE_SEC=120 ./tools/run_sim_experiments.sh
```
Chạy riêng từng kịch bản: thêm `PHASES="kb1"` hoặc `PHASES="kb2"`.

### Kết quả & cách đọc

**KB1 (scalability):** `results/sim_A-multi8gw_scalability.csv` và
`results/sim_B-single_scalability.csv` — mỗi nấc nhà 1 dòng:

| houses | complete_latency_ms | gw_capacity_max | **gw_cpu_busiest_avg_pct** | **gw_ram_busiest_avg_mb** | wan_kb_per_min | oom_killed |
|---|---|---|---|---|---|---|
| 1,3,5,10,20,40 | … | … | … | … | … | 0 = không OOM |

→ Bảng "Households × CPU/RAM thiết bị biên" nằm sẵn ở 2 cột in đậm
(CPU% ≈100% = 1 vCPU của thiết bị bão hoà). Luận điểm:
- **B** (1 thiết bị): CPU/RAM tăng nhanh theo số nhà; nếu ở 40 nhà chạm trần
  hoặc OOM → "1 thiết bị nhỏ ôm hết thì nghẽn".
- **A** (8 thiết bị): mỗi node chỉ 5 nhà → CPU/RAM phẳng và thấp kể cả ở 40 nhà
  → "phân tán tầng Fog gỡ được nghẽn, thiết bị rẻ vẫn chạy ngon".
- So Complete Latency A↔B cùng số nhà: ở tải cao A thấp hơn B → giá trị của
  phân tán; đổi lại A tốn tổng RAM nhiều hơn (cột RAM tổng trong `sim_stats_*`).

**KB2 (cloud off 5'):** `results/kb2_A-multi8gw_*.md` và `results/kb2_B-single_*.md`
— mỗi file có bảng **Max Queue Depth / Recovery Time / Data Loss %** + PASS/FAIL,
chứng minh Store-and-Forward chạy đúng ở cả 2 cấu hình.

**Ảnh:** tự chụp (script nhắc URL + panel khi xong) → lưu `results/img/kb1-A-multi8gw/`,
`results/img/kb1-B-single/`, `results/img/kb2-*/`. CPU/RAM container từng nấc:
`results/sim_stats_sim-*-hNN.csv`.

---

## Lấy hình từ Grafana cho báo cáo (TỰ CHỤP — không render tự động)

Render PNG tự động của Grafana cho ảnh xấu → ta **tự chụp màn hình**. Khi script
đo chạy xong, nó in sẵn **URL Grafana đã ghim đúng khoảng thời gian phiên** +
tên panel nên chụp + thư mục lưu. Việc cần làm:

1. Mở URL script đưa (dạng `http://localhost:3000/d/fog-vs-mono-001/fog?from=…&to=…`),
   login `admin/admin` — dashboard đã ở đúng đoạn thời gian, không cần chỉnh.
2. Với panel cần chụp: Panel menu → **View** (phóng to) → chụp màn hình (Cmd+Shift+4).
3. Lưu vào đúng thư mục kịch bản (script tự tạo sẵn):
   - KB1-A → `results/img/kb1-A-multi8gw/`  · KB1-B → `results/img/kb1-B-single/`
   - KB2-A → `results/img/kb2-A-multi8gw/`  · KB2-B → `results/img/kb2-B-single/`

Panel nên chụp: KB1 → *Gateway: Tuple Ingestion Rate* (bậc thang), *All Gateways:
Bolt Capacity*, *Cloud Bolt: Capacity*. KB2 → *Gateway: Store-and-Forward Queue
Depth* (đường tăng rồi về 0).

> **Số liệu thực (số chuẩn) nằm ở CSV/MD** — ảnh chỉ minh hoạ. Nếu lười chụp,
> chỉ cần CSV/MD là đủ cho phần số của báo cáo.

## Dữ liệu nằm ở đâu

| Loại | Vị trí | Sinh bởi |
|---|---|---|
| **Bảng KB1 ramp (A/B)** | `results/sim_A-multi8gw_scalability.csv`, `results/sim_B-single_scalability.csv` | `sim_scalability.sh` |
| Snapshot metric thủ công | `results/<label>_<ts>.csv` | `collect_metrics.sh` |
| CPU/RAM/NET container (snapshot) | `results/system_<label>_<ts>.csv` | `collect_system.sh` |
| Báo cáo KB2 (3 chỉ số + PASS/FAIL) | `results/kb2_offline_<ts>.md` | `kb2_offline_recovery.sh` |
| **Báo cáo KB2 giả lập (A/B)** | `results/kb2_A-multi8gw_*.md`, `results/kb2_B-single_*.md` | `run_sim_experiments.sh` |
| CPU/RAM container từng nấc | `results/sim_stats_sim-<A\|B>-hNN.csv` | `collect_sim_stats.sh` |
| Ảnh bạn tự chụp | `results/img/kb<1\|2>-<A\|B>-*/` (thư mục theo kịch bản) | chụp tay từ Grafana |
| Log publisher (tốc độ thực tế từng nhà) | `~/iot-data-publisher/logs/*.log` | `send_all.sh` |
| Dữ liệu nghiệp vụ (bảng fog_*) | MySQL trên EC2 — `ssh … docker exec cloud-mysql mysql -uuser1 -pUet123 iotdata_fog` | topology |
| Metric thô (truy vấn lại bất kỳ lúc nào) | Prometheus `http://localhost:9090` (volume `fog_prom_data` — KHÔNG mất khi restart) | Prometheus |

**Ghép báo cáo cuối:** mỗi kịch bản = 1 mục Evaluation: bảng số từ CSV/MD ở
trên + 1–2 ảnh từ `results/img/` + đoạn "cách đọc" tương ứng trong file này.
So sánh nền với Monolithic lấy từ `./tools/compare_results.py`
(xem `KICH_BAN_DO_LUONG.md`).
