# KẾ HOẠCH ĐO LẠI "KHÔNG KẼ HỞ" + SỬA CODE

> Mục tiêu: vô hiệu hoá toàn bộ câu hỏi phản biện bằng cách (1) sửa các lỗ hổng
> phương pháp trong code, (2) chuẩn hoá điều kiện so sánh, (3) đo lại có thống kê,
> (4) định khung lại luận điểm trung thực.
>
> Ký hiệu trạng thái: **[ĐÃ SỬA]** = đã chỉnh trong repo · **[CODE]** = cần sửa code
> (đã chỉ rõ chỗ) · **[ĐO]** = cần đo lại/đo bổ sung · **[VIẾT]** = sửa trong báo cáo.

Sự thật quan trọng nhất sau khi đọc code thật:

| Module | Vai trò thật |
|---|---|
| `gateway/src/.../MainTopo.java` | Code "thầy" = **baseline Monolithic** và cũng là Fog-2-EC2 (qua `--cloudbolts`). Bolt: split→avg→sum→forecast, windows cấu hình qua env. |
| `fog-gateway/src/.../Bolt_ingest.java` | **Fog gateway thật**: tích luỹ count/sum, 1 batch **mỗi window** mỗi flush, EWMA z-score + Slack ở biên, store-and-forward `queue.jsonl`. |
| `fog-cloud/src/.../Bolt_cloudMerge.java` | **Cloud Fog**: REPLACE INTO, rollup household/house, suy ra 60/120 phút từ 30 phút. parallelism=1. |

→ Báo cáo hiện mô tả Fog theo `fog-gateway`/`fog-cloud` (đúng), nhưng có vài chỗ
**listing/đặt tên sai so với code** (xem Nhóm B). Phải căn chỉnh theo code thật.

---

## NHÓM A — Giữ điều kiện so sánh công bằng (nguy hiểm nhất)

### A1. Giữ tổng phần cứng cố định **[ĐO]**
**Vấn đề:** Monolithic = 1× EC2 t3.large; Fog = 1× cloud + 7 Docker + 1 Pi → trộn
biến "kiến trúc" với "tổng năng lực tính toán".
**Cách đo lại đúng (chọn 1, nên làm cả 2 để mạnh nhất):**
1. **Cùng cloud instance:** chạy cả Monolithic và Cloud-Fog trên **đúng cùng loại
   EC2** (ví dụ cùng t3.large hoặc cùng t3.small). Hiện `docs`/compose để Monolithic
   t3.large còn Fog-cloud t3.small — phải thống nhất.
2. **Tách bạch "đóng góp của phân tán" khỏi "đóng góp của thêm máy":** thêm một
   nhánh **"Monolithic-scaled"** = Monolithic chạy trên instance lớn hơn / nhiều
   worker hơn, để chứng minh nó **vẫn** nghẽn (nếu nghẽn) → khi đó mới kết luận
   được nghẽn là do kiến trúc, không do thiếu RAM/CPU.
**Báo cáo:** thêm cột "Tổng vCPU/RAM toàn hệ" vào Bảng 3.2 và nêu rõ ai có gì.

### A2. Báo cáo & quét parallelism của Monolithic (chống "strawman") **[CODE]+[ĐO]**
**Sự thật trong code:** `gateway/src/.../MainTopo.java` (~dòng 114):
```java
builder.setBolt("split-"+windowSize, new Bolt_split(...), 1).setNumTasks(4)  // hint=1
builder.setBolt("avg-"+windowSize,   new Bolt_avg(...),   1)                 // hint=1
... sum, forecast cũng parallelism hint = 1
conf.setNumWorkers(2);
```
→ **Mọi bolt Monolithic chạy parallelism hint = 1.** Đây đúng là điểm hội đồng sẽ bắt.
**Việc cần làm:**
- **[CODE]** Tham số hoá parallelism qua env, ví dụ:
  ```java
  int P = Integer.parseInt(env("BOLT_PARALLELISM","1"));
  builder.setBolt("split-"+w, new Bolt_split(...), P).setNumTasks(Math.max(4,P));
  ```
  và dùng `fieldsGrouping` theo khoá thiết bị thay cho `allGrouping`/`shuffleGrouping`
  ở `split` để tăng song song mà vẫn đúng ngữ nghĩa.
- **[ĐO]** Quét `BOLT_PARALLELISM ∈ {1,2,4}` cho Monolithic ở h40. Báo cáo bảng:
  parallelism → split capacity, complete latency. Hai khả năng, đều thắng lập luận:
  - Nếu tăng song song mà **vẫn nghẽn** → chứng minh nghẽn do kiến trúc, không do cấu hình.
  - Nếu hết nghẽn → trung thực ghi nhận và **định khung lại** (xem Nhóm A-tổng kết).
- **[VIẾT]** Trong §3.2 và Chương 5 ghi rõ parallelism hint + numTasks + numWorkers
  + lý do chọn grouping.

### A3. Chuẩn hoá khối lượng công việc hai bên **[CODE/CONFIG]+[ĐO]**
**Sự thật:** Monolithic windows mặc định `{1,5,10,15,20,30,60,120}` (8) + forecast +
household. Fog: gateway gửi `{1,5,10,15,30}`, cloud suy ra `{60,120}` ⇒ Fog =
`{1,5,10,15,30,60,120}` (7, **thiếu 20**) và **không có forecast**.
→ Một phần lợi thế Fog là do **làm ít hơn**. Phải khử.
**Việc cần làm:**
- **[CONFIG]** Chạy lại với **cùng tập window** hai bên. `getWindowList()` lấy từ env
  cả ở `gateway` (Monolithic) lẫn `fog-gateway`. Đặt `WINDOW_LIST` giống nhau.
  - Hoặc bỏ 20-phút khỏi Monolithic, **hoặc** thêm 20 vào gateway windows
    (`GatewayConfig.getWindowList`) và để cloud không cần suy ra.
- **[CODE]** Bổ sung tầng **forecast** ở Cloud-Fog (`Bolt_cloudMerge`) tương đương
  `Bolt_forecast`, hoặc **bỏ forecast khỏi Monolithic** trong phép so sánh. Phải
  đối xứng. (Khuyến nghị: bỏ forecast cả hai để so "đường tổng hợp" thuần.)
- **[VIẾT]** Nêu rõ: "hai hệ tính **cùng** số cửa sổ và cùng mức rollup".

### A4. 318,9% là do code ghi DB chậm, KHÔNG phải giới hạn kiến trúc **[ĐÃ SỬA]**
**Nguyên nhân gốc (đã xác minh):** `FogDB_store` dùng `addBatch()/executeBatch()`
nhưng URL JDBC **thiếu** `rewriteBatchedStatements=true` ⇒ 200 dòng = 200 round-trip
+ autocommit ⇒ ~47,8 s/batch ⇒ "318,9%".
**Đã sửa trong repo:**
- `fog-cloud/.../CloudConfig.java` `getDbJdbcUrl()`: thêm
  `&rewriteBatchedStatements=true&cachePrepStmts=true&useServerPrepStmts=false`.
- `fog-cloud/.../FogDB_store.java`: 3 hàm upsert nay `setAutoCommit(false)` +
  `commit()` quanh `executeBatch()` ⇒ 1 transaction/flush.
**[ĐO]** Build lại `fog-cloud`, chạy lại KB1-B (1 GW, h40). Kỳ vọng: execute latency
batch giảm từ ~47,8 s xuống **dưới ~1 s**, cloud capacity 1-GW rớt từ 318,9% xuống
**< 100%**. Ghi nhận con số mới. (Đây là thay đổi làm "ưu thế 8 gateway" co lại — phải trung thực.)

### A5. Đo WAN Monolithic THẬT, bỏ ước tính 86% **[ĐO]+[CODE nhẹ]**
**Vấn đề:** "giảm 86%" dựa trên ước tính `400×100 byte`. Monolithic chạy thật rồi → đo được.
**Cách đo (chọn theo tầng):**
- WAN Monolithic = lưu lượng publisher→broker (raw MQTT). Đo bằng **một trong**:
  - `docker stats` net I/O của container broker/publisher (chốt mốc đầu–cuối mỗi nấc), hoặc
  - `node_exporter`/`cAdvisor` `container_network_transmit_bytes_total` trên container publisher, hoặc
  - mosquitto `$SYS/broker/bytes/received` (counter sẵn có).
- WAN Fog = đã có `fog_gateway_*` (publish_size/flush). Quy về **cùng đơn vị KB/min**
  và **cùng điểm đo** (egress khỏi site biên).
**[VIẾT]** Thay footnote "ước tính" bằng số đo thật ± std; nêu rõ định nghĩa "WAN"
(điểm đo nào) cho cả hai.

### Tổng kết Nhóm A → ĐỊNH KHUNG LẠI LUẬN ĐIỂM **[VIẾT]**
Sau khi sửa A4, thông điệp trung thực (đã thống nhất) là:
> "Nút thắt thật của bài toán là **kích thước batch ghi DB ở cloud**. Ghi theo lô có
> transaction (A4) khử phần lớn nghẽn của **mọi** cấu hình. Lợi ích **bền vững** của
> nhiều gateway không phải throughput (1 Pi đã thừa sức — xem B10) mà là **cách ly
> lỗi (fault isolation)** và **giảm/định hình WAN**, đổi lại chi phí ~8× tài nguyên biên."

---

## NHÓM B — Mâu thuẫn nội tại & tính đúng đắn

### B6. "Complete Latency 84 s" vs "capacity 0%" — đặt sai tên **[VIẾT]**
**Sự thật:** cột "Cloud C.Lat 84.499 ms" trong Bảng 6.1/7.1 **không** phải Storm
`complete_latency` (acker) — nó là **End-to-End DB latency** = `updatedAt − event_ts`,
bị thổi phồng do REPLACE/`updatedAt=now()`. Bolt rảnh 0% mà tuple "chờ 84 s" là vô lý
nếu hiểu là complete_latency.
**Việc cần làm:**
- **[VIẾT]** Đổi tên cột thành **"End-to-End DB Latency (artifact)"**; tách hẳn khỏi
  Storm `complete_latency`. Trong Bảng 7.1 **không** để chung cột hai đại lượng khác
  nhau → **bỏ Bảng 7.1 khỏi vai trò "so sánh latency"**, thay bằng so sánh
  **capacity** (đại lượng cùng định nghĩa).
- **[ĐO khuyến nghị]** Báo cáo **Storm complete_latency thật** (lấy từ Storm UI/metrics)
  cho cả hai hệ — đây mới là đại lượng so sánh hợp lệ.
- **[CODE tuỳ chọn]** Thêm cột `firstWrittenAt` (chỉ set 1 lần) để đo e2e latency lần
  ghi đầu, thay cho `updatedAt` luôn = lần cuối (xem B8/Phụ lục A báo cáo).

### B7. "1 batch hay 5 batch/flush?" — listing trong báo cáo SAI **[VIẾT]**
**Sự thật trong code** (`Bolt_ingest.flush()`): vòng lặp `for windowMin: ... publishOrQueue(batch)`
⇒ **1 batch cho MỖI window** ⇒ với 5 window = **5 batch/gateway/flush**.
→ Công thức `Qmax = NGW×W×(Toutage/Tflush) = 8×5×5 = 200` **ĐÚNG với code**.
Lỗi nằm ở **Listing 3.2** trong báo cáo (tôi viết giản lược chỉ 1 `appendToDiskQueue`).
**Việc cần làm [VIẾT]:** sửa Listing 3.2 cho khớp code thật:
```java
void flush() {
  drainQueue();                                  // thử xả queue trước
  for (int windowMin : windowList) {             // 1 batch MỖI window
    AggregatedBatch b = buildBatch(windowMin);   // count/sum tích luỹ
    publishOrQueue(b);                           // publish; lỗi → appendToQueue()
  }
  // KHÔNG reset accumulator (xem B8); chỉ cleanOldSlices()
}
```

### B8. "resetAccumulators() mỗi 60 s" — listing SAI, code đúng **[VIẾT]**
**Sự thật:** `Bolt_ingest.flush()` **KHÔNG** gọi reset. Mỗi số đọc cộng dồn vào đúng
`sliceIndex = timeInDay/(windowMin·60000)`; trong suốt một slice 30 phút, mọi flush
gửi **cumulative đến hiện tại**; Cloud REPLACE ghi đè bằng giá trị mới nhất ⇒ trung
bình 30 phút **đúng**. Chỉ `cleanOldSlices()` xoá slice cũ > 3h.
**Việc cần làm [VIẾT]:** Bỏ `resetAccumulators()` khỏi Listing 3.2; thêm 1 đoạn giải
thích "cumulative-until-slice-boundary" + ví dụ số (vd slice 30' nhận 1800 mẫu, mỗi
flush gửi (count,sum) luỹ kế, REPLACE giữ bản mới nhất). Đây chính là câu trả lời cho
câu hỏi "trung bình 30 phút tính đúng thế nào".

### B9. 318,9% — nêu rõ cửa sổ đo & số executor **[VIẾT]+[ĐO]**
Sau A4 con số sẽ đổi. Khi đo lại:
- **[VIẾT]** Ghi rõ **cửa sổ đo capacity của Storm** (mặc định 60 s hay 600 s?) và
  **số executor** của `Bolt_cloudMerge` (hiện =1, `CloudMainTopo.java:35`). Capacity của
  1 executor về lý thuyết ≤ ~100%/executor; >100% nghĩa là tính trên cửa sổ trong đó
  một execute() (trigger) kéo dài → cần chú thích để tái lập được bằng số học.

### B10. Dữ liệu của chính đồ án phủ định "8 gateway vì throughput" **[VIẾT]+[ĐO]**
**Sự thật (Bảng 6.2):** 1 Pi gánh 40 nhà (400 msg/s) với **GW capacity 0,95%** ⇒ biên
**không bao giờ** là nút thắt. Vậy "Pi xử lý 50 msg/s" (§3.5.2, §8.1.5) là **hạ thấp
8×** năng lực thật.
**Việc cần làm:**
- **[VIẾT]** Sửa phát biểu năng lực biên: nêu đúng "1 Pi xử lý ≥ 400 msg/s với
  capacity < 1%". Định khung lại lý do tồn tại của 8 gateway = **fault isolation +
  định hình WAN**, không phải throughput.
- **[ĐO khuyến nghị]** Đẩy 1 Pi vượt 400 msg/s đến khi biên thực sự nghẽn → công bố
  **trần năng lực biên thật** (số mạnh để bảo vệ).

---

## NHÓM C — Chặt chẽ & tránh phát biểu quá mức

### C11. Energy Optimizer chỉ hiệu quả lúc ramp **[VIẾT]+[ĐO tuỳ chọn]**
**Sự thật:** vận hành thật 40 nhà phát 10 msg/s 24/7 ⇒ không gateway nào idle > 15 s
⇒ optimizer gần như không kích hoạt. Ví dụ "tiết kiệm 12–30%" lấy ở nấc h10 (nhân tạo).
- **[VIẾT]** Nói thẳng phạm vi áp dụng hẹp: chỉ hữu ích khi tải **không đều/thưa**
  (nhà vắng, ban đêm, theo mùa) hoặc giai đoạn triển khai tăng dần. Không tô vẽ là
  cải tiến phổ quát.
- **[ĐO tuỳ chọn]** Tạo kịch bản tải thực tế hơn (một số nhà "đi vắng" → ngừng phát
  nhiều giờ) để cho thấy optimizer tiết kiệm trong điều kiện hợp lý.

### C12. Phát hiện bất thường chưa đánh giá định lượng **[ĐO]+[CODE nhẹ]**
**Sự thật:** `AnomalyDetector` **đã có warmup** (`config.getAlertWarmup()`) nên không
"bão cảnh báo" lúc khởi tạo `var=1.0` như lo ngại — nhưng **vẫn thiếu** precision/recall.
- **[CODE]** Viết harness inject anomaly có nhãn (ground-truth): publisher chèn các
  spike/known-events vào N thiết bị tại thời điểm biết trước.
- **[ĐO]** Tính **precision/recall/F1, false-positive rate**, độ trễ phát hiện. Quét
  `Z_THRESHOLD ∈ {3,4,5}` và `warmup`.
- **[VIẾT]** Thêm tiểu mục đánh giá định lượng; nếu không kịp đo, **hạ cấp** phát biểu
  thành "minh hoạ khả năng phát hiện tại biên" + đưa eval vào hướng phát triển.

### C13. Bỏ "chạy lại nếu có outlier" + báo cáo n lần chạy **[ĐO]+[VIẾT]**
**Vấn đề:** §4.5 "chạy lại khi có outlier" = selective re-running → thiên lệch. Số liệu
hiện là point-estimate 1 lần.
- **[ĐO]** Chạy mỗi kịch bản **n ≥ 5 lần**, **giữ tất cả** (không loại lần xấu), báo cáo
  **mean ± std** (hoặc CI95). Dùng script gói ở `tools/` (xem mục Protocol).
- **[VIẾT]** Sửa §4.5: bỏ chính sách loại outlier; mô tả quy trình n-run + cách tổng hợp.

### C14. "0% mất dữ liệu" chỉ đúng có điều kiện **[VIẾT]+[ĐO tuỳ chọn]**
- **[VIẾT]** Đặc tả **outage tối đa chịu được** theo dung lượng đĩa: với tốc độ tích
  luỹ `r = NGW×W/Tflush` batch/phút và dung lượng đĩa `D`, thời gian chịu đựng
  `T_max ≈ D / (r × kích_thước_batch)`. Nêu rõ "0% loss" chỉ đúng khi `Toutage < T_max`
  và khi drain-rate > fill-rate.
- **[ĐO tuỳ chọn]** Test thêm 1 outage dài (vd 30 phút) để minh hoạ queue đĩa phình
  tuyến tính và recovery dài hơn.

### C15. Spike 91,2% "tự phục hồi" làm yếu phép đo **[VIẾT]+[ĐO]**
- **[ĐO]** Vì snapshot cuối nấc bắt được transient, hãy đo **chuỗi thời gian liên tục**
  (không chỉ snapshot) và báo cáo capacity **p50/p95/max** trong giai đoạn ổn định của
  mỗi nấc → tái lập được, không phụ thuộc thời điểm chụp.
- **[VIẾT]** Giải thích nhất quán: nếu là JVM/JDBC cold-start thì phải nói rõ vì sao chỉ
  h10 spike. Khả năng thật: h10 là lúc gw-02 vừa bật **đồng thời** JDBC pool còn lạnh +
  REPLACE chưa rewriteBatched (đã sửa A4) → sau A4 đo lại có thể spike này **biến mất**.

### C16. Giải thích nén GZIP ngược trực giác **[VIẾT]+[ĐO]**
- **[VIẾT]** Bỏ lập luận "batch lớn nén kém". GZIP thường nén **tốt hơn** với input lớn.
  Chênh 19% WAN (1GW>8GW) nhiều khả năng do **overhead per-publish/MQTT/refresh từ điển
  mỗi batch nhỏ** hoặc **nhiễu đo**.
- **[ĐO]** Đo trực tiếp: với cùng dữ liệu h40, log `payload_bytes` mỗi batch của 1GW vs
  8GW (đã có `publish_size`); tính tỷ lệ nén thật. Nếu không kết luận chắc → ghi "khác
  biệt nhỏ, trong sai số đo".

---

## NHÓM D — Lỗi nhỏ trình bày (sửa ngay trong báo cáo) **[VIẾT]**

| # | Lỗi | Sửa |
|---|---|---|
| D1 | Abstract EN "eleven", §1.6 "11" vs chỗ khác "10" | Thống nhất **10** (bug fix Prometheus không tính) ở MỌI nơi. |
| D2 | 199 vs 296 ops/s (Bảng 7.2 vs 5.2) | Chú thích rõ điều kiện mỗi số (h40 spout-throttle vs steady max). |
| D3 | house-35..39 (0-index) vs "House #1" (Hình 3.14) | Thống nhất quy ước đánh số nhà. |
| D4 | "50 tỷ thiết bị 2030" không nguồn | Thêm trích dẫn hoặc đổi sang số có nguồn (vd IoT Analytics/Statista) — số 50 tỷ của Cisco/Ericsson đã bị rút. |
| D5 | Ack ratio 3,4% ở h01 gây hiểu nhầm | Chú thích: đây là acked/emitted (có fan-out), **không** phải tỉ lệ thành công; 0,4% ≠ mất 99,6% dữ liệu. |

---

## PROTOCOL ĐO LẠI (chạy theo thứ tự)

0. **Build lại** `fog-cloud` (đã sửa A4) và `gateway` (sau khi thêm `BOLT_PARALLELISM`).
1. **Chuẩn hoá cấu hình** (file env/compose):
   - Cùng loại EC2 cho Monolithic và Cloud-Fog (A1).
   - `WINDOW_LIST` giống nhau hai bên; thống nhất có/không forecast (A3).
   - Ghi lại: vCPU/RAM mỗi node, parallelism, numWorkers, numTasks.
2. **Bật đo WAN thật** ở cả hai (A5): node_exporter/cAdvisor hoặc mosquitto `$SYS`.
3. **n-run**: mỗi kịch bản (MONO-KB1/2, FOG-KB1-A/B, FOG-KB2-A/B) chạy **≥5 lần**,
   reset Docker giữa các lần, **giữ mọi lần** (C13).
4. **Thu metric chuỗi thời gian** (không chỉ snapshot cuối nấc) → tính p50/p95/max
   capacity & complete_latency cho giai đoạn ổn định mỗi nấc (C15, B6, B9).
5. **Quét parallelism Monolithic** `{1,2,4}` ở h40 (A2).
6. **Quét batch DB cloud** trước/sau A4 để định lượng tác động (A4, B9).
7. **(tuỳ chọn)** Eval anomaly có ground-truth (C12); outage dài (C14); đẩy 1 Pi tới
   trần (B10).
8. Tổng hợp **mean ± std**; lập lại các bảng/biểu đồ với thanh sai số.

### Checklist nghiệm thu "không kẽ hở"
- [ ] Cùng phần cứng cloud, có nhánh Monolithic-scaled (A1, A2).
- [ ] Cùng số window + cùng rollup hai bên (A3).
- [ ] Cloud DB batch-transaction bật; ghi nhận capacity 1GW mới (A4).
- [ ] WAN đo thật cả hai, cùng điểm đo (A5).
- [ ] Tách Storm complete_latency vs e2e DB latency, đặt tên đúng (B6).
- [ ] Listing flush()/accumulator khớp code (B7, B8).
- [ ] n≥5 run, mean±std, không loại outlier (C13).
- [ ] Năng lực biên thật + định khung lại luận điểm (B10, Nhóm A tổng kết).
- [ ] Anomaly có precision/recall hoặc hạ cấp phát biểu (C12).
- [ ] 5 lỗi nhỏ Nhóm D đã sửa.

---

## ĐÃ SỬA TRONG REPO (lần này)
- `fog-cloud/src/main/java/com/storm/iotdata/fog/CloudConfig.java` — JDBC URL thêm
  `rewriteBatchedStatements=true&cachePrepStmts=true&useServerPrepStmts=false`.
- `fog-cloud/src/main/java/com/storm/iotdata/fog/functions/FogDB_store.java` — 3 hàm
  upsert: `setAutoCommit(false)` + `commit()` (1 transaction/flush).

## VIỆC TIẾP THEO TRONG BÁO CÁO (sau khi có số liệu mới)
Cập nhật `THESIS.tex`: (a) định khung lại luận điểm trung thực; (b) thêm chương/mục
**"Threats to Validity / Hạn chế phương pháp"** gom Nhóm A+C; (c) sửa Listing 3.2 &
đặt tên latency (B6–B8); (d) thay số 318,9%/86% bằng số đo mới; (e) sửa 5 lỗi Nhóm D.

---

# ĐÁNH GIÁ TÍNH HỢP LỆ CỦA 6 KỊCH BẢN ĐO

> Kết luận ngắn: **Hệ thống chạy thật, dữ liệu có thật, nhưng THIẾT KẾ ĐO hiện tại
> CHƯA đảm bảo tính chính xác/chắc chắn.** Có 8 lỗ hổng phương pháp (bằng chứng từ
> chính script đo), trong đó vài cái làm sai lệch trực tiếp các con số tiêu đề.

## Bằng chứng từ script (file:dòng)
- `tools/observe_ramp.sh:82` (Fog) đọc complete_latency bằng **`avg(...)`**.
- `stormsmarthome/tools/observe_ramp_mono.sh:36` (Mono) đọc bằng **`max(...)`**.
  → **So sánh latency mono-vs-fog là max vs avg — không hợp lệ.**
- `observe_ramp.sh:111` & `observe_ramp_mono.sh:71`: capacity = **`max(bolts_capacity)`
  lấy 1 mẫu tức thời cuối nấc** → "169%", "91,2%", "318,9%" đều là cực đại 1 thời điểm,
  không phải giá trị ổn định.
- `observe_ramp.sh:43-46`: Fog **có đo WAN** (`cloud-mqtt` rx_bytes). `observe_ramp_mono.sh`:
  **KHÔNG có cột WAN nào** → WAN Mono chưa từng được đo (phải ước tính).
- `tools/latency_report.sh:9-10`: e2e latency Mono = `reg_date−event_ts`, Fog =
  `updatedAt−event_ts` (updatedAt luôn = lần ghi cuối) → **hai cách đo khác nhau**.
- Mỗi kịch bản đo **1 lần**, mỗi nấc lấy **1 snapshot** cuối nấc (cửa sổ STAT_DUR=60s).
- `tools/kb2_offline_recovery.sh:141,156`: queue peak/recovery **poll mỗi 5s, chạy 1 lần,
  outage chỉ 5 phút**.
- Publisher ở repo riêng, chạy **thủ công** ("HÃY BẮN DATA NGAY"), STEP_DUR phải khớp tay.

## Đánh giá từng kịch bản
| Kịch bản | Vấn đề chính | Mức độ |
|---|---|---|
| **MONO-KB1** (ramp) | capacity = max 1 mẫu; complete_latency = `max`; **không đo WAN**; 1 lần chạy | Cao |
| **MONO-KB2** (steady) | chỉ 2 snapshot (warmup/final); e2e latency dùng `reg_date` (khác Fog); 1 lần | Cao |
| **FOG-KB1-A** (8GW) | capacity = max 1 mẫu (chính là spike 91,2%); complete_latency = `avg` (lệch với Mono `max`); 1 lần | Cao |
| **FOG-KB1-B** (1GW) | **318,9% là artifact JDBC** (đã sửa A4) → kết luận "overload kiến trúc" **không hợp lệ** đến khi đo lại | Nghiêm trọng |
| **FOG-KB2-A/B** (recovery) | 1 lần chạy, outage 5'; peak poll 5s; chưa có trần outage theo dung lượng đĩa | Trung bình |
| (Energy / Anomaly) | Không phải kịch bản định lượng (chỉ minh hoạ); anomaly không có ground-truth | Cao (nếu coi là "cải tiến") |

## 8 mối đe doạ tính hợp lệ (tổng hợp)
1. **Bất đối xứng hàm tổng hợp:** latency Mono `max` vs Fog `avg`; capacity = max-tức-thời cả hai. → Sửa: **cùng một hàm** (khuyến nghị p50 + p95 + max trên cùng cửa sổ).
2. **Một mẫu / một lần chạy:** không có mean±std, không CI, không p50/p95 → không thể khẳng định chắc chắn. → Sửa: **n≥5 lần**, thu **chuỗi thời gian**, lấy thống kê trên giai đoạn ổn định mỗi nấc (bỏ 30–60s đầu mỗi nấc để tránh transient).
3. **WAN chỉ đo một phía (Fog):** Mono ước tính → "giảm 86%" không phải đo like-for-like. → Sửa: đo WAN cả hai tại **cùng điểm** (rx_bytes broker / node_exporter).
4. **Nhầm/giải thích sai latency:** complete_latency là metric Storm thật (không phải artifact updatedAt như báo cáo nói); còn e2e latency lại đo khác nhau hai phía. → Sửa: tách bạch 2 đại lượng, đo cùng cách, đặt tên đúng (xem B6).
5. **Confound chưa kiểm soát:** phần cứng (t3.large vs t3.small), workload (8 vs 7 window, có/không forecast), parallelism=1, **đo khác ngày** (Mono 18/06, Fog 28/06). → Sửa: đồng nhất + đo cùng đợt (xem A1–A3).
6. **Artifact code lẫn vào kết quả:** 318,9% do thiếu `rewriteBatchedStatements` (đã sửa). → Đo lại KB1-B.
7. **Ghép publisher–observer thủ công:** ranh giới nấc dễ lệch; snapshot cuối nấc có thể rơi vào lúc chuyển nấc. → Sửa: **tự động hoá** (1 script điều khiển cả bắn data lẫn đo, đóng dấu mốc nấc chính xác).
8. **Peak/recovery độ phân giải thô + 1 lần:** poll 5s, 1 outage 5'. → Sửa: poll dày hơn (1–2s) hoặc lấy từ counter; lặp nhiều lần; thêm 1 outage dài để minh hoạ giới hạn.

## Tiêu chí để 6 kịch bản "đủ chắc chắn"
- [ ] Dùng **cùng hàm tổng hợp** cho cả hai hệ (p50/p95/max trên cùng cửa sổ, cùng `window=600`).
- [ ] **n≥5 lần/kịch bản**, báo cáo **mean±std (hoặc CI95)**; vẽ thanh sai số.
- [ ] **Chuỗi thời gian** thay vì 1 snapshot; cắt bỏ transient đầu nấc.
- [ ] **WAN đo thật cả hai phía**, cùng điểm đo, cùng đơn vị.
- [ ] **complete_latency (Storm)** và **e2e DB latency** tách bạch, đo cùng cách hai phía.
- [ ] **Đồng nhất** phần cứng + window + forecast + parallelism; **đo cùng đợt**.
- [ ] **Đo lại KB1-B** sau fix JDBC; cập nhật mọi kết luận liên quan.
- [ ] Recovery: lặp nhiều lần + ≥1 outage dài; nêu trần outage theo dung lượng đĩa.
- [ ] Tự động hoá đồng bộ publisher↔observer; lưu log thời điểm từng nấc.

→ Khi đạt đủ các ô trên, các con số mới có thể coi là "chính xác và chắc chắn" và
phần lớn câu hỏi phản biện về phương pháp bị vô hiệu hoá.
