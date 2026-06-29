# KB2 — Cloud Offline → Recovery (2026-06-15 09:15:26)

Outage: 300s | Cloud: 52.74.153.60

## T0 (trước outage): queue=0, enqueued=0, drained=0, flush_total=120, published_total=120

## Cloud MQTT OFF lúc 09:15:28
## Cloud MQTT ON lại lúc 09:20:32 — chờ queue xả về 0...

## KẾT QUẢ

| Chỉ số | Giá trị |
|---|---|
| **Max Queue Depth** | **200** batch |
| **Recovery Time** | **71s** (queue về 0 sau khi cloud online) |
| **Data Loss** | **0.0%** (đã queue 200, drain thành công 200, còn kẹt 0) |
| Tuples xử lý tại gateway trong phiên | 102615 (gateway KHÔNG dừng xử lý khi cloud offline) |

✅ PASS: Store-and-Forward hoạt động đúng khi có lỗi mạng — queue tăng khi offline, xả hết khi online, không mất dữ liệu.

Báo cáo này (số chuẩn): results/kb2_offline_20260615-091526.md
Ảnh minh hoạ: tự chụp panel 'Store-and-Forward Queue Depth' trên Grafana (đường tăng→về 0).
