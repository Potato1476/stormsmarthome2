# ĐO ĐẠC — HỆ FOG (quy trình "chắc chắn", chỉ việc copy-paste)

> **Đây là bản đo lại nghiêm ngặt** (thay bản cũ) — xem lý do từng bước trong
> [docs/REMEASURE_PLAN.md](docs/REMEASURE_PLAN.md).
> Cloud fog (EC2): **CLOUD IP `52.74.153.60`** · key `~/.ssh/storm.pem` (đổi nếu khác).
> Gateway + Prometheus + Grafana chạy LOCAL: Grafana http://localhost:3000, Prom :9090.
> Bắn data từ `~/iot-data-publisher`. Kết quả lưu `results/remeasure/`.
>
> ⚖️ **NGUYÊN TẮC CÔNG BẰNG (bắt buộc, khớp với hệ Mono):**
> - **Cùng tập cửa sổ** hai hệ: `1,5,10,15,30,60,120` (Fog: gateway tạo 1,5,10,15,30; cloud suy ra 60,120).
> - **Cùng có forecast**: `FORECAST_ENABLED=true` (đã thêm vào cloud — parity với Bolt\_forecast của Mono).
> - **Cùng loại EC2 cloud** với Mono (vd cùng t3.large hoặc cùng t3.small) — thống nhất trước khi đo.
> - **Đo n=5 lần** mỗi kịch bản, lấy mean±std. **Không** loại lần "xấu".
> - Dùng **một bộ đo dùng chung** `tools/measure_ramp.sh` (giống hệt Mono) → cùng hàm tổng hợp p50/p95/max, đo WAN cả hai phía.

> 📸 **CHÍNH SÁCH ẢNH (trả lời "đo 5 lần thì chụp mấy lần, để đâu"):**
> - **Số liệu = cả 5 lần** (mean±std, tự động từ CSV) — đây mới là số chuẩn cho báo cáo.
> - **Ảnh Grafana = chỉ 1 lần / kịch bản**, chụp ở **run đại diện** (run có số gần
>   *median* nhất — xem bảng mean; đơn giản nhất chọn **RUN_ID=3**). Ảnh chỉ để minh hoạ.
> - **Nơi lưu ảnh**: `results/remeasure/<kb>/img/` (vd `results/remeasure/kb1a/img/`).
> - Vậy tổng số "bộ ảnh" = số kịch bản: **Fog có 4 bộ** (kb1a, kb1b, kb2a, kb2b).
>   Panel cần chụp mỗi kịch bản: xem `results/remeasure/README.md`.

---

## 0a. (MỘT LẦN) DỌN SẠCH dữ liệu/ảnh đo cũ → tạo thư mục mới
```bash
cd ~/stormsmarthome2
./tools/clean_measurements.sh          # archive an toàn (xem lệnh xoá archive ở cuối output)
# (PURGE=1 ./tools/clean_measurements.sh  nếu muốn xoá hẳn, không giữ archive)
```
Sau bước này: `results/remeasure/{kb1a,kb1b,kb2a,kb2b,anomaly}/img` đã sẵn sàng; thư mục
ảnh báo cáo `images/{mono,fog/*}` được làm trống để re-stage ảnh mới sau khi đo.

## 0. (MỘT LẦN) Rebuild — đã có 3 thay đổi code quan trọng
> ⚠️ Bắt buộc rebuild vì đã sửa: (a) **JDBC batch-transaction** (sửa nghẽn ghi DB ⇒ 318,9%),
> (b) **forecast ở cloud** (parity), (c) gateway giữ nguyên.
```bash
cd ~/stormsmarthome2
(cd fog-gateway && mvn -q -DskipTests package)
(cd fog-cloud && mvn -q -DskipTests package && cd tagawarescheduler && mvn -q -DskipTests package)
docker build -t fog-gateway:latest ./fog-gateway

# redeploy CLOUD topology (jar mới có batch-transaction + forecast)
CLOUD_IP=52.74.153.60; K=~/.ssh/storm.pem
rsync -avz --exclude='.git' --exclude='**/target/classes' --exclude='node_modules' -e "ssh -i $K" ./ ec2-user@$CLOUD_IP:/home/ec2-user/stormsmarthome2/
ssh -i $K ec2-user@$CLOUD_IP 'cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d --build'
ssh -i $K ec2-user@$CLOUD_IP 'docker exec cloud-nimbus storm kill fog-cloud -w 5 || true'; sleep 30
ssh -i $K ec2-user@$CLOUD_IP 'cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d cloud-topo-submit'
```
Kiểm tra forecast bật: `ssh -i $K ec2-user@$CLOUD_IP "docker logs cloud-topo-submit 2>&1 | grep -i forecast"`.

## 0c. (MỖI PHIÊN) PREFLIGHT — kiểm chứng môi trường trước khi đo
> Một lệnh xác nhận: jar mới, compose hợp lệ, publisher đủ data, Prometheus có
> `bolts_capacity`, và **banner workload parity** từ cloud (windows + forecast + cloudMergeMode).
```bash
CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem PROM=http://localhost:9090 ./tools/preflight.sh
# parity in ra dòng:  [WORKLOAD] windows=[1,5,10,15,30,60,120] forecast=true cloudMergeMode=batched flush=60s
```
Sau khi data chạy được ~2 phút, kiểm chứng **tính đúng cửa sổ + idempotency** (1 lần là đủ):
```bash
CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/verify_windows.sh
# kỳ vọng mỗi cửa sổ count=60 avg=100, và "dòng trùng PK = 0"  → PASS
```
Sinh artifact minh bạch (chống "strawman" + tái lập), lưu 1 lần/phiên:
```bash
STORM_UI=http://$CLOUD_IP:8080 TOPO=fog-cloud OUT=results/remeasure/parallelism_fog_cloud.csv ./tools/gen_parallelism.sh
SEED=42 ./tools/gen_manifest.sh          # → results/remeasure/run_manifest.md (điền seed/instance EC2)
# điền results/remeasure/hardware_matrix.csv (instance EC2 thật — KHÔNG ép cân bằng)
```

---

## Tham số CHUNG cho mọi lệnh đo (đặt 1 lần mỗi terminal)
```bash
cd ~/stormsmarthome2
export CLOUD_IP=52.74.153.60
export WAN_SSH=ec2-user@$CLOUD_IP WAN_KEY=~/.ssh/storm.pem WAN_CONTAINER=cloud-mqtt
export PROM=http://localhost:9090
export HOUSES="1 5 10 20 40" STEP_DUR=360 SKIP=90 SAMPLE=2
export OUT_DIR=results/remeasure
```

---

## KB1-A — Scalability 8 GATEWAY  (chạy 5 lần)
Bật stack 8 gateway: `./demo.sh` → bấm `b` → `0` thoát. Lặp `RUN_ID` từ 1→5:

**Terminal A (đo):**
```bash
MODE=fog RUN_ID=1 OUT_DIR=results/remeasure/kb1a ./tools/measure_ramp.sh
```
**Terminal B (bắn data — khi A báo "BẮN DATA NGAY"):**
```bash
cd ~/iot-data-publisher && STEP_DUR=360 ./ramp.sh
```
Giữa các lần: `./tools/reset_fog.sh`. Sau 5 lần gộp mean±std:
```bash
python3 tools/agg_runs.py mean results/remeasure/kb1a fog
```

## KB1-B — Scalability 1 GATEWAY (Pi)  (chạy 5 lần)
Bật 1 gateway: `./demo.sh` → `c`. Lặp như trên với `OUT_DIR=results/remeasure/kb1b`.
> Sau fix JDBC, kỳ vọng cloud capacity 1-GW tại h40 **rớt từ 318,9% xuống <100%**.
> Tìm trần biên thật (tuỳ chọn): thêm nấc `HOUSES="40 80 120"`.

## KB2-A / KB2-B — Offline Recovery  (3 lần + 1 outage dài)
```bash
# 8 GW (profile multi đang bật)
for r in 1 2 3; do
  CLOUD_IP=$CLOUD_IP KEY=~/.ssh/storm.pem OUTAGE_SEC=300 \
  OUT_DIR=results/remeasure/kb2a_run$r ./tools/kb2_offline_recovery.sh
done
# 1 lần outage DÀI để minh hoạ giới hạn đĩa (C14):
CLOUD_IP=$CLOUD_IP KEY=~/.ssh/storm.pem OUTAGE_SEC=1800 \
OUT_DIR=results/remeasure/kb2a_long ./tools/kb2_offline_recovery.sh
```
Lặp tương tự cho 1 GW (`./demo.sh` → `c`) vào `kb2b_run*`.

## Đánh giá ANOMALY (định lượng — C12)
```bash
# Terminal A: thu cảnh báo có timestamp
docker compose -f docker-compose.gateway.yml --profile multi logs -f --timestamps \
  | grep --line-buffered ' ALERT ' > results/remeasure/alerts.log &
# Terminal B: phát luồng có nhãn (baseline + spike)
BROKER=mqtt://localhost:1883 DURATION=600 N_SPIKES=20 HOUSES=0,1,2 \
GT_FILE=results/remeasure/anomaly_gt.json node tools/anomaly_eval.js
# Xong: dừng tail (kill %1) rồi chấm điểm
python3 tools/anomaly_score.py results/remeasure/anomaly_gt.json results/remeasure/alerts.log 90
```
→ precision / recall / F1 / FPR / độ trễ phát hiện.

## Độ trễ — ĐO TÁCH BẠCH 3 LOẠI (B6, prompt §2.2)
Ba đại lượng KHÁC bản chất — **không bao giờ trộn** trong một bảng:
1. **`storm_complete_latency`** (so sánh HỢP LỆ) — đã nằm trong cột `lat_*` của summary (acker-based).
2. **`e2e_first_write`** (so sánh HỢP LỆ) — `firstWrittenAt − event_ts`, lần ghi DB ĐẦU:
   ```bash
   MODE=fog LAT_KIND=first SSH_TARGET=ec2-user@$CLOUD_IP KEY=~/.ssh/storm.pem ./tools/latency_report.sh
   ```
3. **`e2e_last_write`** (ARTIFACT — chỉ minh hoạ, do ngữ nghĩa cumulative, KHÔNG so sánh hiệu năng):
   ```bash
   MODE=fog LAT_KIND=last  SSH_TARGET=ec2-user@$CLOUD_IP KEY=~/.ssh/storm.pem ./tools/latency_report.sh
   ```
> Đây là chỗ khử "complete latency 84 s" cũ: 84 s thực ra là `e2e_last_write`. Sau tách,
> `storm_complete_latency` và `e2e_first_write` đều nhỏ (vài giây) và nhất quán với capacity.

## Kiểm soát: per-row vs batched (xử lý con số 318,9% — prompt §6.3)
Đo KB1-B **hai biến thể** `Bolt_cloudMerge`, báo cáo CẢ HAI:
```bash
# (mặc định) batched — đã chạy ở KB1-B ở trên (CLOUDMERGE_MODE=batched)
# per-row (tái hiện đường ghi cũ): kill topology cũ → submit lại với CLOUDMERGE_MODE=perrow
ssh -i $K ec2-user@$CLOUD_IP "docker exec cloud-nimbus storm kill fog-cloud -w 5 || true"; sleep 30
ssh -i $K ec2-user@$CLOUD_IP "cd stormsmarthome2 && CLOUDMERGE_MODE=perrow \
  docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d cloud-topo-submit --force-recreate"
# xác nhận: docker logs cloud-topo-submit | grep WORKLOAD  → cloudMergeMode=perrow
# đo lại như KB1-B vào thư mục riêng:
MODE=fog RUN_ID=1 OUT_DIR=results/remeasure/kb1b_perrow ./tools/measure_ramp.sh
# XONG: trả lại batched (mặc định) cho mọi kịch bản khác
ssh -i $K ec2-user@$CLOUD_IP "docker exec cloud-nimbus storm kill fog-cloud -w 5 || true"; sleep 30
ssh -i $K ec2-user@$CLOUD_IP "cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d cloud-topo-submit --force-recreate"
```
→ Kết luận trung thực: "318,9% là do vòng ghi từng dòng; sau batch transaction còn «X»%."

---

## CHỐT SỐ CHO BÁO CÁO
Số chuẩn = các file `summary_fog_run*.csv` đã gộp **mean±std** bằng `agg_runs.py mean`.
WAN lấy cột `wan_kb_per_min` (đo thật). Ảnh Grafana chỉ minh hoạ. So sánh với Mono
dùng **cùng** `measure_ramp.sh` (xem `DO_DAC.md` repo mono).
