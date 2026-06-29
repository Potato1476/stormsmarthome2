# Run Manifest — Đo lại Fog vs Monolithic

> Bằng chứng tái lập (prompt §7). Sinh tự động bởi `tools/gen_manifest.sh`.

| Mục | Giá trị |
|---|---|
| Ngày đo | 2026-06-29 14:05:04 +07 |
| Git commit | `fc8edba` (DIRTY (có thay đổi chưa commit)) |
| JDK (build) | openjdk version 11.0.27 2025-04-15 |
| Seed dataset | 42 |
| Số lần lặp / kịch bản | 5 (KB1), 3 + 1 long (KB2) |

## Phiên bản phần mềm (từ docker-compose)
| Thành phần | Image |
|---|---|
| Apache Storm | storm:2.1.0 |
| MySQL | mysql:8.4.2 |
| Mosquitto | eclipse-mosquitto:2.0 |
| Zookeeper | zookeeper:3.8.5 |
| Prometheus | prom/prometheus:v2.53.1 |
| Grafana | grafana/grafana:11.1.0 |
| Storm exporter | mr4x2/stormexporter:v1.2.2 |

## Workload parity (prompt §2.1) — đối chiếu với log khởi động cloud
- Windows: `[1,5,10,15,30,60,120]` (gateway tạo 1..30, cloud suy ra 60,120)
- Forecast: `FORECAST_ENABLED=true` (parity với Bolt_forecast của Mono)
- CloudMerge mode: `CLOUDMERGE_MODE=batched` (đo thêm `perrow` cho so sánh §6.3)
- Kiểm chứng: `docker logs cloud-topo-submit | grep WORKLOAD`

## Hạ tầng
- Xem `results/remeasure/hardware_matrix.csv` (điền instance EC2 thật, KHÔNG ép cân bằng).

## Cấu hình song song (chống "strawman baseline", prompt §2.4)
- Xem `results/remeasure/parallelism_*.csv` (sinh bằng `tools/gen_parallelism.sh`).

## Chính sách outlier (prompt §5.3)
- KHÔNG loại run thầm lặng. Chỉ loại khi có lỗi hạ tầng ghi nhận được. Liệt kê:

| run bị loại | kịch bản | lý do |
|---|---|---|
| (chưa có) | | |

## Ghi chú đo
- (điền) instance EC2 mono/fog, ngày, người đo, bất thường quan sát.
