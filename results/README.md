# results/ — HỆ FOG

Mỗi kịch bản 1 thư mục; log/CSV tự lưu, ảnh bạn paste vào `img/`.

```
results/
  kb1-A-multi8gw/   # KB1 scalability, 8 gateway (30')
    img/            # ← paste ảnh
    sim_A-multi8gw_scalability.csv ; latency_fog_*.csv
  kb1-B-single/     # KB1 scalability, 1 gateway
    img/  ; sim_B-single_scalability.csv ; latency_fog_*.csv
  kb2-A-multi8gw/   # KB2 cloud offline→recovery, 8 gateway
    img/  ; kb2_offline_*.md
  kb2-B-single/     # KB2, 1 gateway
    img/  ; kb2_offline_*.md
```
Quy trình mỗi kịch bản: đo → latency_report → reset_fog → bật lại gateway → kịch bản kế. Xem DO_DAC.md.
