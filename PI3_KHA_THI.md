# Raspberry Pi 3 có xử lý nổi dataset 500MB không? (góp ý 3 của giáo sư)

> *"Data chỉ 500MB thì 1 Pi 3 thực tế có xử lý được không? Nếu được thì
> chẳng phải quá tốt sao — thiết bị rẻ tiền mà vẫn xử lý tốt."*

> **Cập nhật:** thực nghiệm chuyển sang **giả lập** thiết bị biên bằng Docker
> (mỗi gateway giới hạn 1GB/1vCPU đúng cỡ Pi 3) thay vì Pi phần cứng — xem
> `KICH_BAN_THI_NGHIEM.md` Phần II (`run_sim_experiments.sh`). Phần dưới giữ
> lại làm **phân tích lý thuyết** về khả năng của Pi 3 và cách quy đổi giới hạn
> container ↔ phần cứng thật.

## 1. Ước lượng trên giấy: tải này RẤT nhẹ so với khả năng Pi 3

| Đại lượng | Giá trị | Ghi chú |
|---|---|---|
| Dataset | ~500 MB CSV, 40 nhà, ~16h dữ liệu | REFIT, ~50 byte/dòng → ~10 triệu dòng |
| Tốc độ phát lại chuẩn đo | SPEED=10 msg/s/nhà × 40 nhà = **~400 msg/s** | bằng kịch bản đo monolithic |
| Băng thông vào | 400 × ~50B ≈ **20 KB/s** | NIC Pi 3 100 Mbps — dư ~600 lần |
| Việc phải làm mỗi msg | split chuỗi + lọc property + cộng dồn 8 cửa sổ | vài nghìn phép tính đơn giản/giây |
| Pi 3 Model B | 4× Cortex-A53 1.2GHz, **1GB RAM** | điểm nghẽn duy nhất là **RAM cho JVM** |

CPU: A53 làm được hàng chục triệu phép tính đơn giản/giây/lõi → 400 msg/s
(kể cả fan-out ×8 cửa sổ ≈ vài nghìn tuple/s nội bộ) chiếm cỡ vài % CPU.
**Rủi ro thật nằm ở RAM 1GB**: phải chạy JVM heap ≤512MB và dùng
Raspberry Pi OS Lite 64-bit (không GUI).

Bằng chứng gián tiếp đã có: tầng gateway từng chạy ổn trong container giới
hạn **1GB RAM / 1 vCPU** ở tốc độ trên (xem `docker-compose.gateway.yml` v2);
cấu hình FOG v1 cũng giới hạn supervisor1 đúng mức Pi 3 (`gateway/.env`).
*Caveat trung thực: 1 vCPU laptop/EC2 mạnh hơn 1 lõi A53 — nên mới cần đo
trên Pi thật.*

## 2. Phương án đo trên Pi 3 THẬT

### Phương án A — đo NĂNG LỰC xử lý (khuyến nghị làm trước, không phụ thuộc mạng)

Chạy toàn bộ workload tầng gateway cho CẢ 40 nhà trên 1 Pi:

1. Cài Raspberry Pi OS **Lite 64-bit** (bắt buộc 64-bit để có JDK/ARM image) + Docker.
2. Image `fog-gateway:latest` là multi-arch (temurin-8, đã chạy trên ARM64) —
   build trên laptop: `docker buildx build --platform linux/arm64 -t fog-gateway:pi --load ./fog-gateway`
   rồi `docker save | ssh pi docker load`.
3. Trên Pi: chạy 1 container gateway phụ trách `HOUSE_IDS=0..39` + mosquitto local.
4. Từ laptop bơm dữ liệu tăng dần: `SPEED=10 → 20 → 50` (`DURATION=600` mỗi nấc),
   theo dõi `http://<pi>:9091/metrics` (`fog_gateway_tuples_processed_total`)
   + `vmstat 5` trên Pi.
5. **Tiêu chí đạt:** tốc độ xử lý bám sát tốc độ bơm (không tụt lại),
   RAM ổn định không OOM, CPU < 80%.

Kết quả kỳ vọng: đạt ở SPEED=10 (400 msg/s) với CPU thấp → đúng luận điểm
"thiết bị ~35 USD gánh trọn tầng biên cho 40 hộ" — điểm cộng lớn cho mô hình Fog.

### Phương án B — Pi 3 làm supervisor1 thật trong FOG v1 (demo end-to-end)

Pi thay thế EC2 gateway trong RUNBOOK_FOG_V1:

1. Trên Pi (OS 64-bit): cài `temurin-8-jdk` + Apache Storm 2.1.0 (tarball,
   Storm là Java thuần nên chạy native ARM được), copy
   `gateway/storm/config/supervisor.yaml` vào `conf/storm.yaml`,
   sửa `zookeeper`/`nimbus`/`mysql` trỏ về `52.74.153.60` (qua `/etc/hosts`).
2. Chạy mosquitto local trên Pi (broker `mqtt-broker` trong `/etc/hosts` → 127.0.0.1).
3. **Lưu ý NAT:** worker cloud phải kết nối ngược vào Pi (port 6700-6703) —
   Pi ở mạng nhà cần **port-forward 6700-6703** trên router về Pi, và
   `storm.local.hostname` đặt bằng IP public của mạng nhà.
4. Phần còn lại giống RUNBOOK_FOG_V1 (submit, đo, test mất mạng — riêng test
   mất mạng chỉ cần rút dây mạng/tắt WiFi của Pi là cách demo trực quan nhất:
   cảnh báo thiết bị VẪN hiện trên broker local của Pi).

### Trả lời câu hỏi của giáo sư

Theo ước lượng + bằng chứng container 1GB/1vCPU: **có, 1 Pi 3 xử lý được**
dataset này ở tốc độ phát lại chuẩn đo (400 msg/s), nghẽn duy nhất cần canh
là RAM. Và đúng như giáo sư nói — đây là **kết quả tốt cần nhấn mạnh trong
báo cáo**: tầng biên không cần phần cứng đắt tiền; gateway rẻ tiền + cloud
chia tải hợp lý chính là giá trị của kiến trúc Fog.
