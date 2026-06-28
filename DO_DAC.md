# ĐO ĐẠC — HỆ FOG (chỉ việc copy-paste + chụp màn hình)

> Cloud fog (EC2) đang chạy. **CLOUD IP: `52.74.153.60`** · key fog: `~/.ssh/storm.pem` (đổi nếu khác)
> Gateway + Prometheus + Grafana chạy LOCAL: Grafana http://localhost:3000 (admin/admin), Prometheus :9090
> Bắn data từ `~/iot-data-publisher`. Log/CSV tự lưu theo kịch bản: `results/{kb1-A-multi8gw,kb1-B-single,kb2-A-multi8gw,kb2-B-single}/`. Ảnh bạn paste vào `results/<kịch-bản>/img/` (đã tạo sẵn).
> Menu nhanh: `./demo.sh` (b = 8 gateway, c = 1 gateway, …).
>
> ⏱ **MỌI kịch bản bắn data đúng 30 phút** (ramp 5×360s · steady/KB2 1800s) — bắt buộc để
> đối chiếu end-to-end latency với mono cho chuẩn.

---

## 0. (MỘT LẦN) Rebuild vì vừa thêm instrumentation đo end-to-end (cột event_ts)
> ✅ **ĐÃ LÀM SẴN (2026-06-18)**: cloud topology đã redeploy bằng jar mới (đang ACTIVE),
> image `fog-gateway:latest` đã rebuild. **Bỏ qua mục 0 này** — chỉ chạy lại nếu bạn đổi code.
> Bỏ qua khi CHƯA rebuild thì cột `event_ts` sẽ = 0 và không đo được độ trễ end-to-end.
```bash
cd ~/stormsmarthome2
# build lại jar + image gateway
(cd fog-gateway && mvn -q -DskipTests package)
(cd fog-cloud && mvn -q -DskipTests package && cd tagawarescheduler && mvn -q -DskipTests package)
docker build -t fog-gateway:latest ./fog-gateway

# redeploy CLOUD topology (rsync → up → kill topo cũ → submit lại)
CLOUD_IP=52.74.153.60; K=~/.ssh/storm.pem
rsync -avz --exclude='.git' --exclude='**/target/classes' -e "ssh -i $K" ./ ec2-user@$CLOUD_IP:/home/ec2-user/stormsmarthome2/
ssh -i $K ec2-user@$CLOUD_IP 'cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d --build'
ssh -i $K ec2-user@$CLOUD_IP 'docker exec cloud-nimbus storm kill fog-cloud -w 5 || true'
sleep 30
ssh -i $K ec2-user@$CLOUD_IP 'cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d cloud-topo-submit'
```

---

## KB1-A — Scalability, 8 GATEWAY (phân tán)
```bash
cd ~/stormsmarthome2 && ./demo.sh        # bấm 'b' để bật 8 gateway, rồi '0' thoát
```
**Terminal A** (đo):
```bash
cd ~/stormsmarthome2
OUT_DIR=results/kb1-A-multi8gw ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/observe_ramp.sh
```
**Terminal B** (bắn — khi Terminal A báo):
```bash
cd ~/iot-data-publisher && STEP_DUR=360 ./ramp.sh   # 5 nấc × 360s = 30 phút
```
➡️ Chụp Grafana theo URL Terminal A in ra → paste vào **`results/kb1-A-multi8gw/img/`**. CSV (tự lưu): `results/kb1-A-multi8gw/sim_A-multi8gw_scalability.csv`.

## KB1-B — Scalability, 1 GATEWAY (gánh 40 nhà)
```bash
cd ~/stormsmarthome2 && ./demo.sh        # bấm 'c' để bật 1 gateway
# Terminal A:
OUT_DIR=results/kb1-B-single ENV=B CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/observe_ramp.sh
# Terminal B:
cd ~/iot-data-publisher && STEP_DUR=360 ./ramp.sh   # 5 nấc × 360s = 30 phút
```
➡️ Ảnh → **`results/kb1-B-single/img/`**. CSV (tự lưu): `results/kb1-B-single/sim_B-single_scalability.csv`.

---

## KB2-A — Cloud offline → recovery, 8 GATEWAY
```bash
cd ~/stormsmarthome2 && ./demo.sh        # 'b' (8 gateway) nếu chưa bật
# Terminal B (bắn ổn định trước, để chạy suốt):
cd ~/iot-data-publisher && SPEED=10 DURATION=1800 ./send_all.sh
# Terminal A (đợi ~3' cho ổn định rồi chạy):
cd ~/stormsmarthome2
OUT_DIR=results/kb2-A-multi8gw CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/kb2_offline_recovery.sh
```
➡️ Kết quả (tự lưu): `results/kb2-A-multi8gw/kb2_offline_<ts>.md`; ảnh queue-depth → **`results/kb2-A-multi8gw/img/`**.

## KB2-B — Cloud offline → recovery, 1 GATEWAY
```bash
cd ~/stormsmarthome2 && ./demo.sh        # 'c' (1 gateway)
cd ~/iot-data-publisher && SPEED=10 DURATION=1800 ./send_all.sh    # Terminal B
cd ~/stormsmarthome2 && OUT_DIR=results/kb2-B-single CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/kb2_offline_recovery.sh   # Terminal A
```
➡️ Kết quả → `results/kb2-B-single/`; ảnh → **`results/kb2-B-single/img/`**.

---

## ĐỘ TRỄ END-TO-END (produced → ghi DB) — chạy sau KB1
```bash
cd ~/stormsmarthome2
# đổi OUT_DIR đúng kịch bản vừa đo (kb1-A-multi8gw / kb1-B-single / …); chạy TRƯỚC khi reset
OUT_DIR=results/kb1-A-multi8gw MODE=fog SSH_TARGET=ec2-user@52.74.153.60 KEY=~/.ssh/storm.pem ./tools/latency_report.sh
```
Lưu `results/<kịch-bản>/latency_fog_*.csv` (p50/p95/p99/max). So trực tiếp với `latency_mono_*.csv`.

---

## 🔄 RESET GIỮA CÁC KỊCH BẢN (bắt buộc — chống chồng chéo latency)
Chạy SAU khi đo + lấy latency 1 kịch bản, TRƯỚC kịch bản kế:
```bash
cd ~/stormsmarthome2
CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/reset_fog.sh
```
Fog nhiễu NẶNG hơn mono: cloud bolt ghi đè lại toàn bộ slice cũ mỗi 60s → reset này xoá DB
fog + accumulator cloud + queue/accumulator gateway. Sau đó bật lại gateway (`./demo.sh` b/c) rồi đo.

## ⚡ TĂNG TỐC ĐỘ BẮN DATA — phải giống HỆT mono
```bash
cd ~/iot-data-publisher
SPEED=25 DURATION=1800 ./send_all.sh        # steady/KB2: 40×25 = 1000 msg/s
SPEED=25 STEP_DUR=360 ./ramp.sh             # ramp
```

## TẮT gateway local (khi nghỉ)
```bash
cd ~/stormsmarthome2 && docker compose -f docker-compose.gateway.yml --profile multi --profile single down
```

> ⚠️ Công bằng: cùng `SPEED=10`, cùng dataset, cùng exporter/scrape 5s với mono. KB2 là tính năng
> RIÊNG của fog (mono không có store-and-forward → mất 100% data khi cloud offline).
