#!/usr/bin/env bash
# ============================================================================
# LATENCY REPORT — độ trễ END-TO-END (produced → ghi DB) cho cả mono và fog.
#
# Đây là metric trả lời "fog có thực sự nhanh hơn end-to-end không" — KHÁC với
# 'cloud được giảm tải' (hiển nhiên). Đọc cột event_ts (epoch-ms lúc cảm biến
# phát) đã được cắm vào DB, trừ với thời điểm ghi để ra độ tươi mỗi bản ghi.
#
#   mono : device_data       latency = UNIX_TIMESTAMP(reg_date)*1000 - event_ts
#   fog  : fog_device_data    latency = updatedAt - event_ts
#
# Dùng (chạy từ máy local, query DB trong container mysql trên EC2 qua SSH):
#   MODE=mono SSH_TARGET=ec2-user@<mono-ip>  KEY=~/Downloads/mono.pem ./tools/latency_report.sh
#   MODE=fog  SSH_TARGET=ec2-user@<fog-ip>   KEY=~/.ssh/<fog>.pem     ./tools/latency_report.sh
# Env phụ: DB_USER DB_PASS DB_NAME MYSQL_CONTAINER WINDOW(=slice_gap, để trống = mọi window)
#          LABEL (tên file ra), OUT_DIR (mặc định results)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:?Cần MODE=mono hoặc MODE=fog}"
SSH_TARGET="${SSH_TARGET:?Cần SSH_TARGET=ec2-user@<ip>}"
KEY="${KEY:?Cần KEY=đường-dẫn-.pem}"
OUT_DIR="${OUT_DIR:-results}"
WINDOW="${WINDOW:-}"
mkdir -p "$OUT_DIR"

case "$MODE" in
  mono)
    DB_USER="${DB_USER:-user1}"; DB_PASS="${DB_PASS:-Uet123}"; DB_NAME="${DB_NAME:-iotdata}"
    MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
    TABLE="device_data"; WRITE_MS="UNIX_TIMESTAMP(reg_date)*1000"; GAPCOL="slice_gap";;
  fog)
    DB_USER="${DB_USER:-user1}"; DB_PASS="${DB_PASS:-Uet123}"; DB_NAME="${DB_NAME:-iotdata_fog}"
    MYSQL_CONTAINER="${MYSQL_CONTAINER:-cloud-mysql}"
    TABLE="fog_device_data"; WRITE_MS="updatedAt"; GAPCOL="sliceGap";;
  *) echo "MODE phải là mono hoặc fog"; exit 1;;
esac

WHERE="event_ts > 0"
[[ -n "$WINDOW" ]] && WHERE="$WHERE AND $GAPCOL = $WINDOW"
# loại bản ghi lệch đồng hồ (âm) và outlier > 1h (chỉ giữ độ trễ hợp lệ)
SQL="SELECT ($WRITE_MS - event_ts) AS lat FROM $TABLE WHERE $WHERE HAVING lat BETWEEN 0 AND 3600000;"

LABEL="${LABEL:-$MODE}"
OUT="$OUT_DIR/latency_${LABEL}_$(date +%Y%m%d-%H%M%S).csv"

echo "[latency] MODE=$MODE table=$TABLE window=${WINDOW:-ALL} → query qua $SSH_TARGET ..."
RAW=$(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$SSH_TARGET" \
  "docker exec $MYSQL_CONTAINER mysql -u'$DB_USER' -p'$DB_PASS' '$DB_NAME' -N -B -e \"$SQL\"" 2>/dev/null) || {
    echo "[latency] LỖI: không query được DB. Kiểm tra SSH/KEY/creds/container."; exit 1; }

# Viết Python script ra file tạm để tránh stdin conflict giữa pipe và heredoc
_PY=$(mktemp /tmp/lat_report.XXXXX.py)
cat > "$_PY" <<'PY'
import sys
mode,label,window,out = sys.argv[1:5]
vals=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: vals.append(float(line))
    except ValueError: pass
if not vals:
    print("[latency] KHÔNG có bản ghi hợp lệ (event_ts chưa được cắm? hoặc chưa chạy đủ).")
    sys.exit(0)
vals.sort()
n=len(vals)
def pct(p):
    if n==1: return vals[0]
    k=(n-1)*p/100.0; f=int(k); c=min(f+1,n-1)
    return vals[f]+(vals[c]-vals[f])*(k-f)
mean=sum(vals)/n
rows=[("mode",mode),("window",window),("samples",n),
      ("mean_ms",round(mean,1)),("p50_ms",round(pct(50),1)),
      ("p95_ms",round(pct(95),1)),("p99_ms",round(pct(99),1)),
      ("max_ms",round(vals[-1],1)),("min_ms",round(vals[0],1))]
with open(out,"w") as f:
    f.write("metric,value\n")
    for k,v in rows: f.write(f"{k},{v}\n")
print(f"── ĐỘ TRỄ END-TO-END ({label}, window={window}) ──")
for k,v in rows: print(f"  {k:<10} {v}")
print(f"[latency] Đã lưu: {out}")
PY
echo "$RAW" | python3 "$_PY" "$MODE" "$LABEL" "${WINDOW:-ALL}" "$OUT"
rm -f "$_PY"
