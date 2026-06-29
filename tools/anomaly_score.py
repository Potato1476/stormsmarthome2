#!/usr/bin/env python3
"""
Chấm điểm bộ phát hiện bất thường: so ground-truth (anomaly_eval.js) với cảnh báo
thật của gateway.

  python3 tools/anomaly_score.py <anomaly_gt.json> <alerts.log> [tol_sec]

alerts.log: log cảnh báo của gateway, BẮT BUỘC có timestamp của docker, ví dụ:
  docker compose -f docker-compose.gateway.yml --profile multi logs --timestamps \
    | grep ' ALERT ' > alerts.log
Dòng ALERT mẫu (Bolt_ingest):
  2026-06-29T08:23:01.123Z [Bolt_ingest-gw-01] ALERT HIGH house=1 hh=0 plug=2 z=5.1 ...

In: precision / recall / F1 / false-positive rate / độ trễ phát hiện trung bình.
"""
import sys, json, re
from datetime import datetime, timezone

if len(sys.argv) < 3:
    print(__doc__); sys.exit(1)
GT, ALOG = sys.argv[1], sys.argv[2]
TOL = float(sys.argv[3]) if len(sys.argv) > 3 else 90.0  # cửa sổ khớp ±90s

gt = json.load(open(GT))
spikes = gt["spikes"]

# Parse alert log lines
ts_re = re.compile(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)')
fld_re = re.compile(r'house=(\d+)\s+hh=(\d+)\s+plug=(\d+)')
alerts = []
for line in open(ALOG, errors='ignore'):
    if ' ALERT ' not in line:
        continue
    mt = ts_re.search(line.strip())
    mf = fld_re.search(line)
    if not mf:
        continue
    if mt:
        iso = mt.group(1).replace('Z', '+00:00')
        ep = datetime.fromisoformat(iso).replace(tzinfo=timezone.utc).timestamp()
    else:
        ep = None
    alerts.append({'ts': ep, 'h': int(mf.group(1)), 'hh': int(mf.group(2)), 'p': int(mf.group(3)), 'used': False})

# Match each injected spike to the nearest unused alert for same device within TOL
tp, fn, latencies = 0, 0, []
for s in spikes:
    cand = [a for a in alerts if not a['used'] and a['h'] == s['houseId']
            and a['hh'] == s['householdId'] and a['p'] == s['plugId']
            and (a['ts'] is None or abs(a['ts'] - s['ts']) <= TOL)]
    if cand:
        # nearest in time if timestamps available
        cand.sort(key=lambda a: abs((a['ts'] or s['ts']) - s['ts']))
        a = cand[0]; a['used'] = True; tp += 1
        if a['ts'] is not None:
            latencies.append(a['ts'] - s['ts'])
    else:
        fn += 1

fp = sum(1 for a in alerts if not a['used'])
precision = tp / (tp + fp) if (tp + fp) else float('nan')
recall = tp / (tp + fn) if (tp + fn) else float('nan')
f1 = 2 * precision * recall / (precision + recall) if precision == precision and recall == recall and (precision + recall) else float('nan')
dur_min = max((gt['end'] - gt['start']) / 60.0, 1e-9)
fpr_per_min = fp / dur_min
mean_lat = sum(latencies) / len(latencies) if latencies else float('nan')

print("==== ANOMALY DETECTION EVALUATION ====")
print(f"Injected (ground-truth): {len(spikes)}")
print(f"Alerts parsed:           {len(alerts)}")
print(f"TP={tp}  FP={fp}  FN={fn}")
print(f"Precision: {precision:.3f}")
print(f"Recall:    {recall:.3f}")
print(f"F1:        {f1:.3f}")
print(f"False-positive rate: {fpr_per_min:.2f} /phút")
print(f"Mean detection latency: {mean_lat:.1f} s" if mean_lat == mean_lat else "Mean detection latency: N/A (log thiếu timestamp)")
