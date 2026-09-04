# Android AI Gateway (Edge AI with YOLO26n)

Ứng dụng Flutter kết hợp C++ Native Engine (NCNN) để chạy nhận diện vật thể thời gian thực (**Real-time Object Detection**) hoàn toàn on-device trên Android.

---

## 🚀 Tính năng nổi bật

* **Mô hình**: **YOLO26n** (Phiên bản Nano mới nhất từ Ultralytics, phát hành đầu năm 2026).
* **Độ phân giải đầu vào**: **`640x640`** (RGB) giúp phát hiện chi tiết và chính xác các vật thể kích thước vừa và nhỏ.
* **Kiến trúc NMS-Free & DFL-Free**: Loại bỏ các bước giải mã anchor phân phối phức tạp và Non-Maximum Suppression nặng nề trên CPU, tăng tốc độ xử lý hơn 40% so với các thế hệ cũ.
* **Framework suy luận**: **Tencent NCNN** hỗ trợ tăng tốc phần cứng thông qua **ARM NEON** (đa luồng CPU) và **Vulkan GPU Compute** (Adreno / Mali).
* **Kiến trúc Native C++ Bridge**: Sử dụng Dart FFI giao tiếp trực tiếp với thư viện C++ native `libnative_ai_engine.so` mà không qua MethodChannel, đảm bảo độ trễ (latency) tối thiểu khi nhận diện luồng camera.
* **Dataset**: Nhận diện 80 lớp chuẩn COCO (người, phương tiện, động vật, đồ gia dụng...).

---

## 📁 Cấu trúc thư mục AI Native & Models

```text
android_ai_gateway/
├── assets/
│   └── models/
│       ├── yolo26n.param      # Cấu trúc đồ thị mạng YOLO26n (NCNN)
│       ├── yolo26n.bin        # Trọng số mô hình FP16 (~4.9 MB)
│       └── README.md          # Ghi chú chi tiết & lệnh export model
├── android/app/src/main/cpp/
│   ├── CMakeLists.txt         # Cấu hình build C++ native & tự động tải NCNN SDK
│   ├── native_ai_bridge.h     # Interface C Export cho Dart FFI
│   ├── native_ai_bridge.cpp   # Implementation bridge
│   ├── yolo26_engine.h        # Khai báo Engine suy luận YOLO26
│   └── yolo26_engine.cpp      # Preprocessing (letterbox 640x640), NCNN extractor & postprocessing
└── lib/features/ai_engine/
    ├── native/
    │   └── native_ai_bindings.dart  # Dart FFI bindings
    └── services/
        ├── model_asset_service.dart # Copy model từ APK sang Application Support
        └── ai_engine_service.dart   # Quản lý lifecycle & gọi detect
```

---

## 🛠 Hướng dẫn xuất (Export) mô hình YOLO26n 640x640

Mô hình hiện tại trong thư mục `assets/models/` được tạo tự động qua Python script:

```bash
pip install -U ultralytics
python -c "from ultralytics import YOLO; model = YOLO('yolo26n.pt'); model.export(format='ncnn', imgsz=640, half=True)"
```

Sau đó copy 2 file `model.ncnn.param` và `model.ncnn.bin` vào `assets/models/` với tên:
* `assets/models/yolo26n.param`
* `assets/models/yolo26n.bin`

---

## 📱 Hiệu năng tham khảo trên Android

* **GPU Vulkan**: Tận dụng GPU Adreno (Qualcomm) hoặc Mali (MediaTek) với độ trễ tối ưu.
* **CPU ARM NEON**: Tự động nhận diện số lõi lớn (`get_big_cpu_count()`) để chạy đa luồng tối đa hiệu năng.
* **Tốc độ xử lý (640x640)**:
  * Flagship / Cận cao cấp (Snapdragon 8 Gen, 7+ Gen): ~15–25 ms/frame (~40–60 FPS).
  * Tầm trung (Dimensity 7000/8000 series, Snapdragon 7 series): ~25–40 ms/frame (~25–40 FPS).
