# KB2 — Cloud Offline → Recovery (2026-06-16 08:28:35)

Outage: 300s | Cloud: 52.74.153.60

## T0 (trước outage): queue=0, enqueued=0, drained=1, flush_total=15, published_total=16

## Cloud MQTT OFF lúc 08:28:37
## Cloud MQTT ON lại lúc 08:33:41 — chờ queue xả về 0...

## KẾT QUẢ

| Chỉ số | Giá trị |
|---|---|
| **Max Queue Depth** | **25** batch |
| **Recovery Time** | **101s** (queue về 0 sau khi cloud online) |
| **Data Loss** | **0.0%** (đã queue 25, drain thành công 25, còn kẹt 0) |
| Tuples xử lý tại gateway trong phiên | 110846 (gateway KHÔNG dừng xử lý khi cloud offline) |

✅ PASS: Store-and-Forward hoạt động đúng khi có lỗi mạng — queue tăng khi offline, xả hết khi online, không mất dữ liệu.

Báo cáo này (số chuẩn): results/kb2_offline_20260616-082835.md
Ảnh minh hoạ: tự chụp panel 'Store-and-Forward Queue Depth' trên Grafana (đường tăng→về 0).
