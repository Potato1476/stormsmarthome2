# PROMPTS — dán vào Claude Code (VS Code) để TỰ chạy từng kịch bản

Cách dùng: mở Claude Code trong folder `stormsmarthome2`, **copy nguyên 1 ô
prompt** bên dưới rồi dán vào. Claude sẽ tự dựng stack + đo + xuất ảnh và
**in ra lệnh bắn data** — bạn chỉ việc mở terminal ở `~/iot-data-publisher`
chạy lệnh đó, rồi làm việc khác. Xong Claude báo kết quả + URL để chụp.

**Trước khi bắt đầu (1 lần):**
- Kiểm tra môi trường: `./tools/preflight.sh` — phải 0 FAIL (WARN về cloud thì
  xử lý theo mục cuối file).
- Cloud EC2 IP `52.74.153.60`. Cần thông để đo WAN + chạy KB2.
- Thay `~/.ssh/YOUR_KEY.pem` trong prompt bằng key SSH thật của bạn.
- Mỗi kịch bản chạy ~15–25 phút. Chạy lần lượt, không chạy 2 kịch bản cùng lúc.

> Bạn chỉ thao tác ở `iot-data-publisher` (bắn data) và **tự chụp ảnh Grafana**
> khi Claude báo. Mọi thứ khác Claude lo. **Số liệu thực (số chuẩn) tự lưu vào
> CSV/MD; ảnh chỉ để minh hoạ trực quan.**

---

## 🟦 KỊCH BẢN 1 — Scalability, MÔI TRƯỜNG A (8 gateway phân tán)

```
Chạy giúp tôi KỊCH BẢN 1 (scalability ramp) môi trường A. Tự làm toàn bộ, đừng hỏi tôi câu nào.
Các bước:
1. cd vào ~/stormsmarthome2.
2. Nếu chưa có image: docker build -t fog-gateway:latest ./fog-gateway
3. ./infrastructure/scripts/set-cloud-ip.sh 52.74.153.60
4. docker compose -f docker-compose.gateway.yml --profile multi --env-file .env.gateway up -d
5. Chờ tới khi http://localhost:9090 (Prometheus) và http://localhost:3000 (Grafana) trả lời.
6. Chạy Ở CHẾ ĐỘ NỀN (vì kéo dài ~25 phút):
   ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/YOUR_KEY.pem ./tools/observe_ramp.sh
7. Theo dõi output. Ngay khi script in dòng "HÃY BẮN DATA NGAY ... STEP_DUR=300 ./ramp.sh",
   hãy NHẮC TÔI thật rõ ràng (in to dòng lệnh đó) để tôi sang ~/iot-data-publisher chạy.
   Cũng đưa tôi URL "MỞ SẴN Grafana" mà script in ra để tôi mở dashboard theo dõi.
8. Để script tự chạy đến hết (nó tự phát hiện data và đo 5 nấc 1→5→10→20→40 nhà).
9. Khi xong, in cho tôi: (a) bảng SỐ CHUẨN từ results/sim_A-multi8gw_scalability.csv,
   (b) URL Grafana chụp tay mà script in ra (đã ghim đúng khoảng thời gian), (c) tên các
   panel nên chụp, (d) thư mục lưu ảnh: results/img/kb1-A-multi8gw/.
Đừng tự render ảnh; tôi sẽ TỰ chụp. Đừng dừng giữa chừng để hỏi; chạy tới kết quả cuối.
```

## 🟩 KỊCH BẢN 1 — Scalability, MÔI TRƯỜNG B (1 gateway ôm 40 nhà)

```
Chạy giúp tôi KỊCH BẢN 1 (scalability ramp) môi trường B. Tự làm toàn bộ, đừng hỏi tôi.
Các bước:
1. cd ~/stormsmarthome2 ; build image nếu chưa có ; ./infrastructure/scripts/set-cloud-ip.sh 52.74.153.60
2. Tắt môi trường A rồi bật B:
   docker compose -f docker-compose.gateway.yml --profile multi --env-file .env.gateway down
   docker compose -f docker-compose.gateway.yml --profile single --env-file .env.gateway up -d
3. Chờ Prometheus :9090 và Grafana :3000 sẵn sàng.
4. Chạy Ở CHẾ ĐỘ NỀN (~25 phút):
   ENV=B CLOUD_IP=52.74.153.60 KEY=~/.ssh/YOUR_KEY.pem ./tools/observe_ramp.sh
5. Ngay khi script in "HÃY BẮN DATA NGAY ... STEP_DUR=300 ./ramp.sh", nhắc tôi rõ ràng để tôi chạy ở ~/iot-data-publisher, kèm URL "MỞ SẴN Grafana".
6. Để script chạy hết. Khi xong, in: bảng SỐ CHUẨN results/sim_B-single_scalability.csv,
   URL Grafana chụp tay (script in ra), panel nên chụp, thư mục lưu ảnh results/img/kb1-B-single/.
Quan trọng: nếu môi trường B (1 gateway 1GB) bị OOM hoặc CPU chạm 100% ở nấc nhiều nhà,
hãy nêu rõ trong kết luận — đó chính là kết quả "1 thiết bị nhỏ thì nghẽn".
Đừng tự render ảnh; tôi tự chụp. Đừng hỏi, chạy tới hết.
```

## 🟧 KỊCH BẢN 2 — Cloud Offline → Recovery, MÔI TRƯỜNG A

```
Chạy giúp tôi KỊCH BẢN 2 (Cloud Offline 5 phút → Recovery) môi trường A. Tự làm toàn bộ, đừng hỏi tôi.
Các bước:
1. cd ~/stormsmarthome2 ; đảm bảo stack profile multi đang chạy
   (docker compose -f docker-compose.gateway.yml --profile multi --env-file .env.gateway up -d).
2. Chạy Ở CHẾ ĐỘ NỀN (~12 phút):
   ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/YOUR_KEY.pem ./tools/observe_offline.sh
   (KEY phải là key THẬT — bài này cần SSH vào EC2 để tắt/bật cloud-mqtt.)
3. Ngay khi script in "HÃY BẮN DATA NỀN ... ./send_all.sh", nhắc tôi rõ để tôi chạy ở ~/iot-data-publisher.
4. Để script tự: chờ data → warmup → tắt cloud-mqtt 5' → bật lại → đo. Đừng can thiệp.
   (Đưa tôi URL "MỞ SẴN Grafana" mà script in để tôi xem queue dâng rồi xả.)
5. Khi xong, in cho tôi: báo cáo SỐ CHUẨN results/kb2_A-multi8gw_*.md (Max Queue Depth /
   Recovery Time / Data Loss %), URL Grafana chụp tay (script in ra), panel 'Store-and-Forward
   Queue Depth', thư mục lưu ảnh results/img/kb2-A-multi8gw/.
Đừng tự render ảnh; tôi tự chụp. Đừng dừng để hỏi; chạy tới kết quả cuối.
```

## 🟥 KỊCH BẢN 2 — Cloud Offline → Recovery, MÔI TRƯỜNG B

```
Chạy giúp tôi KỊCH BẢN 2 (Cloud Offline 5 phút → Recovery) môi trường B. Tự làm toàn bộ, đừng hỏi tôi.
Các bước:
1. cd ~/stormsmarthome2 ; chuyển sang stack B:
   docker compose -f docker-compose.gateway.yml --profile multi --env-file .env.gateway down
   docker compose -f docker-compose.gateway.yml --profile single --env-file .env.gateway up -d
2. Chạy Ở CHẾ ĐỘ NỀN (~12 phút):
   ENV=B CLOUD_IP=52.74.153.60 KEY=~/.ssh/YOUR_KEY.pem ./tools/observe_offline.sh
3. Khi script in "HÃY BẮN DATA NỀN ... ./send_all.sh", nhắc tôi rõ để tôi chạy ở ~/iot-data-publisher, kèm URL "MỞ SẴN Grafana".
4. Để script tự chạy hết. Khi xong, in: báo cáo SỐ CHUẨN results/kb2_B-single_*.md,
   URL Grafana chụp tay, panel 'Store-and-Forward Queue Depth', thư mục lưu ảnh results/img/kb2-B-single/.
Đừng tự render ảnh; tôi tự chụp. Đừng hỏi; chạy tới kết quả cuối.
```

---

## Bạn làm gì ở `iot-data-publisher` (chỉ 1 lệnh/kịch bản)

Khi Claude báo "HÃY BẮN DATA", mở terminal ở `~/iot-data-publisher` và chạy:

| Kịch bản | Lệnh bắn data |
|---|---|
| **KB1** (A hoặc B) | `STEP_DUR=300 ./ramp.sh`  ← tự tăng 1→5→10→20→40 nhà |
| **KB2** (A hoặc B) | `SPEED=10 DURATION=1500 ./send_all.sh`  ← 40 nhà liên tục, để chạy đến khi Claude báo xong |

Lần đầu cần `npm install` trong `~/iot-data-publisher`. `STEP_DUR` của `ramp.sh`
phải khớp với lúc Claude chạy (mặc định cả hai là 300 → khỏi chỉnh).

## Kết quả lưu ở đâu

**SỐ CHUẨN (tự lưu, dùng cho báo cáo — quan trọng nhất):**

| Kịch bản | File số chuẩn |
|---|---|
| KB1 môi trường A | `results/sim_A-multi8gw_scalability.csv` (+ `results/sim_stats_sim-A-*.csv`) |
| KB1 môi trường B | `results/sim_B-single_scalability.csv` (+ `results/sim_stats_sim-B-*.csv`) |
| KB2 môi trường A | `results/kb2_A-multi8gw_*.md` |
| KB2 môi trường B | `results/kb2_B-single_*.md` |

**ẢNH BẠN TỰ CHỤP (minh hoạ) — lưu đúng thư mục theo kịch bản** (script tự tạo sẵn):

| Kịch bản | Thư mục lưu ảnh |
|---|---|
| KB1 môi trường A | `results/img/kb1-A-multi8gw/` |
| KB1 môi trường B | `results/img/kb1-B-single/` |
| KB2 môi trường A | `results/img/kb2-A-multi8gw/` |
| KB2 môi trường B | `results/img/kb2-B-single/` |

Cách chụp: khi Claude báo "GIỜ VÀO CHỤP", mở URL Grafana nó đưa (đã ghim đúng
khoảng thời gian phiên, login admin/admin) → chụp các panel được nêu → lưu file
ảnh vào đúng thư mục trên.

Ghép báo cáo: mỗi kịch bản = 1 bảng (từ CSV/MD = **số chuẩn**) + 1–2 ảnh minh
hoạ. So sánh A↔B để rút ra luận điểm phân tán. Chi tiết "cách đọc" trong
[KICH_BAN_THI_NGHIEM.md](KICH_BAN_THI_NGHIEM.md).

## Nếu Cloud EC2 không phản hồi (`curl http://52.74.153.60:8080` lỗi)

1. SSH vào EC2 kiểm tra stack cloud đã chạy chưa:
   `ssh -i ~/.ssh/YOUR_KEY.pem ec2-user@52.74.153.60 "docker ps"` — phải thấy
   cloud-mqtt, cloud-mysql, cloud-nimbus, cloud-supervisor, cloud-storm-exporter.
   Chưa có → deploy theo [HUONG_DAN_CHAY.md](HUONG_DAN_CHAY.md) §5.
2. Nếu SSH cũng treo → Security Group chặn IP nhà bạn (IP đã đổi). Vào AWS
   Console → EC2 → Security Group `fog-cloud-sg` → sửa inbound mở 22/1883/8080/8000
   cho IP hiện tại (`curl ifconfig.me`).
