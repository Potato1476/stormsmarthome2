# Hướng Dẫn Chạy — Fog Computing Smart Home IoT

Hai tầng: **Gateway** (8 container trên laptop, giả lập Raspberry Pi 3B) + **Cloud** (EC2 AWS).

---

## Bật hệ thống để đo

### Bước 1 — Start EC2 (nếu đã stop trước đó)

```bash
cd ~/stormsmarthome2
./infrastructure/scripts/start.sh
```

Chờ ~2 phút cho EC2 boot xong và các container Cloud tự khởi động.  
IP Cloud **không thay đổi** (Elastic IP tĩnh) → không cần cập nhật gì thêm.

Kiểm tra Cloud ổn:

```bash
# Xem Storm UI (topology phải hiển thị là ACTIVE)
open http://$(cd infrastructure/terraform && terraform output -raw cloud_public_ip):8080

# Hoặc kiểm tra nhanh qua exporter
curl -s http://$(cd infrastructure/terraform && terraform output -raw cloud_public_ip):8000/metrics | head -5
```

---

### Bước 2 — Start 8 Gateway + Monitoring trên local

```bash
cd ~/stormsmarthome2
docker compose -f docker-compose.gateway.yml --env-file .env.gateway up -d
```

> Nếu laptop vừa bật lại và Docker Desktop đã chạy, các container có thể đã tự khởi động
> (restart policy `unless-stopped`). Lệnh trên chạy lại cũng không sao (idempotent).

Kiểm tra:

```bash
docker compose -f docker-compose.gateway.yml ps
# Tất cả phải là "running" hoặc "healthy"
```

Mở Grafana: [http://localhost:3000](http://localhost:3000) → `admin / admin`

---

### Bước 3 — Chạy publisher để bơm dữ liệu

```bash
cd ~/iot-data-publisher
SPEED=10 DURATION=1800 ./send_all.sh
# 40 nhà × 10 msg/s = ~400 msg/s tổng thô, tự dừng sau 30 phút
```

Xác nhận dữ liệu đang chạy (terminal khác):

```bash
# Gateway đang nhận
curl -s http://localhost:9091/metrics | grep tuples_processed_total
# Grafana: xem panel "Gateway: Tuple Ingestion Rate" → phải ~30 t/s mỗi gateway
```

---

## Tắt hệ thống sau khi đo

### Tắt publisher

`Ctrl+C` trong terminal đang chạy `send_all.sh`, hoặc đợi 30 phút tự dừng.

### Tắt EC2 (tiết kiệm chi phí)

```bash
cd ~/stormsmarthome2
./infrastructure/scripts/stop.sh
```

> EBS giữ nguyên dữ liệu MySQL + ZooKeeper state. Lần sau `start.sh` là tiếp tục được.

### Tắt gateway local (tuỳ chọn)

```bash
docker compose -f docker-compose.gateway.yml stop
# Dùng "stop" thay vì "down" để container tự khởi động lại khi Docker Desktop bật lại
```

---

## Tham khảo nhanh

| Thứ | URL / Lệnh |
|-----|------------|
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Storm UI | `http://$(cd infrastructure/terraform && terraform output -raw cloud_public_ip):8080` |
| Cloud IP | `cd infrastructure/terraform && terraform output -raw cloud_public_ip` |

---

## Khi nào cần làm thêm

| Tình huống | Việc cần làm |
|---|---|
| Lần đầu setup, chưa có EC2 | Xem mục "Lần đầu setup" bên dưới |
| Topology biến mất khỏi Storm UI | Nộp lại topology (xem bên dưới) |
| Gateway không đẩy được lên Cloud | Kiểm tra IP và Security Group (xem bên dưới) |
| Muốn xoá hết EC2/EIP | `./infrastructure/scripts/destroy.sh` |

---

## Nộp lại topology (khi Storm UI không có topology)

Thường xảy ra nếu ZooKeeper mất data (EC2 bị terminate rồi tạo lại). SSH vào EC2 rồi nộp:

```bash
CLOUD_IP=$(cd infrastructure/terraform && terraform output -raw cloud_public_ip)

ssh -i ~/.ssh/storm.pem ec2-user@$CLOUD_IP \
  'cd stormsmarthome2 && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d cloud-topo-submit'
```

Chờ ~90 giây → F5 Storm UI xem topology `iot-smarthome` xuất hiện.

---

## Gateway không kết nối được Cloud

```bash
CLOUD_IP=$(cd infrastructure/terraform && terraform output -raw cloud_public_ip)

# Kiểm tra từ máy local
nc -zv $CLOUD_IP 1883 && echo "OK" || echo "FAIL — kiểm tra Security Group"

# Nếu FAIL: IP máy bạn đã đổi → cập nhật Security Group
terraform -chdir=infrastructure/terraform apply \
  -var="your_ip_cidr=$(curl -s ifconfig.me)/32"
```

---

## Lần đầu setup (chỉ làm một lần)

> **Bỏ qua nếu EC2 đã tồn tại từ trước.**

```bash
# 1. Build JAR
cd fog-gateway && mvn package -DskipTests && cd ..
cd fog-cloud && mvn package -DskipTests && cd tagawarescheduler && mvn package -DskipTests && cd ../..

# 2. Build Docker image gateway (cho ARM64 hoặc x86_64 tuỳ máy)
docker build -t fog-gateway:latest ./fog-gateway

# 3. Dựng EC2 bằng Terraform
export AWS_PROFILE=fog-smarthome
cd infrastructure/terraform
terraform init
terraform apply -var="key_pair_name=storm" -var="your_ip_cidr=$(curl -s ifconfig.me)/32"
cd ../..

# 4. Điền IP Cloud vào .env.gateway và prometheus (chỉ cần làm 1 lần vì EIP tĩnh)
./infrastructure/scripts/set-cloud-ip.sh

# 5. Copy mã nguồn lên EC2 và bật Cloud
CLOUD_IP=$(cd infrastructure/terraform && terraform output -raw cloud_public_ip)
rsync -avz --exclude='.git' --exclude='**/target/classes' \
  -e "ssh -i ~/.ssh/storm.pem" \
  ./ ec2-user@$CLOUD_IP:/home/ec2-user/stormsmarthome2/

ssh -i ~/.ssh/storm.pem ec2-user@$CLOUD_IP \
  'cd stormsmarthome2 && cp .env.cloud.example .env.cloud && docker compose -f docker-compose.cloud.yml --env-file .env.cloud up -d'

# 6. Bật gateway local
docker compose -f docker-compose.gateway.yml --env-file .env.gateway up -d
```
