# RUNBOOK — Phiên đo hệ FOG  (dự án `stormsmarthome2`)

Đo hệ Fog (8 gateway biên + 1 Cloud EC2) trong 30 phút, cùng dataset & tốc độ với
phiên Monolithic, để so sánh công bằng. Phiên Monolithic xem `~/stormsmarthome/RUNBOOK_MONOLITHIC.md`.

Bắn data từ: **`~/iot-data-publisher`** (raw vào local-mqtt; gateway gửi aggregate lên Cloud).

> Bạn chỉ cần chạy lệnh ở §2→§4. Bước so sánh cuối (§5) cần đã chạy xong cả phiên Monolithic.

---

## 0. Điều kiện cần
- AWS CLI đã cấu hình; terraform đã `init` trong `infrastructure/terraform/`; key `.pem` ở `~/.ssh/<key>.pem`.
- Hiểu cách dựng hệ Fog (chi tiết: `HUONG_DAN_CHAY.md`).

## 1. Bật hệ Fog
```bash
# Cloud tier trên AWS
cd infrastructure/terraform && terraform apply
terraform output cloud_public_ip          # ghi lại IP fog-cloud
# Điền IP đó vào gateway + prometheus (1 lệnh):
cd ../scripts && ./set-cloud-ip.sh $(cd ../terraform && terraform output -raw cloud_public_ip)
# (Deploy stack Cloud + submit topology fog-cloud: xem HUONG_DAN_CHAY.md)

# Gateway tier + monitoring chạy local (8 gateway + Prometheus :9090 + Grafana :3000)
cd ~/stormsmarthome2 && docker compose -f docker-compose.gateway.yml up -d
```
Kiểm tra: Grafana `http://localhost:3000`, gateway `gw-01..08` đang chạy.

---

## 2. Bắn data (30 phút, ~400 msg/s)  ← **PHẦN BẮN DATA**
```bash
cd ~/iot-data-publisher
SPEED=10 DURATION=1800 ./send_all.sh        # 40 nhà × 10 = ~400 msg/s, tự dừng sau 30'
```

## 3. Thu số liệu (chạy ở phút ~0 sau warmup và phút ~30)

### 3A. App-level (throughput / latency / capacity)
```bash
cd ~/stormsmarthome2
./tools/collect_metrics.sh fog              # Prometheus local :9090
```

### 3B. Tài nguyên + WAN (chạy CẢ t0 lẫn t30)
```bash
# 8 gateway chạy local:
./tools/collect_system.sh fog-gw-t0         # ngay sau warmup
./tools/collect_system.sh fog-gw-t30        # ở phút 30
# Cloud trên EC2 (cần cả t0+t30 để WAN = RX cloud-mqtt t30−t0):
SSH_TARGET=ec2-user@52.74.153.60 KEY=~/.ssh/<key>.pem ./tools/collect_system.sh fog-cloud-t0
SSH_TARGET=ec2-user@52.74.153.60 KEY=~/.ssh/<key>.pem ./tools/collect_system.sh fog-cloud-t30
```
CSV lưu ở `results/`.

---

## 4. Tắt (tuỳ chọn, để khỏi tốn tiền nếu nghỉ lâu)
```bash
docker compose -f docker-compose.gateway.yml down
# fog-cloud EC2: dùng infrastructure/scripts/stop... (xem HUONG_DAN_CHAY.md)
```

---

## 5. So sánh với Monolithic (sau khi đã chạy xong CẢ hai phiên)
```bash
cd ~/stormsmarthome2
./tools/compare_results.py                  # đọc results/, ra bảng + COMPARISON_<ts>.md
```

---

## Ghi nhớ tính hợp lệ
- Bắn cùng `SPEED=10` (publisher throttle giống Monolithic) → cùng ~400 msg/s raw.
- Cùng exporter `mr4x2/stormexporter:v1.2.2` REFRESH_RATE=5, Prometheus scrape 5s như Monolithic.
- So mạnh nhất = throughput (acked/emitted/transferred) + WAN; latency/capacity = cùng box, định tính.
- Chạy 2 phiên **riêng biệt**, không cùng lúc.
