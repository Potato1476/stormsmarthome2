#!/usr/bin/env bash
# ============================================================================
# GEN MANIFEST — sinh run_manifest.md (bằng chứng tái lập cho hội đồng, prompt §7).
# Tự bắt: git commit, ngày đo, phiên bản phần mềm (từ docker-compose), JDK.
# Để TRỐNG (điền tay): seed dataset, instance EC2, số run bị loại + lý do.
#
# Dùng:  SEED=42 ./tools/gen_manifest.sh   (hoặc bỏ SEED, điền sau)
# Ra:    results/remeasure/run_manifest.md
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${OUT:-results/remeasure/run_manifest.md}"
SEED="${SEED:-<ĐIỀN_SEED>}"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
COMMIT_DIRTY=$(git diff --quiet 2>/dev/null && echo "clean" || echo "DIRTY (có thay đổi chưa commit)")
DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
JDK=$(java -version 2>&1 | head -1 | tr -d '"')

ver() { grep -hoE "$1:[v0-9][^\"' ]*" docker-compose.cloud.yml docker-compose.gateway.yml 2>/dev/null | head -1; }

cat > "$OUT" <<MD
# Run Manifest — Đo lại Fog vs Monolithic

> Bằng chứng tái lập (prompt §7). Sinh tự động bởi \`tools/gen_manifest.sh\`.

| Mục | Giá trị |
|---|---|
| Ngày đo | $DATE |
| Git commit | \`$COMMIT\` ($COMMIT_DIRTY) |
| JDK (build) | $JDK |
| Seed dataset | $SEED |
| Số lần lặp / kịch bản | 5 (KB1), 3 + 1 long (KB2) |

## Phiên bản phần mềm (từ docker-compose)
| Thành phần | Image |
|---|---|
| Apache Storm | $(ver storm) |
| MySQL | $(ver mysql) |
| Mosquitto | $(ver eclipse-mosquitto) |
| Zookeeper | $(ver zookeeper) |
| Prometheus | $(ver prom/prometheus) |
| Grafana | $(ver grafana/grafana) |
| Storm exporter | $(ver mr4x2/stormexporter) |

## Workload parity (prompt §2.1) — đối chiếu với log khởi động cloud
- Windows: \`[1,5,10,15,30,60,120]\` (gateway tạo 1..30, cloud suy ra 60,120)
- Forecast: \`FORECAST_ENABLED=true\` (parity với Bolt_forecast của Mono)
- CloudMerge mode: \`CLOUDMERGE_MODE=batched\` (đo thêm \`perrow\` cho so sánh §6.3)
- Kiểm chứng: \`docker logs cloud-topo-submit | grep WORKLOAD\`

## Hạ tầng
- Xem \`results/remeasure/hardware_matrix.csv\` (điền instance EC2 thật, KHÔNG ép cân bằng).

## Cấu hình song song (chống "strawman baseline", prompt §2.4)
- Xem \`results/remeasure/parallelism_*.csv\` (sinh bằng \`tools/gen_parallelism.sh\`).

## Chính sách outlier (prompt §5.3)
- KHÔNG loại run thầm lặng. Chỉ loại khi có lỗi hạ tầng ghi nhận được. Liệt kê:

| run bị loại | kịch bản | lý do |
|---|---|---|
| (chưa có) | | |

## Ghi chú đo
- (điền) instance EC2 mono/fog, ngày, người đo, bất thường quan sát.
MD

echo "✅ Đã ghi $OUT  (nhớ điền SEED, instance EC2, run bị loại)"
