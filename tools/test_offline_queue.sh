#!/usr/bin/env bash
# ============================================================================
# CƠ CHẾ KIỂM TRA HÀNG ĐỢI / MẤT MẠNG (góp ý của giáo sư: "có hàng đợi khi
# mất mạng là tốt, nhưng chưa có cơ chế kiểm tra cho nó")
#
# Kịch bản: trong lúc publisher đang gửi dữ liệu đều đặn, CẮT liên lạc
# gateway ↔ cloud trong OUTAGE_SEC giây rồi khôi phục, và đo 3 thứ:
#
#   (1) TÍNH LIÊN TỤC CỤC BỘ: trong lúc mất mạng, gateway VẪN phát cảnh báo
#       thiết bị tức thì cho hộ gia đình (đếm message trên topic
#       iot-notification của broker LOCAL phía gateway).
#   (2) KHÔNG MẤT DỮ LIỆU: sau khi khôi phục, đếm số dòng các bảng MySQL
#       (device_data / house_data / household_data) và kiểm tra dãy
#       slice_index của cửa sổ 1 phút KHÔNG BỊ LỖ HỔNG quanh khoảng mất mạng.
#       (DB dùng INSERT ... ON DUPLICATE KEY UPDATE → việc gửi lại an toàn.)
#   (3) HÀNG ĐỢI XẢ HẾT (chỉ kiến trúc v2): metric fog_gateway_store_queue_size
#       tăng lên trong outage và xả về 0 sau khi khôi phục.
#
# Cách dùng — kiến trúc FOG v1 (code thầy + tag, 2 EC2):
#   1. Đảm bảo topology đang chạy + publisher đang gửi (SPEED ổn định).
#   2. GATEWAY_IP=<ip> CLOUD_IP=<ip> KEY=~/.ssh/<key>.pem \
#        ./tools/test_offline_queue.sh
#
# Cách dùng — kiến trúc FOG v2 (fog-gateway local + fog-cloud EC2):
#   ARCH=v2 CLOUD_IP=<ip> KEY=~/.ssh/<key>.pem ./tools/test_offline_queue.sh
#
# Tham số (env): OUTAGE_SEC=90  GRACE_SEC=120  DB_NAME=iotdata
# Yêu cầu local: mosquitto_sub (brew install mosquitto) — nếu thiếu, bước (1)
# được bỏ qua với cảnh báo.
# ============================================================================
set -euo pipefail

ARCH="${ARCH:-v1}"
OUTAGE_SEC="${OUTAGE_SEC:-90}"
GRACE_SEC="${GRACE_SEC:-120}"
KEY="${KEY:?Cần KEY=~/.ssh/<key>.pem}"
CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP=<ip cloud EC2>}"
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/offline_queue_test_$(date +%Y%m%d-%H%M%S).md"

DB_NAME="${DB_NAME:-iotdata}"
DB_USER="${DB_USER:-user1}"
DB_PASS="${DB_PASS:-Uet123}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
[[ "$ARCH" == "v2" ]] && { DB_NAME="${DB_NAME_V2:-iotdata_fog}"; MYSQL_CONTAINER="cloud-mysql"; }

pass=0; fail=0
note() { echo "$*" | tee -a "$REPORT"; }
verdict() { # verdict <ok|bad> <text>
  if [[ "$1" == ok ]]; then pass=$((pass+1)); note "  ✅ PASS: $2";
  else fail=$((fail+1)); note "  ❌ FAIL: $2"; fi
}

sql() { # sql <query> — chạy trên container mysql của cloud qua SSH
  ssh "${SSH_OPTS[@]}" "ec2-user@$CLOUD_IP" \
    "docker exec $MYSQL_CONTAINER mysql -N -B -u$DB_USER -p$DB_PASS $DB_NAME -e \"$1\" 2>/dev/null"
}

db_counts() {
  sql "SELECT (SELECT COUNT(*) FROM device_data), (SELECT COUNT(*) FROM house_data), (SELECT COUNT(*) FROM household_data);" | tr '\t' ' '
}

note "# Kiểm tra hàng đợi khi mất mạng — $(date '+%Y-%m-%d %H:%M:%S')"
note ""
note "- Kiến trúc: **$ARCH** | Outage: ${OUTAGE_SEC}s | Grace sau khôi phục: ${GRACE_SEC}s"
note ""

# ── B1. Snapshot T0 ──────────────────────────────────────────────────────────
note "## B1. Snapshot trước khi cắt mạng (T0)"
T0_COUNTS=$(db_counts)
read -r T0_DEV T0_HOUSE T0_HH <<<"$T0_COUNTS"
T0_MAX_SLICE=$(sql "SELECT IFNULL(MAX(slice_index),-1) FROM device_data WHERE slice_gap=1;")
note "- device_data=$T0_DEV, house_data=$T0_HOUSE, household_data=$T0_HH, max slice_index(gap=1)=$T0_MAX_SLICE"

if [[ "$ARCH" == "v2" ]]; then
  Q0=$(curl -sf "http://localhost:9090/api/v1/query?query=sum(fog_gateway_store_queue_size)" | sed 's/.*"value":\[[^,]*,"\([0-9.]*\)".*/\1/' || echo "?")
  note "- store_queue_size(T0)=$Q0"
fi

# ── B2. Đếm cảnh báo local trong lúc mất mạng (chạy nền) ─────────────────────
ALERT_FILE=$(mktemp)
SUB_PID=""
if [[ "$ARCH" == "v1" ]]; then
  GATEWAY_IP="${GATEWAY_IP:?Cần GATEWAY_IP=<ip gateway EC2> cho v1}"
  if command -v mosquitto_sub >/dev/null; then
    mosquitto_sub -h "$GATEWAY_IP" -p 1883 -t "iot-notification" -v > "$ALERT_FILE" 2>/dev/null &
    SUB_PID=$!
    note ""
    note "## B2. Bắt đầu đếm cảnh báo trên broker LOCAL của gateway (topic iot-notification)"
  else
    note "- ⚠️ Không có mosquitto_sub → bỏ qua kiểm tra (1) cảnh báo local"
  fi
fi

# ── B3. Cắt mạng gateway ↔ cloud ─────────────────────────────────────────────
note ""
note "## B3. CẮT mạng gateway ↔ cloud trong ${OUTAGE_SEC}s"
if [[ "$ARCH" == "v1" ]]; then
  # Chặn 2 chiều với cloud ngay trên máy gateway (SSH từ laptop không ảnh hưởng)
  ssh "${SSH_OPTS[@]}" "ec2-user@$GATEWAY_IP" \
    "sudo iptables -I OUTPUT -d $CLOUD_IP -j DROP && sudo iptables -I INPUT -s $CLOUD_IP -j DROP"
  note "- Đã chặn iptables trên gateway lúc $(date '+%H:%M:%S')"
else
  # v2: dừng broker cloud → Bolt_ingest các gateway phải xếp hàng (store-and-forward)
  ssh "${SSH_OPTS[@]}" "ec2-user@$CLOUD_IP" "docker stop cloud-mqtt >/dev/null"
  note "- Đã dừng cloud-mqtt lúc $(date '+%H:%M:%S')"
fi

ALERTS_BEFORE=$(wc -l < "$ALERT_FILE" 2>/dev/null || echo 0)
sleep "$OUTAGE_SEC"
ALERTS_DURING=$(( $(wc -l < "$ALERT_FILE" 2>/dev/null || echo 0) - ALERTS_BEFORE ))

if [[ "$ARCH" == "v2" ]]; then
  QMID=$(curl -sf "http://localhost:9090/api/v1/query?query=sum(fog_gateway_store_queue_size)" | sed 's/.*"value":\[[^,]*,"\([0-9.]*\)".*/\1/' || echo "?")
  note "- store_queue_size(đang outage)=$QMID"
fi

# ── B4. Khôi phục mạng ───────────────────────────────────────────────────────
note ""
note "## B4. KHÔI PHỤC mạng, chờ ${GRACE_SEC}s cho hệ thống đuổi kịp"
if [[ "$ARCH" == "v1" ]]; then
  ssh "${SSH_OPTS[@]}" "ec2-user@$GATEWAY_IP" \
    "sudo iptables -D OUTPUT -d $CLOUD_IP -j DROP && sudo iptables -D INPUT -s $CLOUD_IP -j DROP"
else
  ssh "${SSH_OPTS[@]}" "ec2-user@$CLOUD_IP" "docker start cloud-mqtt >/dev/null"
fi
note "- Khôi phục lúc $(date '+%H:%M:%S')"
sleep "$GRACE_SEC"
[[ -n "$SUB_PID" ]] && kill "$SUB_PID" 2>/dev/null || true

# ── B5. Đánh giá ─────────────────────────────────────────────────────────────
note ""
note "## B5. Kết quả"
T1_COUNTS=$(db_counts)
read -r T1_DEV T1_HOUSE T1_HH <<<"$T1_COUNTS"
T1_MAX_SLICE=$(sql "SELECT IFNULL(MAX(slice_index),-1) FROM device_data WHERE slice_gap=1;")
note "- device_data: $T0_DEV → $T1_DEV | house_data: $T0_HOUSE → $T1_HOUSE | household_data: $T0_HH → $T1_HH"

# (1) Cảnh báo local trong outage
if [[ "$ARCH" == "v1" && -n "$SUB_PID" ]]; then
  note "- Cảnh báo nhận được trên broker local TRONG lúc mất mạng: $ALERTS_DURING"
  if (( ALERTS_DURING > 0 )); then
    verdict ok "Gateway vẫn phát cảnh báo tức thì khi mất kết nối cloud (fog locality)"
  else
    verdict bad "Không thấy cảnh báo local trong outage (kiểm tra ngưỡng notification.device.checkMax / dữ liệu publisher)"
  fi
fi

# (2) Dữ liệu tiếp tục chảy sau khôi phục
if (( T1_DEV > T0_DEV && T1_HOUSE > T0_HOUSE )); then
  verdict ok "Pipeline phục hồi: số dòng device_data và house_data tiếp tục tăng sau outage"
else
  verdict bad "Số dòng không tăng sau khôi phục (device $T0_DEV→$T1_DEV, house $T0_HOUSE→$T1_HOUSE)"
fi

# (2b) Lỗ hổng slice_index quanh khoảng outage (cửa sổ 1 phút, mức house —
# bảng này do sum-1 bên CLOUD ghi nên phản ánh đúng dữ liệu vượt WAN)
GAPS=$(sql "SELECT (MAX(slice_index)-MIN(slice_index)+1)-COUNT(DISTINCT slice_index) FROM house_data WHERE slice_gap=1 AND slice_index BETWEEN $T0_MAX_SLICE AND $T1_MAX_SLICE;")
note "- Lỗ hổng slice_index (house_data, gap=1, khoảng $T0_MAX_SLICE..$T1_MAX_SLICE): $GAPS"
if [[ "$GAPS" == "0" ]]; then
  verdict ok "Không mất cửa sổ dữ liệu nào quanh khoảng mất mạng"
else
  verdict bad "Thiếu $GAPS slice — dữ liệu vượt WAN trong outage bị mất (ghi nhận vào báo cáo: đây chính là phần hàng đợi phải bù)"
fi

# (3) v2: hàng đợi xả hết
if [[ "$ARCH" == "v2" ]]; then
  Q1=$(curl -sf "http://localhost:9090/api/v1/query?query=sum(fog_gateway_store_queue_size)" | sed 's/.*"value":\[[^,]*,"\([0-9.]*\)".*/\1/' || echo "?")
  note "- store_queue_size(T1)=$Q1 (T0=$Q0, trong outage=$QMID)"
  if [[ "$Q1" == "0" ]]; then
    verdict ok "Hàng đợi store-and-forward đã xả hết về 0 sau khôi phục"
  else
    verdict bad "Hàng đợi còn $Q1 message sau ${GRACE_SEC}s"
  fi
fi

note ""
note "## Tổng kết: $pass PASS / $fail FAIL — báo cáo lưu tại $REPORT"
rm -f "$ALERT_FILE"
exit $(( fail > 0 ? 1 : 0 ))
