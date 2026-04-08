# Benchmark Metrics Documentation
*Tài liệu giải thích chi tiết các chỉ số đo lường (Metrics) được sử dụng để đánh giá hiệu suất hệ thống Apache Storm khi so sánh cụm kiến trúc Monolithic (Cloud-only) và Split (Gateway/Cloud).*

---

## 1. Metric Nhóm: End-to-End Latency & Throughput (Trễ Toàn Cục & Thông Lượng)

### 1.1 Topology Complete Latency (`topology_stats_complete_latency`)
*   **Định nghĩa:** Là tổng thời gian trung bình (được tính bằng mili-giây - ms) từ lúc một "Tuple" (tin nhắn) gốc được Spout bắn ra, đi qua toàn bộ các Bolt định tuyến trong Topology cho đến khi Spout gốc nhận lại tín hiệu ACK (chứng tỏ toàn bộ quá trình đã xử lý thành công).
*   **Trong Prometheus / Grafana:** Hiển thị trực tiếp qua biến `topology_stats_complete_latency`.
*   **Áp dụng so sánh kiến trúc:** 
    *   Trong cấu trúc Monolithic (Cloud-only), các tiến trình chia sẻ chung cùng một máy chủ hoặc mạng nội bộ tốc độ cao nên latency này thường cực thấp.
    *   Trong cấu trúc Split (Gateway/Cloud), khi Worker 1 trên Gateway chuyển dữ liệu cho Worker 2 trên Cloud qua mạng Internet, Latency này sẽ phình to rõ rệt. Khoảng chênh lệch của chỉ số này đo lường chính xác "chi phí độ trễ (Network Penalty)" mà hệ thống phải đánh đổi khi tách cấu trúc ra biên (Edge/Gateway).

### 1.2 Rate of Messages Acked / Throughput (`rate(topology_stats_acked[1m])`)
*   **Định nghĩa:** Tốc độ xử lý hoàn tất các tin nhắn tính trên mỗi giây (ops/s).
*   **Trong Prometheus / Grafana:** Dùng biểu thức `rate(topology_stats_acked[1m])` lấy tốc độ trung bình trong từng phút của biến đếm tổng (counter) các lệnh ack.
*   **Áp dụng so sánh kiến trúc:**
    *   So sánh trực tiếp để thấy thông lượng cực đại của hệ thống. Nếu sau khi chia thành mô hình Split, Throughput sụt giảm mạnh mẽ so với mô hình nguyên khối, thì nút thắt thắt cổ chai (bottleneck) về Network Bandwidth đã bóp nghẹt hệ thống, khiến Cloud Supervisor không thể xử lý dữ liệu với tốc độ như cũ.

### 1.3 Spouts Emitted Rate (`rate(spouts_emitted[1m])`)
*   **Định nghĩa:** Tốc độ sinh ra (phát dữ liệu) của Spout trong 1 giây (Ops/s).
*   **Áp dụng so sánh kiến trúc:** Khi kết hợp so sánh với chỉ số `Acked Rate` phía trên, nếu Spouts phát ra (Emitted) với tốc độ cao nhưng luồng xử lý trọn vẹn (Acked) ở mức rất thấp, điều đó đồng nghĩa với việc các tin nhắn đang bị quá tải (backpressure) hoặc bị tắc nghẽn trong các hàng đợi (ZeroMQ / Netty buffer queue) giữa Gateway và Cloud.

---

## 2. Metric Nhóm: Bolt Processing Internal (Độ Trễ Phân Mảnh)

Trong quá trình xử lý của một Bolt bất kỳ, Storm chia cấu trúc thời gian ra làm hai phần cụ thể: `Execute` (thời gian chạy logic) và `Process` (thời gian logic + thời gian mạng / hàng đợi).

### 2.1 Bolt Execute Latency (`bolts_execute_latency`)
*   **Định nghĩa:** Là thời gian thuần túy (ms) để Storm gọi hàm `execute(tuple)` trong code Java của Bolt. Cụ thể là thời gian CPU tập trung chạy các thuật toán nghiệp vụ.
*   **Áp dụng so sánh kiến trúc:** Giả định logic thuật toán không đổi, thời gian thực thi (execute latency) này ở hai cấu hình (Monolithic vs. Split) về lý thuyết là **phải tương đồng nhau**. Nếu chênh lệch, chứng tỏ cấu hình máy vật lý ở 2 môi trường này không cân bằng về sức mạnh CPU cấp phát.

### 2.2 Bolt Process Latency (`bolts_process_latency`)
*   **Định nghĩa:** Mất bao lâu kể từ khi một tuple được Bolt đó "nhận" cho đến khi logic xử lý xong và Bolt đó phát lệnh "ack()" xác nhận là xong.
*   **Áp dụng so sánh kiến trúc:** Giai đoạn từ Execute -> Ack ẩn chứa thời gian để đẩy dữ liệu xuống hàng đợi Transfer Thread của worker ra ngoài đường truyền mạng. 
    *   *Trọng điểm Benchmarks:* Khi so sánh, hãy lấy `bolts_process_latency - bolts_execute_latency`. Khác biệt (delta) này càng lớn, chứng tỏ mạng (Network Channel) bị chậm hoặc việc báo tín hiệu ACK giữa các nút đang mắc kẹt do độ trễ truyền dữ liệu Internet. Mô hình Split chắc chắn sẽ để lộ sự bất lợi lớn ở Delta này so với Monolithic.

### 2.3 Bolt Capacity (`bolts_capacity`)
*   **Định nghĩa:** Được tính gần đúng dựa trên công thức `(Số tuples chạy * Thời gian execute trung bình) / Khung cửa sổ thời gian`. Giá trị chạy từ 0 đến 1 (hoặc hiển thị dạng % đến 100%).
*   **Ý nghĩa:** Một Bolt có Capacity ở mức `0.9 - 1.0` (90%-100%) nghĩa là nó đang hoạt động cật lực, chạy code `execute` liên tục không ngừng nghỉ.
*   **Áp dụng so sánh kiến trúc:** Bộc lộ khả năng cân bằng tải (Load Balancing). Trong bộ Monolithic, nếu Capacity của tất cả Bolt chạm ngưỡng 1.0, chứng tỏ CPU nút đó dồn cục đã kiệt sức. Trong mô hình Split, bạn mong chờ việc điều hướng các AI/Logic Bolt nặng nhọc lên các Cloud Worker sẽ giúp giải phóng mức Capacity, để Gateway Spout/Bolts hoạt động dưới 50%. Đây là bằng chứng lợi ích tốt nhất cho cấu hình Split.

---

## 3. Metric Nhóm: Cluster Scale & Resource Allocation (Tài Nguyên Cụm)

### 3.1 Worker Cluster Used & Total (`worker_cluster_used` vs `worker_cluster_total`)
*   **Định nghĩa:** Tổng số worker slots (các tiến trình JVM chạy trên port 6700, 6701...) được thiết lập (total) và hiện tại được chiếm dụng (used) bởi ứng dụng Storm trên từng Supervisor Node.
*   **Áp dụng so sánh kiến trúc:**
    *   Tính công bằng của Scheduler: Bằng biểu đồ bar gauge, bạn có thể thấy rõ các workers điều phối (Topology tasks) đang dồn vào địa chỉ IP của Cloud? Hay dồn vào Gateway?
    *   Nếu là Cụm Monolithic: Node đó sẽ load full các slot Worker Used.
    *   Nếu Cụm Split phối hợp với tag-aware scheduler: Khẳng định rằng thuật toán cấp phát có hoạt động, chuyển các worker phân tách cụ thể trên hai host khác nhau một cách lành mạnh thay vì để trống slot một bên.

---
**Tổng Kết Nhận Định:**
Chất lượng đánh giá (Benchmark Report) giữa mô hình Split IoT/Edge và Monolithic sẽ dựa vào **sự đối đầu giữa 2 thế lực**: "Sức tải của Worker Capacity" (Giảm tải độ kiệt sức CPU cho máy biên/Gateway) và "Network Penalty" (Cái giá thời gian trễ độ Process Latency và End-to-End vì truyền tải xa). Đồ thị Grafana sẽ chứng minh ngưỡng giới hạn mà việc đánh đổi là hợp lý cho dự án.
