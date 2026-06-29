# Fog Computing Smart Home IoT (FOG v2) — Apache Storm

Hệ thống xử lý dữ liệu IoT nhà thông minh theo mô hình **Fog Computing v2 (2 tầng phân tán)**:
- **Tầng Gateway (Edge / Local - Raspberry Pi 3)**:
  - Nhận dữ liệu điện năng raw từ Publisher cục bộ qua broker MQTT local.
  - Tích hợp bộ phát hiện bất thường **EWMA z-score + hard-ceiling** ngay tại biên và bắn cảnh báo trực tiếp ra **Slack** từng hộ gia đình (tính năng thời gian thực độc lập, không phụ thuộc WAN).
  - Tích hợp cơ chế **Store-and-Forward queue** (lưu trữ SQLite local) giúp lưu trữ và truyền lại toàn vẹn dữ liệu khi mạng Cloud mất kết nối (Outage Recovery).
  - Tích lũy (aggregate) dữ liệu theo chu kỳ 60s và chuyển tiếp lên Cloud.
- **Tầng Cloud (AWS EC2)**:
  - Broker MQTT nhận dữ liệu aggregated từ các Gateway.
  - Storm topology `fog-cloud` (`Spout_aggregated` + `Bolt_cloudMerge`) gộp dữ liệu các Gateway và ghi trực tiếp vào MySQL database (`cloud-mysql`) với cơ chế **JDBC batch-transaction**.
  - Dịch vụ API `iot-data-api` chạy Web Dashboard trên cổng 9000 phục vụ hiển thị dữ liệu thời gian thực và so sánh baseline dự báo.

```
[Publisher] ──MQTT──▶ [Local MQTT] ──▶ [fog-gateway] ──(Slack API)──▶ Slack Alert 🚨
                         (raw)       - Anomaly EWMA z-score
                                     - Aggregation (60s)
                                     - Store-Forward Queue
                                              │
                                             WAN
                                        (aggregated)
                                              ▼
                                       [Cloud MQTT]
                                              │
                                              ▼
                                         [fog-cloud] (Storm Topology on EC2)
                                              │
                                              ▼
                                        [Cloud MySQL] ◀── [iot-data-api (Port 9000)]
```

---

## 📂 Cấu trúc thư mục chính

| Thư mục / File | Vai trò |
|----------------|---------|
| [fog-gateway/](file:///Users/nguyenbao/stormsmarthome2/fog-gateway) | Mã nguồn Java của Gateway biên, bao gồm mosquitto MQTT local, SQLite queue và Dockerfile build gateway. |
| [fog-cloud/](file:///Users/nguyenbao/stormsmarthome2/fog-cloud) | Mã nguồn Java của Cloud topology (`Spout_aggregated` & `Bolt_cloudMerge`) và Dockerfile cho Storm. |
| [cloud/webapp/](file:///Users/nguyenbao/stormsmarthome2/cloud/webapp) | API Node.js và giao diện Web Dashboard (`iot-data-api`) chạy ở cổng 9000 trên Cloud. |
| [fog-monitoring/](file:///Users/nguyenbao/stormsmarthome2/fog-monitoring) | Cấu hình Prometheus + Grafana cục bộ để giám sát hiệu năng các Gateway và Cloud. |
| [infrastructure/](file:///Users/nguyenbao/stormsmarthome2/infrastructure) | Mã nguồn Terraform dựng hạ tầng AWS EC2 cho Cloud (t3.large) + kịch bản script set IP/khởi chạy. |
| [tools/](file:///Users/nguyenbao/stormsmarthome2/tools) | Các script phục vụ tự động hóa đo đạc, tạo manifesto, tổng hợp dữ liệu và sinh báo cáo trễ. |
| [demo.sh](file:///Users/nguyenbao/stormsmarthome2/demo.sh) | Script Menu tương tác giúp điều khiển & demo toàn bộ hệ thống local nhanh chóng. |
| [run_alerts_test.sh](file:///Users/nguyenbao/stormsmarthome2/run_alerts_test.sh) | Script kiểm tra nhanh tính năng anomaly detection và gửi webhook alert ra Slack. |

---

## 📄 Tài liệu Hướng dẫn

- **[DO_DAC.md](file:///Users/nguyenbao/stormsmarthome2/DO_DAC.md)**: Hướng dẫn quy trình đo đạc nghiêm ngặt (chạy các kịch bản KB1a, KB1b, KB2a, KB2b, đánh giá Anomaly và đo đạc Latency tách biệt).
- **[docs/REMEASURE_PLAN.md](file:///Users/nguyenbao/stormsmarthome2/docs/REMEASURE_PLAN.md)**: Kế hoạch và lý do thực hiện đo lại hệ thống.
- **[docs/METRICS_EXPLANATION.md](file:///Users/nguyenbao/stormsmarthome2/docs/METRICS_EXPLANATION.md)**: Giải thích chi tiết các chỉ số đo lường hiệu năng (Latency, Throughput, Capacity, Outage Queue).
- **[PROMPTS.md](file:///Users/nguyenbao/stormsmarthome2/PROMPTS.md)**: Các prompt hướng dẫn đo đạc và tự động thu thập số liệu.
