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
