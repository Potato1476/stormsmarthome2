#!/usr/bin/env bash
# ============================================================================
# GEN PARALLELISM — xuất parallelism.csv cho MỘT topology từ Storm UI REST API
# (chống cáo buộc "strawman baseline" — prompt §2.4).
#
# Cột: component, parallelism (num_executors), num_tasks, emitted, transferred
# Lấy từ: <STORM_UI>/api/v1/topology/summary  → tìm id theo tên → /topology/<id>
#
# Dùng:
#   STORM_UI=http://localhost:8080 TOPO=fog-cloud OUT=results/remeasure/parallelism_fog_cloud.csv \
#     ./tools/gen_parallelism.sh
#   # Cloud EC2 (qua SSH tunnel hoặc IP public nếu mở cổng 8080):
#   STORM_UI=http://52.74.153.60:8080 TOPO=fog-cloud ./tools/gen_parallelism.sh
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

STORM_UI="${STORM_UI:?Cần STORM_UI=http://host:8080}"
TOPO="${TOPO:?Cần TOPO=<tên topology>}"
OUT="${OUT:-results/remeasure/parallelism_${TOPO}.csv}"
mkdir -p "$(dirname "$OUT")"

ID=$(curl -s "$STORM_UI/api/v1/topology/summary" \
  | python3 -c "import sys,json
ts=json.load(sys.stdin).get('topologies',[])
m=[t for t in ts if t.get('name')=='$TOPO']
print(m[0]['id'] if m else '')")
[[ -z "$ID" ]] && { echo "❌ Không thấy topology '$TOPO' trên $STORM_UI"; exit 1; }

curl -s "$STORM_UI/api/v1/topology/$ID" | python3 -c "
import sys,json,csv
d=json.load(sys.stdin)
w=csv.writer(sys.stdout)
w.writerow(['topology','type','component','executors','tasks','emitted','transferred'])
rows=open('$OUT','w'); cw=csv.writer(rows)
cw.writerow(['topology','type','component','executors','tasks','emitted','transferred'])
for kind in ('spouts','bolts'):
    for c in d.get(kind,[]):
        r=['$TOPO', kind[:-1], c.get('spoutId') or c.get('boltId'),
           c.get('executors'), c.get('tasks'), c.get('emitted'), c.get('transferred')]
        w.writerow(r); cw.writerow(r)
rows.close()
"
echo "✅ Đã ghi $OUT"
