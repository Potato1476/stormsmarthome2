# Fog Computing Smart Home IoT — Apache Storm

Hệ thống xử lý dữ liệu IoT nhà thông minh theo mô hình **Fog Computing 2 tầng**,
dùng **nguyên topology gốc** (`Spout_data → Bolt_split → Bolt_avg → Bolt_sum →
Bolt_forecast`) và **chia tải bằng TagAwareScheduler** — một Storm cluster duy
nhất trải trên 2 máy, bolt nào gắn `tags=cloud` thì chạy ở Cloud, còn lại chạy
ở Gateway. Không bolt nào bị sửa hay gộp.

- **Gateway (Edge, ~Raspberry Pi 3)** — việc nhẹ: nhận dữ liệu thô từ broker
  MQTT local, `split-*` + `avg-*`, phát **cảnh báo thiết bị tức thì** cho hộ
  gia đình qua broker local (không phụ thuộc WAN).
- **Cloud (AWS EC2)** — việc nặng: `sum-*` (tổng hợp house/household),
  `forecast-*` (dự báo, query DB), MySQL, Storm Nimbus/UI/exporter.

```
[Publisher] ─MQTT─▶ mqtt-broker ─▶ supervisor1 (GW, untagged)     ─Storm/WAN─▶ supervisor2 (tags=cloud)
                    (local, raw)    spout, split-*, avg-*                       sum-*, forecast-* → MySQL
                         ▲                │                                     (+ nimbus, ZK, exporter)
              cảnh báo tức thì ◀──────────┘
              cho hộ gia đình
```

## Tài liệu

| File | Nội dung |
|---|---|
| **[PROMPTS.md](PROMPTS.md)** | ⭐ Prompt sẵn-dán vào Claude Code (VS Code): mỗi kịch bản 1 ô, Claude tự dựng + đo + xuất ảnh, bạn chỉ bắn data ở `iot-data-publisher` |
| **[KICH_BAN_THI_NGHIEM.md](KICH_BAN_THI_NGHIEM.md)** | Chi tiết kịch bản + cách đọc số liệu: scalability ramp, Cloud Offline→Recovery, 2 môi trường giả lập (8 gateway phân tán vs 1 gateway) |
| **[PHAN_CHIA_BOLT.md](PHAN_CHIA_BOLT.md)** | Bolt nào ở gateway / cloud, lý do, cách tinh chỉnh tag (`--cloudbolts`) |
| **[RUNBOOK_FOG_V1.md](RUNBOOK_FOG_V1.md)** | Triển khai 2 EC2, nộp topology, đo lường, test mất mạng |
| **[PI3_KHA_THI.md](PI3_KHA_THI.md)** | Phân tích + kịch bản đo trên Raspberry Pi 3 thật |
| [KICH_BAN_DO_LUONG.md](KICH_BAN_DO_LUONG.md) | Kịch bản so sánh với Monolithic |

## Thành phần chính

| Thành phần | Vai trò |
|------------|---------|
| `gateway/` | **Code topology gốc của thầy** + TagAwareScheduler + compose tầng Gateway |
| `cloud/` | Compose tầng Cloud (ZK, Nimbus+scheduler, supervisor2 `tags=cloud`, MySQL, exporter) |
| `tools/test_offline_queue.sh` | **Cơ chế kiểm tra hàng đợi khi mất mạng** (cắt mạng có kiểm soát → đo cảnh báo local + toàn vẹn dữ liệu) |
| `infrastructure/` | Terraform: 2 EC2 (gateway t3.small + cloud t3.large), EIP tĩnh, SG mở port Storm giữa 2 máy |
| `monitoring/` | Prometheus + Grafana (chạy local, scrape exporter Cloud) |
| `fog-gateway/`, `fog-cloud/` | Kiến trúc v2 cũ (gateway tự tổng hợp, gửi MQTT + hàng đợi store-and-forward) — giữ lại để tham khảo/so sánh |

## Thay đổi so với code gốc

Đúng một chỗ: `MainTopo.java` nhận option `-c/--cloudbolts` (mặc định
`sum,forecast` — y hệt hard-code cũ) để thử các phương án phân chia bolt mà
không cần rebuild. Toàn bộ phần còn lại là cấu hình triển khai.
