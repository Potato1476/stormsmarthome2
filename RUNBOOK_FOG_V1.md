# RUNBOOK — FOG v1 (code thầy + TagAwareScheduler, 2 EC2)

Một Storm cluster duy nhất trải trên 2 máy AWS:

```
 MÁY GATEWAY (t3.small, EIP)            MÁY CLOUD (t3.large, EIP)
 ┌──────────────────────────┐           ┌──────────────────────────────────┐
 │ mqtt-broker  :1883       │           │ zookeeper :2181                  │
 │  (raw data + cảnh báo    │           │ nimbus+UI :8080/:6627            │
 │   local cho hộ gia đình) │  WAN      │   └─ TagAwareScheduler           │
 │ supervisor1 (KHÔNG tag,  │◀─────────▶│ supervisor2 (tags: cloud)        │
 │  giới hạn 1GB/1vCPU≈Pi3) │ avg→sum   │   └─ sum-*, forecast-*           │
 │  └─ spout, split-*, avg-*│           │ mysql :3306   storm-exporter:8000│
 └──────────▲───────────────┘           └──────────────────────────────────┘
            │ MQTT raw (SPEED=10/house, 40 nhà)
       [Publisher — laptop]
```

## 0. Build (local, một lần)

```bash
cd gateway && mvn package -DskipTests          # Storm-IOTdata-...jar (topology)
cd tagawarescheduler && mvn package -DskipTests # tagawarescheduler-1.0.jar
```

## 1. Dựng hạ tầng

```bash
cd infrastructure/terraform
terraform apply -var key_pair_name=<key> -var your_ip_cidr=<ip-của-bạn>/32
# outputs: cloud_public_ip, gateway_public_ip (đều là EIP tĩnh)
```

## 2. Deploy 2 máy

Đồng bộ repo lên cả 2 máy (đã build jar ở local):

```bash
rsync -az -e "ssh -i $KEY" --exclude .git . ec2-user@52.74.153.60:~/stormsmarthome2/
rsync -az -e "ssh -i $KEY" --exclude .git . ec2-user@<GATEWAY_IP>:~/stormsmarthome2/
```

**Máy cloud:**
```bash
cd ~/stormsmarthome2/cloud
cp .env.example .env   # điền GATEWAY_PUBLIC_IP=<gateway EIP>
docker compose up -d   # zookeeper, nimbus, supervisor2, mysql, storm-exporter
```

**Máy gateway:**
```bash
cd ~/stormsmarthome2/gateway
cp .env.example .env   # điền CLOUD_PUBLIC_IP=<cloud EIP>
docker compose up -d   # mqtt-broker, supervisor1 (1GB/1vCPU)
```

## 3. Nộp topology (trên máy cloud)

```bash
cd ~/stormsmarthome2/cloud
docker compose run --rm topo-submit
# hoặc đổi phân chia bolt: CLOUD_BOLTS="sum,forecast,avg-60,avg-120,split-60,split-120" docker compose run --rm topo-submit
```

Kiểm tra Storm UI `http://52.74.153.60:8080`:
- topology `iot-smarthome` ACTIVE, 2 worker;
- vào trang topology → **component** `sum-1` host = `supervisor2`,
  `avg-1` host = `supervisor1` → tag hoạt động đúng.

## 4. Bơm dữ liệu (laptop)

```bash
cd ~/iot-data-publisher
BROKER_HOST=<GATEWAY_IP> SPEED=10 DURATION=1800 ./send_all.sh   # ~400 msg/s
```

## 5. Đo lường (so sánh với Monolithic — cùng jar, cùng dataset, cùng exporter)

Prometheus/Grafana local (monitoring/) scrape `http://52.74.153.60:8000`.
Cùng quy trình với `RUNBOOK_FOG.md` cũ:

```bash
./tools/collect_metrics.sh fogv1-t0      # sau warmup 5'
./tools/collect_system.sh  fogv1-gw-t0   # SSH_TARGET=ec2-user@<GW_IP> KEY=...
./tools/collect_system.sh  fogv1-cloud-t0
# ... chạy 30' ...
./tools/collect_metrics.sh fogv1-t30
./tools/collect_system.sh  fogv1-gw-t30
./tools/collect_system.sh  fogv1-cloud-t30
./tools/compare_results.py
```

Điểm so sánh "đẹp" cần nêu trong báo cáo:
- `bolts_capacity{bolt="avg-1"}`: monolithic 14.5 → FOG v1 (avg-1 một mình
  một máy) — kỳ vọng giảm mạnh;
- CPU 2 máy (collect_system): cloud KHÔNG còn gánh split/avg, gateway Pi-class
  gánh phần nhẹ → "chia tải" đúng nghĩa;
- NET I/O của `supervisor1` (WAN ra cloud) so với tổng raw vào `mqtt-broker`.

## 6. Kiểm tra hàng đợi / mất mạng (góp ý 2 của giáo sư)

Trong lúc publisher đang chạy:

```bash
GATEWAY_IP=<gw-ip> CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem \
  OUTAGE_SEC=90 ./tools/test_offline_queue.sh
```

Script tự động: chặn iptables gateway↔cloud 90s → đếm cảnh báo thiết bị vẫn
phát trên broker local trong outage → khôi phục → kiểm tra MySQL tiếp tục tăng
và dãy `slice_index` không lỗ hổng → in PASS/FAIL + lưu `results/offline_queue_test_*.md`.

## 7. Dọn dẹp

```bash
cd infrastructure/terraform && terraform destroy
```

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| Storm UI: topology ACTIVE nhưng `sum-*` không có host | supervisor2 chưa lên hoặc thiếu `tags: cloud` trong `cloud/storm/config/supervisor.yaml` |
| `SCHEDULING FAILED` trên UI | TagAwareScheduler không tìm thấy supervisor cho 1 tag — kiểm tra cả 2 supervisor đã đăng ký (UI → Supervisor Summary) |
| Worker 2 phía không trao đổi tuple | SG chưa mở 6700-6703 theo EIP của máy kia (terraform đã khai báo — kiểm tra `terraform apply` chạy đủ) |
| Gateway OOM | `worker.heap.memory.mb: 512` trong `gateway/storm/config/supervisor.yaml` phải nhỏ hơn `GW_MEM_LIMIT` |
| Cảnh báo local không có message | Ngưỡng `notification.device.checkMax: true` trong `conf.yaml` — cần dữ liệu vượt max lịch sử mới phát |
