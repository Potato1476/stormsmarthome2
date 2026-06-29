#!/usr/bin/env bash
# ============================================================================
# CLEAN MEASUREMENTS — dọn sạch dữ liệu/ảnh/log của các lần đo TRƯỚC để đo lại
# từ đầu, rồi tạo CẤU TRÚC THƯ MỤC SẠCH cho phiên đo mới (5 lần).
#
# An toàn: mặc định KHÔNG xoá hẳn mà ARCHIVE (di chuyển) sang
#   results/_archive_pre_remeasure_<timestamp>/  → có thể xoá sau khi yên tâm.
# Dùng PURGE=1 ./tools/clean_measurements.sh để xoá hẳn (không archive).
#
# GIỮ LẠI: code, scripts, docs (REPORT/ANALYSIS/README), results/paper/.
# DỌN: results/{kb*,img,sim_*,*_simstats.log,kb2_*.md,*.log,*.pdf} + images/{fog,mono}.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

TS=$(date +%Y%m%d-%H%M%S)
ARCH="results/_archive_pre_remeasure_$TS"
PURGE="${PURGE:-0}"

move() {  # move() <path...> → archive hoặc xoá
  for p in "$@"; do
    [ -e "$p" ] || continue
    if [ "$PURGE" = 1 ]; then rm -rf "$p"; echo "  xoá   $p";
    else mkdir -p "$ARCH"; mv "$p" "$ARCH/" 2>/dev/null && echo "  → arch $p" || true; fi
  done
}

echo "[clean] Dọn dữ liệu đo cũ (PURGE=$PURGE)..."
# 1) Thư mục + file kết quả đo cũ
move results/kb1-A-multi8gw results/kb1-B-single results/kb2-A-multi8gw results/kb2-B-single
move results/img
move results/sim_*.csv results/sim_stats_*.csv results/*_simstats.log results/kb2_*.md
move results/energy_optimization.log results/test_optimizer_daemon.log results/report_fog_vs_mono.pdf
move results/.DS_Store
# 2) Ảnh Grafana cũ đã ghép vào báo cáo (giữ logo/slack nếu nằm chỗ khác)
[ -d images/fog ]  && { mkdir -p "$ARCH/images"; move images/fog;  }
[ -d images/mono ] && { mkdir -p "$ARCH/images"; move images/mono; }
# 3) Lần đo trước trong results/remeasure (nếu có) — dọn để đo lại sạch
move results/remeasure

echo "[clean] Tạo cấu trúc SẠCH cho phiên đo mới..."
for d in kb1a kb1b kb2a kb2b anomaly; do
  mkdir -p "results/remeasure/$d/img"
  : > "results/remeasure/$d/.gitkeep"; : > "results/remeasure/$d/img/.gitkeep"
done
# Thư mục ảnh báo cáo (để re-stage ảnh mới sau khi đo)
for d in images/mono images/fog/kb1a images/fog/kb1b images/fog/kb2a images/fog/kb2b; do
  mkdir -p "$d"; : > "$d/.gitkeep"
done

cat > results/remeasure/README.md <<'MD'
# results/remeasure — kết quả đo LẠI (nghiêm ngặt)

CHÍNH SÁCH:
- **Số liệu**: chạy MỖI kịch bản **5 lần** (RUN_ID=1..5) → gộp mean±std bằng
  `tools/agg_runs.py mean <dir> <fog|mono>`. KHÔNG loại lần "xấu".
- **Ảnh (Grafana)**: CHỈ chụp **1 lần / kịch bản**, ở **run đại diện** (run có số
  gần median nhất — xem summary; đơn giản chọn RUN_ID=3). Ảnh chỉ để MINH HOẠ;
  số liệu chuẩn lấy từ CSV của cả 5 lần.

THƯ MỤC (Fog):
- `kb1a/`  — 8 gateway ramp (ts_*, summary_*, run1..5);  ảnh → `kb1a/img/`
- `kb1b/`  — 1 gateway ramp;                              ảnh → `kb1b/img/`
- `kb2a/`  — 8 gateway recovery (run1..3 + long);          ảnh → `kb2a/img/`
- `kb2b/`  — 1 gateway recovery;                           ảnh → `kb2b/img/`
- `anomaly/` — anomaly_gt.json, alerts.log, điểm precision/recall

PANEL CẦN CHỤP (ảnh, ở run đại diện):
- kb1a: Cloud Bolt Capacity · All Gateways Capacity · Gateway Ingestion Rate ·
        Gateway Exec Latency · Summary panel
- kb1b: Cloud Bolt Capacity · Summary panel · Gateway Exec Latency
- kb2a/kb2b: Store-Forward Queue Depth · Summary (lúc outage) · Summary (lúc recovery)
MD

echo "════════════════════════════════════════════════════════════════"
echo " ✅ ĐÃ DỌN. Dữ liệu cũ: ${ARCH:-'(đã purge)'}"
echo " 📂 Cấu trúc mới: results/remeasure/{kb1a,kb1b,kb2a,kb2b,anomaly}/img"
echo " 🖼  Ảnh báo cáo (re-stage sau đo): images/{mono,fog/kb1a,kb1b,kb2a,kb2b}"
[ "$PURGE" != 1 ] && echo " ♻️  Yên tâm rồi thì xoá archive:  rm -rf $ARCH"
echo "════════════════════════════════════════════════════════════════"
