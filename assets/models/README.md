# AI Models

Thư mục này chứa các file mô hình chạy on-device bằng framework **NCNN**:

## Mô hình hiện tại: YOLO26n (Ultralytics)

* **Tên file**: `yolo26n.param` và `yolo26n.bin`
* **Nguồn gốc**: [Ultralytics YOLO26](https://github.com/ultralytics/ultralytics) (Phát hành đầu năm 2026)
* **Kích thước đầu vào (Input Resolution)**: `640x640` (RGB)
* **Kiểu dữ liệu (Quantization)**: `FP16` (Half precision)
* **Số lượng tham số**: ~2.56M parameters (~4.9 MB model size)
* **Đặc điểm kiến trúc**:
  * **NMS-Free / End-to-End architecture**: Loại bỏ Non-Maximum Suppression phức tạp trên CPU, tối ưu hóa tốc độ suy luận trực tiếp trên mobile.
  * **DFL-Free (Distribution Focal Loss)**: Graph tính toán tinh gọn, loại bỏ các bước giải mã anchor phân phối phức tạp.
  * **Chuẩn hóa đầu vào**: `mean = [0, 0, 0]`, `norm = [1/255, 1/255, 1/255]`
  * **Số lớp phát hiện**: 80 lớp COCO (person, bicycle, car, motorcycle, bus, truck, dog, cat, v.v.)
  * **Tensor đầu ra (NCNN `out0`)**: `[84, 8400]` (4 tọa độ `cx, cy, w, h` + 80 xác suất lớp đã qua hàm Sigmoid trực tiếp trong graph).

## Hướng dẫn xuất (Export) mô hình từ Python

Để xuất lại hoặc tùy chỉnh mô hình YOLO26n sang định dạng NCNN:

```bash
# 1. Cài đặt Ultralytics
pip install -U ultralytics

# 2. Xuất mô hình YOLO26n sang NCNN với độ phân giải 640x640 và FP16
python -c "from ultralytics import YOLO; model = YOLO('yolo26n.pt'); model.export(format='ncnn', imgsz=640, half=True)"

# 3. Copy các file model.ncnn.param và model.ncnn.bin vào thư mục này và đổi tên thành:
#    assets/models/yolo26n.param
#    assets/models/yolo26n.bin
```
