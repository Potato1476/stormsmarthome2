# Runbook — Cảnh báo đa kênh (Slack) + Phát hiện bất thường tại Gateway

Tính năng này thêm **phát hiện bất thường ngay tại tầng Fog (Gateway)** và **đẩy cảnh báo
ra Slack** khi một thiết bị tiêu thụ điện bất thường — người dùng nhận cảnh báo mà
không cần mở dashboard.

## Kiến trúc

```
Spout_rawData ──data──▶ Bolt_ingest ──(mỗi tuple)──▶ AnomalyDetector (EWMA z-score + trần cứng)
                            │                              │ phát hiện bất thường
                            │ flush 60s                    ▼
                            ▼                         SlackNotifier (Block Kit, async, rate-limit)
                       Cloud MQTT                          │  POST webhook
                       (aggregated)                        ▼
                                                       Slack channel  🚨
```

Cảnh báo đi **thẳng từ edge ra Slack**, không phụ thuộc vòng lặp lên Cloud → độ trễ
mili-giây, vẫn hoạt động kể cả khi Cloud mất kết nối (đúng lợi thế Fog).

## Hai tín hiệu phát hiện

| Tín hiệu | Khi nào kích hoạt | Mức độ | Cần học trước? |
|---|---|---|---|
| **Trần cứng** (`ALERT_HARD_CEILING_W`) | reading ≥ ngưỡng tuyệt đối | `CRITICAL` 🚨 | Không — bắn ngay từ mẫu đầu |
| **EWMA z-score** (`ALERT_Z_THRESHOLD`) | lệch ≥ N sigma khỏi baseline học cho **từng** thiết bị | `WARNING` ⚠️ | Có — sau `ALERT_WARMUP` mẫu |

`AnomalyDetector` giữ EWMA mean + variance cho mỗi thiết bị (vài byte/thiết bị). 2 kW là
bình thường với lò nướng nhưng bất thường với sạc điện thoại — z-score thích nghi theo
từng thiết bị, còn trần cứng bắt quá tải nguy hiểm tuyệt đối.

## Cấu hình (biến môi trường — xem `.env.gateway.example`)

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `SLACK_WEBHOOK_URL` | _(rỗng)_ | Dán webhook vào để **BẬT**. Rỗng = tắt (no-op an toàn). |
| `ALERT_ENABLED` | `true` | Ép tắt bằng `false` dù có webhook. |
| `ALERT_HARD_CEILING_W` | `2500` | Trần công suất tuyệt đối (W). |
| `ALERT_Z_THRESHOLD` | `3.0` | Số sigma lệch baseline → WARNING. |
| `ALERT_EWMA_ALPHA` | `0.3` | Hệ số làm mượt EWMA (0..1). |
| `ALERT_WARMUP` | `20` | Số mẫu trước khi bật z-score. |
| `ALERT_COOLDOWN_SEC` | `60` | Khoảng cách tối thiểu giữa 2 cảnh báo CHO CÙNG 1 thiết bị. |
| `ALERT_MIN_INTERVAL_MS` | `1000` | Khoảng cách tối thiểu giữa 2 lần POST Slack (rate-limit toàn cục). |

## Chạy thử end-to-end (1 gateway, dữ liệu giả lập)

```bash
# 1. Tạo Slack Incoming Webhook (Slack → Apps → Incoming Webhooks → Add to Slack → chọn kênh)
#    rồi thêm vào .env.gateway:
echo 'SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ' >> .env.gateway

# 2. Build lại image (đã gồm code phát hiện bất thường + Slack):
docker build -t fog-gateway:latest fog-gateway

# 3. Khởi động 1 gateway duy nhất + broker local:
docker compose -f docker-compose.gateway.yml --env-file .env.gateway --profile single up -d gw-single mqtt-broker

# 4. Bơm dữ liệu giả lập (sinh công suất 0..3000W → vượt trần 2500W sẽ bắn cảnh báo):
./tools/publish_csv.sh --synthetic 2000 200

# 5. Xem cảnh báo trong Slack 🚨, và log gateway:
docker logs -f gw-single | grep ALERT
```

### Kiểm tra nhanh chỉ riêng webhook (không cần Storm)

```bash
java -cp fog-gateway/target/fog-gateway-1.0-jar-with-dependencies.jar \
     com.storm.iotdata.fog.alert.SlackNotifier "$SLACK_WEBHOOK_URL"
```
Gửi 1 cảnh báo CRITICAL mẫu và in kết quả HTTP — cách nhanh nhất để xác nhận webhook đúng.

## Quan sát qua Prometheus

`Bolt_ingest` xuất thêm 2 counter (cổng `:9091/metrics`):

- `fog_gateway_alerts_fired_total` — số cảnh báo đã đẩy ra kênh ngoài.
- `fog_gateway_alerts_suppressed_total` — số cảnh báo bị nén bởi cooldown từng thiết bị.

## Góc độ học thuật (so sánh độ trễ kênh)

- MQTT local (cảnh báo thiết bị tức thì): < 10 ms, trong LAN.
- Slack webhook (kênh ra ngoài): ~200–500 ms.
- Phát hiện ngay tại edge (không round-trip Cloud) so với phát hiện ở Cloud sau flush 60s
  → minh chứng Fog đảm bảo SLA real-time cho cảnh báo quan trọng.

## Tệp liên quan

- `fog-gateway/.../anomaly/AnomalyDetector.java` — logic EWMA z-score + trần cứng (có unit test).
- `fog-gateway/.../alert/SlackNotifier.java` — Block Kit + POST webhook async, rate-limit.
- `fog-gateway/.../alert/Alert.java` — model cảnh báo (sẵn sàng mở rộng Telegram/FCM/email).
- `fog-gateway/.../storm/Bolt_ingest.java` — nối phát hiện + cooldown từng thiết bị.
- `fog-gateway/.../GatewayConfig.java` — đọc cấu hình từ biến môi trường.
