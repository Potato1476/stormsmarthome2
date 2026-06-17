#!/usr/bin/env python3
# ============================================================================
# So sánh kết quả Monolithic vs Fog từ các CSV trong results/ → bảng markdown.
#
# Đọc:
#   results/monolithic_*.csv , results/fog_*.csv         (collect_metrics.sh)
#   results/system_*.csv                                  (collect_system.sh)
# Xuất:
#   In bảng ra màn hình + ghi results/COMPARISON_<ts>.md
#
# Dùng (sau khi đã chạy collect_metrics.sh + collect_system.sh cho cả 2 hệ):
#   ./tools/compare_results.py
#   ./tools/compare_results.py --results-dir results
#
# Tính hợp lệ đã đảm bảo: cùng dataset, cùng ~400 msg/s (publisher throttle giống
# nhau), cùng exporter mr4x2 v1.2.2 + REFRESH_RATE=5, cùng EC2 t3.large, cùng
# Prometheus scrape 5s. Nhãn độ tin cậy gắn theo từng chỉ số bên dưới.
# ============================================================================
import csv, glob, os, re, sys, datetime

RES = "results"
if "--results-dir" in sys.argv:
    RES = sys.argv[sys.argv.index("--results-dir") + 1]


def latest(pattern):
    fs = sorted(glob.glob(os.path.join(RES, pattern)), key=os.path.getmtime)
    return fs[-1] if fs else None


def all_sorted(pattern):
    return sorted(glob.glob(os.path.join(RES, pattern)), key=os.path.getmtime)


def read_metrics(path):
    """collect_metrics.sh CSV -> {(metric,window): float|None}"""
    d = {}
    if not path or not os.path.exists(path):
        return d
    with open(path) as f:
        for row in csv.DictReader(f):
            try:
                d[(row["metric"], row["window"])] = float(row["value"])
            except (ValueError, TypeError, KeyError):
                d[(row.get("metric"), row.get("window"))] = None
    return d


_UNITS = {"B": 1, "KB": 1e3, "KIB": 1024, "MB": 1e6, "MIB": 1024**2,
          "GB": 1e9, "GIB": 1024**3, "TB": 1e12, "TIB": 1024**4}


def to_bytes(s):
    """'12.3MB' / '4.5kiB' -> số bytes (float). None nếu không parse được."""
    m = re.match(r"\s*([\d.]+)\s*([A-Za-z]+)", s or "")
    if not m:
        return None
    return float(m.group(1)) * _UNITS.get(m.group(2).upper(), 1)


def read_system(path):
    """collect_system.sh CSV -> (rows[list of dict], total_cpu)"""
    rows, total_cpu = [], None
    if not path or not os.path.exists(path):
        return rows, total_cpu
    with open(path) as f:
        for row in csv.DictReader(f):
            if row["container"] == "TOTAL_CPU_PERCENT":
                try:
                    total_cpu = float(row["cpu_perc"])
                except (ValueError, TypeError):
                    pass
                continue
            rows.append(row)
    return rows, total_cpu


def broker_rx(path, container):
    rows, _ = read_system(path)
    for r in rows:
        if container in (r.get("container") or ""):
            netio = r.get("net_io", "")
            rx = netio.split("/")[0] if "/" in netio else netio
            return to_bytes(rx)
    return None


def pct(mono, fog):
    if mono in (None, 0) or fog is None:
        return "—"
    change = (fog - mono) / mono * 100
    arrow = "↓" if change < 0 else "↑"
    a = abs(change)
    return f"{arrow} {a:.2f}%" if a > 99 else f"{arrow} {a:.1f}%"


def fmt(v):
    if v is None:
        return "NA"
    if abs(v) >= 1000:
        return f"{v:,.0f}"
    return f"{v:.3f}".rstrip("0").rstrip(".") if v != int(v) else f"{int(v)}"


# ── Nạp dữ liệu ──────────────────────────────────────────────────────────────
mono = read_metrics(latest("monolithic_*.csv"))
fog = read_metrics(latest("fog_*.csv"))

if not mono and not fog:
    sys.exit(f"[compare] Không thấy monolithic_*.csv / fog_*.csv trong {RES}/. "
             "Chạy collect_metrics.sh trước.")

# WAN: tìm file system sớm nhất (t0) & muộn nhất (t30) có chứa broker tương ứng
def wan(container, label_glob):
    files = all_sorted(label_glob)
    pts = [(f, broker_rx(f, container)) for f in files]
    pts = [(f, rx) for f, rx in pts if rx is not None]
    if len(pts) >= 2:
        return pts[-1][1] - pts[0][1]   # RX(t30) - RX(t0)
    if len(pts) == 1:
        return pts[0][1]
    return None

wan_mono = wan("mqtt-broker", "system_mono*.csv")
wan_fog = wan("cloud-mqtt", "system_fog-cloud*.csv")

# CPU tổng
def total_cpu_of(label_glob):
    f = latest(label_glob)
    _, tc = read_system(f)
    return tc

cpu_mono = total_cpu_of("system_mono-t30*.csv") or total_cpu_of("system_mono*.csv")
cpu_fog_cloud = total_cpu_of("system_fog-cloud*.csv")
cpu_fog_gw = total_cpu_of("system_fog-gw-t30*.csv") or total_cpu_of("system_fog-gw*.csv")

# ── Dựng bảng ────────────────────────────────────────────────────────────────
ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
L = []
L.append(f"# So sánh Monolithic vs Fog — {ts}\n")
L.append("> Cùng dataset · ~400 msg/s · cùng EC2 t3.large · cùng exporter mr4x2 v1.2.2 · scrape 5s.\n")

L.append("## A. Throughput (độc lập phần cứng — so sánh MẠNH NHẤT)\n")
L.append("| Chỉ số | Monolithic | Fog | Thay đổi |")
L.append("|---|---|---|---|")
for metric, win, name in [
    ("acked", "all-time", "Acked (all-time)"),
    ("emitted", "all-time", "Emitted (all-time)"),
    ("transferred", "all-time", "Transferred (all-time)"),
]:
    m, fgv = mono.get((metric, win)), fog.get((metric, win))
    L.append(f"| {name} | {fmt(m)} | {fmt(fgv)} | {pct(m, fgv)} |")

L.append("\n## B. Độ trễ & capacity (cùng EC2 → so được xu hướng)\n")
L.append("| Chỉ số | Monolithic | Fog | Thay đổi | Tin cậy |")
L.append("|---|---|---|---|---|")
rows_b = [
    ("max_complete_latency_ms", "all-time", "Complete Latency max (ms) — HEADLINE", "định lượng (cùng box)"),
    ("max_complete_latency_ms", "600", "Complete Latency max (ms, 600s)", "định lượng (cùng box)"),
    ("max_process_latency_ms", "600", "Process Latency max (ms)", "định lượng (cùng box)"),
    ("max_execute_latency_ms", "600", "Execute Latency max (ms)", "I/O-bound, tham khảo"),
    ("max_bolt_capacity", "600", "Bolt Capacity peak", "định tính (bản chất khác)"),
]
for metric, win, name, conf in rows_b:
    m, fgv = mono.get((metric, win)), fog.get((metric, win))
    L.append(f"| {name} | {fmt(m)} | {fmt(fgv)} | {pct(m, fgv)} | {conf} |")

L.append("\n## C. Tài nguyên tổng & WAN (trả lời câu hỏi TỔNG THỂ)\n")
L.append("| Chỉ số | Monolithic | Fog | Ghi chú |")
L.append("|---|---|---|---|")
L.append(f"| Σ CPU% Cloud (cùng t3.large) | {fmt(cpu_mono)} | {fmt(cpu_fog_cloud)} | mono = cả box; fog = chỉ cloud tier |")
L.append(f"| Σ CPU% 8 gateway (CHI PHÍ Fog đẻ thêm) | — | {fmt(cpu_fog_gw)} | giả lập trên laptop → tương đối |")
wan_m_mb = f"{wan_mono/1e6:.1f} MB" if wan_mono else "NA"
wan_f_mb = f"{wan_fog/1e6:.1f} MB" if wan_fog else "NA"
wan_pct = pct(wan_mono, wan_fog) if (wan_mono and wan_fog) else "—"
L.append(f"| WAN bytes/phiên lên Cloud (broker RX) | {wan_m_mb} | {wan_f_mb} | {wan_pct} |")
gwpub = fog.get(("gw_mqtt_published_total", "-"))
L.append(f"| Fog MQTT msgs gửi lên Cloud (đếm) | (raw ~720k offered) | {fmt(gwpub)} | counter gateway |")

L.append("\n## Diễn giải khung (điền/điều chỉnh theo số thật)\n")
L.append("- **Throughput**: Fog giảm nhiều bậc vì fan-out/định tuyến đẩy xuống biên — đây là bằng chứng kiến trúc, độc lập phần cứng.")
L.append("- **Complete Latency**: chỉ số then chốt; cùng EC2 nên chênh lệch phản ánh đúng việc xoá bottleneck đơn-executor.")
L.append("- **Capacity**: nếu mono bão hoà nặng trên t3.large (cao hơn cả số local cũ) → lập luận 'cùng box, mono không kham nổi' rất mạnh.")
L.append("- **TỔNG THỂ**: cái giá Fog = Σ CPU 8 gateway. Đổi lại WAN giảm + sống offline. Verdict phụ thuộc gateway là hub sẵn có hay HW mua mới.")

out = "\n".join(L) + "\n"
print(out)
fn = os.path.join(RES, f"COMPARISON_{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.md")
with open(fn, "w") as f:
    f.write(out)
print(f"[compare] Đã ghi: {fn}")
