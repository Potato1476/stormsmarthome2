#!/usr/bin/env bash
# ============================================================================
# VERIFY WINDOWS — kiểm chứng TÍNH ĐÚNG của cửa sổ tổng hợp + idempotency
# (prompt §2.6 + §2.3). Bơm một chuỗi giá trị ĐÃ BIẾT rồi SELECT lại để so.
#
# Cách làm:
#   1. Bơm N reading value=V cho 1 device (house/hh/plug) TRONG CÙNG 1 giây
#      ⇒ tất cả rơi vào CÙNG slice của MỌI cửa sổ ⇒ kỳ vọng count=N, avg=V.
#   2. Chờ flush (≥FLUSH_SEC) + cloud merge, rồi query fog_device_data.
#   3. So sánh từng cửa sổ (sliceGap ∈ 1,5,10,15,30) với count=N, avg=V.
#   4. Idempotency: COUNT(*) − COUNT(DISTINCT pk) PHẢI = 0 (không dòng trùng).
#
# Dùng (8GW đang chạy: house 1 ⇒ gw-01):
#   CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/verify_windows.sh
# Env: HOUSE=1 HOUSEHOLD=0 PLUG=0 VALUE=100 N=60 FLUSH_SEC=60 WAIT=180
#      LOCAL_MQTT_CONTAINER=local-mqtt  CLOUD_MYSQL=cloud-mysql DB=iotdata_fog
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP}"; KEY="${KEY:?Cần KEY=.pem}"
HOUSE="${HOUSE:-1}"; HOUSEHOLD="${HOUSEHOLD:-0}"; PLUG="${PLUG:-0}"
VALUE="${VALUE:-100}"; N="${N:-60}"
FLUSH_SEC="${FLUSH_SEC:-60}"; WAIT="${WAIT:-180}"
LOCAL_MQTT_CONTAINER="${LOCAL_MQTT_CONTAINER:-local-mqtt}"
CLOUD_MYSQL="${CLOUD_MYSQL:-cloud-mysql}"; DB="${DB:-iotdata_fog}"
DB_USER="${DB_USER:-user1}"; DB_PASS="${DB_PASS:-Uet123}"
TOPIC="${TOPIC:-iot-data}"
WINDOWS="${WINDOWS:-1 5 10 15 30}"

TS=$(date +%s)   # cùng 1 giây cho cả N reading ⇒ cùng slice
echo "[verify] Bơm $N reading value=$VALUE → house=$HOUSE hh=$HOUSEHOLD plug=$PLUG ts=$TS topic=$TOPIC"
# format: _,timestamp,value,property,plugId,householdId,houseId   (property=1 = load)
for i in $(seq 1 "$N"); do
  MSG="0,$TS,$VALUE,1,$PLUG,$HOUSEHOLD,$HOUSE"
  docker exec "$LOCAL_MQTT_CONTAINER" mosquitto_pub -h localhost -p 1883 -t "$TOPIC" -m "$MSG" -q 1
done
echo "[verify] Đã bơm. Chờ flush+merge (~$WAIT s)..."
sleep "$WAIT"

q() { ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 ec2-user@"$CLOUD_IP" \
        "docker exec $CLOUD_MYSQL mysql -u'$DB_USER' -p'$DB_PASS' '$DB' -N -B -e \"$1\"" 2>/dev/null; }

PASS=1
echo "──────────────────────────────────────────────────────────────"
printf "%-8s %-8s %-12s %-10s %-8s\n" "window" "count" "sum" "avg" "verdict"
for W in $WINDOWS; do
  ROW=$(q "SELECT COALESCE(SUM(count),0), COALESCE(SUM(sumValue),0) FROM fog_device_data \
           WHERE houseId=$HOUSE AND householdId=$HOUSEHOLD AND deviceId=$PLUG AND sliceGap=$W;")
  CNT=$(echo "$ROW" | awk '{print $1}'); SUM=$(echo "$ROW" | awk '{print $2}')
  AVG=$(python3 -c "c=float('${CNT:-0}' or 0); print(round(float('${SUM:-0}')/c,2) if c else 'nan')")
  EXP_SUM=$(python3 -c "print($N*$VALUE)")
  V="✅"; python3 -c "import sys; sys.exit(0 if abs(float('$AVG')-$VALUE)<0.01 and abs(float('${CNT:-0}')-$N)<0.5 else 1)" || { V="❌"; PASS=0; }
  printf "%-8s %-8s %-12s %-10s %-8s\n" "$W" "$CNT" "$SUM" "$AVG" "$V"
done
echo "──────────────────────────────────────────────────────────────"
echo "  (kỳ vọng mỗi cửa sổ: count=$N, sum=$((N*VALUE)), avg=$VALUE)"

# Idempotency: không được có dòng trùng PRIMARY KEY
DUP=$(q "SELECT COUNT(*) - COUNT(DISTINCT houseId,householdId,deviceId,year,month,day,sliceIndex,sliceGap) FROM fog_device_data;")
echo "[verify] Dòng trùng PK (phải = 0): ${DUP:-?}"
[[ "${DUP:-1}" == "0" ]] || PASS=0

if [[ "$PASS" == 1 ]]; then echo "✅ VERIFY WINDOWS PASS (cửa sổ đúng + idempotent)";
else echo "❌ VERIFY WINDOWS FAIL — xem bảng trên"; exit 1; fi
