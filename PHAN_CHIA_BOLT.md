# Phân chia bolt giữa Gateway và Cloud (FOG v1 — giữ nguyên code thầy)

> Trả lời góp ý của giáo sư: *"Mục đích tách cloud/gateway là CHIA TẢI…
> gateway xử lý tác vụ nhẹ để cảnh báo ngay lập tức cho hộ gia đình, cloud
> xử lý phần còn lại. Để nguyên code thầy, chỉ đánh tag cho các bolt."*

## Nguyên tắc

- **Không gộp / không viết lại bolt nào.** Topology là code gốc
  (`gateway/src/main/java/com/storm/iotdata/`): `Spout_data`, `Spout_trigger`,
  `Bolt_split`, `Bolt_avg`, `Bolt_sum`, `Bolt_forecast`.
- Chia tải bằng **TagAwareScheduler** (đã có sẵn trong `gateway/tagawarescheduler/`):
  một Storm cluster duy nhất trải trên 2 máy; supervisor phía gateway **không
  tag**, supervisor phía cloud có `supervisor.scheduler.meta: tags: cloud`.
  Bolt nào gắn `tags=cloud` thì scheduler xếp sang máy cloud, còn lại nằm ở gateway.

## Phân chia mặc định và lý do

| Thành phần | Nơi chạy | Tải | Lý do |
|---|---|---|---|
| `spout-data` | **Gateway** | nhẹ | Nhận dữ liệu thô từ broker MQTT **local** — dữ liệu thô không rời khỏi nhà |
| `spout-trigger` | **Gateway** | rất nhẹ | Phát nhịp đồng hồ |
| `split-W` (×8 cửa sổ) | **Gateway** | nhẹ, stateless | Chỉ parse + tính `slice_index`. Đặt ở gateway để fan-out (allGrouping ×8 cửa sổ) xảy ra **trong máy**, không phình lưu lượng WAN |
| `avg-W` (×8) | **Gateway** | vừa | Trung bình **mức thiết bị** + phát **cảnh báo thiết bị TỨC THÌ** vào broker local (`Bolt_avg` publish device-notification qua `spout.brokerURL` = broker nhà) → hộ gia đình nhận cảnh báo ngay cả khi đứt mạng internet |
| `sum-W` (×8) | **Cloud** (`tags=cloud`) | nặng | Tổng hợp mức house/household (liên hộ), ghi `house_data`/`household_data` vào MySQL |
| `forecast-W` (×8) | **Cloud** (`tags=cloud`) | nặng nhất | Dự báo: query lịch sử DB + tính median — cần dữ liệu lịch sử và CPU, đúng vai trò cloud |

Luồng qua WAN chỉ còn `avg-W → sum-W/forecast-W` (dữ liệu đã tổng hợp theo cửa
sổ, nhỏ hơn nhiều so với dữ liệu thô) + phần ghi `device_data` của `Bolt_avg`
vào MySQL cloud.

**Cảnh báo:** cảnh báo **thiết bị** (quá tải, vượt ngưỡng max) do `avg`
phát ra **tại gateway, qua broker local** → tức thì, không phụ thuộc WAN.
Cảnh báo mức **house/household** do `sum` phát từ cloud về broker nhà.

## Tinh chỉnh tag để "kết quả đẹp" (không cần sửa code)

Thay đổi duy nhất trong code là `MainTopo.java` nhận thêm option
`-c/--cloudbolts` (mặc định `sum,forecast` — đúng hành vi hard-code cũ của thầy).
Khi nộp topology có thể thử các phương án phân chia khác **không cần rebuild**:

```bash
# Mặc định (như code thầy):
CLOUD_BOLTS="sum,forecast" docker compose run --rm topo-submit

# Đẩy thêm avg cửa sổ dài (không phục vụ cảnh báo tức thì) sang cloud
# nếu gateway quá tải:
CLOUD_BOLTS="sum,forecast,avg-60,avg-120,split-60,split-120" docker compose run --rm topo-submit
```

Quy ước giá trị: tên loại (`sum`, `forecast`, `avg`, `split`) áp cho **mọi**
cửa sổ; thêm `-W` (vd `avg-60`) chỉ áp cho cửa sổ đó.

Lưu ý khi cân chỉnh:
- `split-W` nên đi cùng `avg-W` của nó — nếu chuyển `avg-60` sang cloud mà để
  `split-60` ở gateway thì luồng `split-60 → avg-60` vượt WAN (to hơn luồng
  `avg → sum`); chuyển cả cặp thì luồng vượt WAN là **dữ liệu thô** cho cửa sổ
  đó (to nhất). Vì vậy chỉ chuyển cặp cửa sổ dài khi gateway thật sự quá tải.
- Trong báo cáo monolithic, nút cổ chai là `avg-1` (capacity 14.5). Ở FOG v1,
  `avg-1` chạy một mình một tầng (không tranh CPU với sum/forecast/DB) — đây
  chính là số liệu cần so sánh trước/sau.

## Vì sao cách này thỏa cả 2 góp ý (1) và (4)

1. **Chia tải thật:** cloud chạy 16/32 bolt (sum+forecast ×8 cửa sổ) gồm toàn
   bộ phần ghi DB house/household + dự báo; gateway chỉ còn phần nhẹ + cảnh
   báo tức thì — đúng mô hình smarthome thực tế.
2. **Code thầy giữ nguyên:** không bolt nào bị sửa/gộp; thay đổi duy nhất là
   `MainTopo` đọc danh sách tag từ tham số (mặc định giống hệt code cũ),
   còn lại toàn bộ là **cấu hình triển khai** (supervisor tag, compose, IP).
