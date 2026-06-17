#!/usr/bin/env bash
# ============================================================================
# Lấy CPU / RAM các container gateway GIẢ LẬP (chạy local trên laptop) theo
# thời gian — cho thí nghiệm giả lập môi trường A (8 gw) và B (1 gw).
#
# Mỗi container bị giới hạn 1GB/1vCPU (giả lập 1 thiết bị biên Pi-class), nên
# docker stats CPUPerc ~100% = 1 vCPU của "thiết bị" đó bão hoà.
#
# Dùng (song song lúc bắn data):
#   ./tools/collect_sim_stats.sh <label> [duration_s] [interval_s]
#
# CSV: results/sim_stats_<label>.csv
#   epoch, gw_count, cpu_sum_pct, cpu_max_pct, mem_sum_mb, mem_max_mb
# In trung bình + đỉnh ở cuối (cpu_max/mem_max = "thiết bị biên bận nhất").
# ============================================================================
set -euo pipefail

LABEL="${1:?Dùng: $0 <label> [duration_s] [interval_s]}"
DURATION="${2:-900}"
INTERVAL="${3:-10}"
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/sim_stats_${LABEL}.csv"

echo "Theo dõi container gw-* mỗi ${INTERVAL}s trong ${DURATION}s → $OUT"
echo "epoch,gw_count,cpu_sum_pct,cpu_max_pct,mem_sum_mb,mem_max_mb" > "$OUT"

END=$(( $(date +%s) + DURATION ))
while (( $(date +%s) < END )); do
  LINE=$(docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' 2>/dev/null \
    | grep -E '^gw-' \
    | awk -F, '
        { gsub(/%/,"",$2); cs+=$2; if($2>cm)cm=$2;
          split($3,a," "); v=a[1]; u=a[1];
          gsub(/[0-9.]/,"",u); gsub(/[A-Za-z]/,"",v);
          if(u ~ /GiB|GB/) v=v*1024; ms+=v; if(v>mm)mm=v; n++ }
        END{ printf "%d,%.1f,%.1f,%.0f,%.0f", n, cs, cm, ms, mm }')
  echo "$(date +%s),${LINE:-0,0,0,0,0}" >> "$OUT"
  printf '\r%s  gw=%s' "$(date '+%H:%M:%S')" "${LINE%%,*}"
  sleep "$INTERVAL"
done
echo ""

python3 - "$OUT" <<'PY'
import csv,sys
rows=[r for r in csv.DictReader(open(sys.argv[1])) if r['gw_count'] and int(r['gw_count'])>0]
if not rows: print("Không có mẫu container gw-*."); sys.exit()
def col(k): return [float(r[k]) for r in rows]
cmax=col('cpu_max_pct'); mmax=col('mem_max_mb'); msum=col('mem_sum_mb'); n=int(rows[-1]['gw_count'])
print(f"  Số gateway     : {n}")
print(f"  CPU/1 gw bận nhất : trung bình {sum(cmax)/len(cmax):.1f}%  | đỉnh {max(cmax):.1f}%  (≈100% = bão hoà 1 vCPU)")
print(f"  RAM/1 gw bận nhất : trung bình {sum(mmax)/len(mmax):.0f} MB | đỉnh {max(mmax):.0f} MB")
print(f"  RAM tổng {n} gw    : trung bình {sum(msum)/len(msum):.0f} MB | đỉnh {max(msum):.0f} MB")
print(f"  → điền bảng: CPU={sum(cmax)/len(cmax):.0f}%  RAM={sum(mmax)/len(mmax):.0f}MB (mỗi thiết bị biên)")
PY
echo "CSV: $OUT"
