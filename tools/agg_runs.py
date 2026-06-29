#!/usr/bin/env python3
"""
Tổng hợp số liệu đo "chắc chắn".

  step  <ts.tsv> <steps.tsv> <skip_s> <step_dur> <mode>
        → in CSV/ stdout: với MỖI nấc, tính p50/p95/max (capacity, latency) trên
          giai đoạn ổn định (bỏ skip_s đầu nấc) + throughput + WAN KB/min.

  mean  <out_dir> <mode>
        → đọc summary_<mode>_run*.csv, gộp theo số nhà, in mean±std mỗi chỉ số.
"""
import sys, glob, os, csv, statistics as st


def pct(xs, p):
    xs = sorted(v for v in xs if v == v)  # bỏ nan
    if not xs:
        return float('nan')
    if len(xs) == 1:
        return xs[0]
    k = (len(xs) - 1) * (p / 100.0)
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def f(x):
    try:
        return float(x)
    except Exception:
        return float('nan')


def cmd_step(ts_file, steps_file, skip, step_dur, mode):
    rows = []
    with open(ts_file) as fh:
        r = csv.DictReader(fh, delimiter='\t')
        for d in r:
            rows.append({k: f(v) for k, v in d.items()})
    steps = []
    with open(steps_file) as fh:
        r = csv.DictReader(fh, delimiter='\t')
        for d in r:
            steps.append((int(float(d['houses'])), float(d['step_start']), float(d['step_end'])))

    out = csv.writer(sys.stdout)
    out.writerow(["houses", "msg_per_s", "cap_p50", "cap_p95", "cap_max",
                  "lat_p50_ms", "lat_p95_ms", "lat_max_ms", "gwcap_max",
                  "ack_per_s", "wan_kb_per_min", "n_samples"])
    for houses, s, e in steps:
        seg = [x for x in rows if s + skip <= x['epoch'] <= e]
        cap = [x['cap'] for x in seg]
        lat = [x['lat'] for x in seg]
        gwc = [x['gwcap'] for x in seg]
        wan = [(x['epoch'], x['wan_rx']) for x in seg if x['wan_rx'] == x['wan_rx']]
        if len(wan) >= 2:
            (e0, r0), (e1, r1) = wan[0], wan[-1]
            mins = max((e1 - e0) / 60.0, 1e-9)
            wan_kbm = round((r1 - r0) / 1024.0 / mins, 1)
        else:
            wan_kbm = float('nan')
        # throughput: 'ack' is a CUMULATIVE counter (exporter returns all-time for
        # every window) → rate = delta / seconds across the stable segment.
        ackp = [(x['epoch'], x['ack']) for x in seg if x['ack'] == x['ack']]
        if len(ackp) >= 2:
            (ae0, a0), (ae1, a1) = ackp[0], ackp[-1]
            ack_per_s = round(max(a1 - a0, 0) / max(ae1 - ae0, 1e-9), 1)
        else:
            ack_per_s = float('nan')
        out.writerow([houses, houses * 10,
                      round(pct(cap, 50), 4), round(pct(cap, 95), 4), round(max([c for c in cap if c == c], default=float('nan')), 4),
                      round(pct(lat, 50), 3), round(pct(lat, 95), 3), round(max([l for l in lat if l == l], default=float('nan')), 3),
                      round(max([g for g in gwc if g == g], default=float('nan')), 4),
                      ack_per_s, wan_kbm, len(seg)])


def cmd_mean(out_dir, mode):
    files = sorted(glob.glob(os.path.join(out_dir, f"summary_{mode}_run*.csv")))
    if not files:
        print(f"[agg] Không thấy summary_{mode}_run*.csv trong {out_dir}", file=sys.stderr)
        sys.exit(1)
    by_house = {}   # houses -> col -> [values across runs]
    cols = None
    for fp in files:
        with open(fp) as fh:
            r = csv.DictReader(fh)
            cols = r.fieldnames
            for d in r:
                h = d['houses']
                bag = by_house.setdefault(h, {c: [] for c in cols})
                for c in cols:
                    bag[c].append(f(d[c]))
    metric_cols = [c for c in cols if c not in ('houses', 'msg_per_s', 'n_samples')]
    out = csv.writer(sys.stdout)
    header = ["houses", "msg_per_s", "n_runs"]
    for c in metric_cols:
        header += [f"{c}_mean", f"{c}_std", f"{c}_ci95"]   # ci95 = half-width of 95% CI
    out.writerow(header)
    for h in sorted(by_house, key=lambda x: int(float(x))):
        bag = by_house[h]
        row = [h, bag['msg_per_s'][0] if bag.get('msg_per_s') else '', len(files)]
        for c in metric_cols:
            vals = [v for v in bag[c] if v == v]
            mean = round(st.mean(vals), 2) if vals else float('nan')
            # population std for description; sample std for the CI (unbiased)
            sd = round(st.pstdev(vals), 2) if len(vals) > 1 else 0.0
            ci = round(ci95_halfwidth(vals), 2)
            row += [mean, sd, ci]
        out.writerow(row)


# two-sided t critical values @ 95% for df=1..10, then normal approx
_T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571,
        6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228}


def ci95_halfwidth(vals):
    """Half-width of the 95% confidence interval of the mean (t-based, small n)."""
    n = len(vals)
    if n < 2:
        return float('nan')
    sd = st.stdev(vals)            # sample std (n-1)
    t = _T95.get(n - 1, 1.96)
    return t * sd / (n ** 0.5)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    if sys.argv[1] == "step":
        _, _, ts_file, steps_file, skip, step_dur, mode = sys.argv
        cmd_step(ts_file, steps_file, float(skip), float(step_dur), mode)
    elif sys.argv[1] == "mean":
        cmd_mean(sys.argv[2], sys.argv[3])
    else:
        print(__doc__); sys.exit(1)
