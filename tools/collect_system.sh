#!/usr/bin/env bash
# ============================================================================
# Snapshot TÀI NGUYÊN HỆ THỐNG (CPU%, RAM, NET I/O) của các container Docker —
# để trả lời câu hỏi TỔNG THỂ mà collect_metrics.sh (chỉ app-level) không đo:
#   - Fog "đẻ thêm" bao nhiêu CPU thật (Σ 8 gateway)
#   - Lưu lượng WAN thật (NET I/O của broker nhận raw/agg)
#
# docker stats cho NET I/O là TÍCH LŨY theo đời container → chạy script này
# 2 LẦN: ngay sau warmup (T0) và ở phút thứ 30 (T30), rồi LẤY HIỆU để ra
# bytes/30phút. CPU%/MEM là tức thời → đọc trực tiếp ở T30.
#
# Dùng:
#   # Fog gateways (chạy local trên laptop):
#   ./tools/collect_system.sh fog-gw-t0
#   ./tools/collect_system.sh fog-gw-t30
#
#   # Fog cloud hoặc Monolithic (qua SSH vào EC2):
#   SSH_TARGET=ec2-user@<ip> KEY=~/.ssh/<key>.pem ./tools/collect_system.sh mono-t0
#   SSH_TARGET=ec2-user@<ip> KEY=~/.ssh/<key>.pem ./tools/collect_system.sh mono-t30
# ============================================================================
set -euo pipefail

LABEL="${1:-sys}"
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/system_${LABEL}_$(date +%Y%m%d-%H%M%S).csv"

FMT='{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}'

if [[ -n "${SSH_TARGET:-}" ]]; then
  KEY="${KEY:?Cần KEY=*.pem khi dùng SSH_TARGET}"
  STATS="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" "$SSH_TARGET" \
            "docker stats --no-stream --format '$FMT'")"
else
  STATS="$(docker stats --no-stream --format "$FMT")"
fi

echo "container,cpu_perc,mem_usage,net_io,block_io" > "$OUT"
echo "$STATS" >> "$OUT"

# Tổng CPU% (cộng dồn tất cả container)
TOTAL_CPU="$(echo "$STATS" | awk -F',' '{gsub(/%/,"",$2); s+=$2} END{printf "%.1f", s}')"
echo "TOTAL_CPU_PERCENT,$TOTAL_CPU,,," >> "$OUT"

echo "── System snapshot (${LABEL}) ──"
column -s, -t "$OUT"
echo "[collect_system] Σ CPU = ${TOTAL_CPU}%  |  Đã lưu: $OUT"
echo "[collect_system] WAN: lấy cột net_io của container broker ở T30 TRỪ T0 = bytes/30phút."
