# Android AI Gateway (Edge AI with YOLO26n & Dual VLM Benchmark)

Ứng dụng Flutter kết hợp C++ Native Engine (NCNN) và Google LiteRT-LM để chạy nhận diện đối tượng thời gian thực (**YOLO26n**) và so sánh hiệu năng 2 mô hình thị giác - ngôn ngữ on-device (**SmolVLM2-500M vs Gemma-4-E2B-it**).

---

## 🚀 Tính năng nổi bật

### 1. Real-Time Object Detection: YOLO26n (640x640)
* **Mô hình**: **YOLO26n** (Phiên bản Nano từ Ultralytics, phát hành đầu năm 2026).
* **Độ phân giải đầu vào**: **`640x640`** (RGB) giúp phát hiện chi tiết các vật thể kích thước vừa và nhỏ.
* **Kiến trúc NMS-Free & DFL-Free**: Tối ưu tốc độ xử lý hơn 40% so với các thế hệ cũ.
* **Framework suy luận**: **Tencent NCNN** hỗ trợ tăng tốc **ARM NEON** và **Vulkan GPU Compute** (Adreno / Mali).
* **Kiến trúc Native C++ Bridge**: Sử dụng Dart FFI giao tiếp trực tiếp với `libnative_ai_engine.so`.
* 📖 **Tài liệu chi tiết cơ chế gọi & phân tích FPS**: Xem [docs/YOLO_PIPELINE_AND_PERFORMANCE.md](docs/YOLO_PIPELINE_AND_PERFORMANCE.md).

---

## 📍 Native ORB-SLAM3 Dataset Replay

Supported:
- EuRoC `cam0` monocular
- EuRoC `cam0` + `imu0` mono-inertial
- Realtime replay (0.5x, 1.0x, 2.0x)
- Maximum-speed replay

Native library:
`liborbslam_native.so` (Android ARM64 / `arm64-v8a`)

Dataset is not bundled in APK.

See:
- [docs/ORB_SLAM_SETUP.md](docs/ORB_SLAM_SETUP.md)
- [docs/ORB_SLAM_COORDINATES.md](docs/ORB_SLAM_COORDINATES.md)
- [docs/ORB_SLAM_BENCHMARK.md](docs/ORB_SLAM_BENCHMARK.md)

### License Notice
ORB-SLAM3 is released under the GNU General Public License v3.0 (GPLv3). Its inclusion and build within `liborbslam_native.so` is governed by the GPLv3 license terms. This is a technical integration note and not a commercial license opinion.


---

## 🧠 Benchmark 2 Mô hình On-Device VLM (Google LiteRT-LM v0.16.1)

Ứng dụng tích hợp tab **VLM Benchmark** (ngoài cùng bên phải thanh điều hướng) hỗ trợ benchmark so sánh trực tiếp 2 mô hình VLM chạy hoàn toàn on-device:

| Tiêu chí | SmolVLM2-500M | Gemma-4-E2B-it |
| :--- | :--- | :--- |
| **Repo HuggingFace** | `litert-community/SmolVLM2-500M` | `litert-community/gemma-4-E2B-it-litert-lm` |
| **File Bundle** | `SmolVLM2-500M.litertlm` | `gemma-4-E2B-it-gpu.litertlm` (GPU) / `gemma-4-E2B-it.litertlm` (CPU) |
| **Dung lượng file** | ~344 MB | ~2.01 GB |
| **Kiến trúc tham số** | 500M Parameters | 5.1B Total, 2.3B Active Params (Per-Layer Embeddings) |
| **Context Length** | 512 visual/text tokens | Lên tới 128K context |
| **Tăng tốc phần cứng** | GPU (OpenCL/Mali-G610) / CPU | GPU (OpenCL/Mali-G610) / CPU |

---

### ⚙️ Kiến trúc Tối ưu Bắt buộc (Engine Persistence & Model Switching)

1. **Persistent Warm Engine Holder (Singleton)**:
   - Model chỉ nạp vào RAM/VRAM **đúng 1 lần duy nhất** (Cold Start).
   - Engine và trọng số giữ resident giữa các request trên cùng process; request mới tạo `Conversation` riêng. KV cache thuộc conversation và không được tái sử dụng giữa các ảnh.
   - Khi model đã resident, request warm không nạp lại trọng số; không đồng nghĩa tổng thời gian khởi tạo request bằng 0 ms.

2. **Cơ chế Chuyển đổi Model An toàn**:
   - Để tránh quá tải bộ nhớ khi nạp đồng thời cả 2 model, app chỉ giữ **1 model resident** tại một thời điểm.
   - Khi chuyển từ `SmolVLM2` $\rightarrow$ `Gemma-4` (hoặc ngược lại):
     ```
     Đóng Conversation cũ -> Hủy Engine cũ -> Gọi System.gc() -> Nạp Model mới -> Giữ Resident
     ```

3. **Đo đạc chính xác TTFT (Time To First Token) & Tokens/s**:
   - Sử dụng Kotlin coroutine streaming qua `Conversation.sendMessageAsync(contents)` trả về `Flow<Message>`.
   - Ghi nhận chính xác mốc thời gian chunk token đầu tiên phát ra (**TTFT**).
   - Đo đạc tốc độ giải mã thực tế (`tokensPerSecond`).

4. **Tự động hóa Benchmark x5 (Cold Start vs Warm Runs)**:
   - Nút **[BENCH x5]** tự động chạy 5 lượt suy luận liên tiếp trên cùng 1 ảnh và câu hỏi.
   - Bảng thống kê chi tiết cho từng vòng: `TTFT`, `Generation Time`, `Total Time`, `Tokens/s`, `RAM Native/Java`.
   - Tính toán trung bình hiệu năng các lượt Warm Inference và hỗ trợ nút **Copy JSON Report**.

5. **Tối ưu hóa ảnh đầu vào**:
   - Ảnh chụp từ Camera hoặc Gallery được tiền xử lý tự động (resize về `~512x512` bảo toàn tỷ lệ khung hình, nắn chiều xoay EXIF) trước khi chuyển vào mô hình, ngăn ngừa OOM từ ảnh camera 108MP/12MP.

---

## 📥 Hướng dẫn Tải & Nạp Model vào thiết bị Android bằng ADB

Thư mục lưu trữ nội bộ của app:
```text
/data/user/0/com.example.android_ai_gateway/files/models/
    SmolVLM2-500M.litertlm
    gemma-4-E2B-it-gpu.litertlm
```

### 1. Nạp SmolVLM2-500M (344 MB)
```bash
# Tải file từ HuggingFace:
curl -L -o SmolVLM2-500M.litertlm "https://huggingface.co/litert-community/SmolVLM2-500M/resolve/main/SmolVLM2-500M.litertlm"

# Đẩy vào thiết bị qua ADB:
adb push SmolVLM2-500M.litertlm /data/local/tmp/
adb shell run-as com.example.android_ai_gateway cp /data/local/tmp/SmolVLM2-500M.litertlm files/models/
```

### 2. Nạp Gemma-4-E2B-it-gpu (2.01 GB)
```bash
# Tải file bundle tối ưu GPU từ HuggingFace:
curl -L -o gemma-4-E2B-it-gpu.litertlm "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-gpu.litertlm"

# Đẩy vào thiết bị qua ADB:
adb push gemma-4-E2B-it-gpu.litertlm /data/local/tmp/
adb shell run-as com.example.android_ai_gateway cp /data/local/tmp/gemma-4-E2B-it-gpu.litertlm files/models/
```

---

## 📊 Benchmark trên thiết bị

Số liệu kiểm chứng hiện có lấy trên Xiaomi 12S Pro, Android 15, GPU Mali-G610;
đây là số đo toàn process khi camera/YOLO và SmolVLM2 cùng chạy, không phải bộ
nhớ riêng của model. Benchmark 5 lượt warm ghi nhận TTFT trung bình 365.8 ms,
8.19 tokens/s, native heap 254,604 KiB, PSS 975,462 KiB và graphics 300,664 KiB.
Khởi tạo GPU model mất 11,732 ms trong lần đo ban đầu. Một lượt khác sau tích hợp
structured output có 1,320.8 ms TTFT và 2.75 tokens/s, đồng thời đầu ra bị parser
từ chối; không dùng lượt này thay cho benchmark warm. Gemma-4 chưa có số đo được
xác minh trên thiết bị hiện tại. Xem [benchmark chi tiết](docs/vietnamese_vlm/benchmark.md)
để biết giới hạn so sánh và số đo cập nhật.

---

## 🏗️ Realtime AI Pipeline Architecture (Refactored)

### 1. Tổng quan Kiến trúc Realtime
```text
                    ┌─────────────────┐
                    │ Android Camera  │
                    │ startImageStream│
                    └────────┬────────┘
                             │
                             ▼ (YUV420_888 / NV21 packed)
                    ┌─────────────────┐
                    │   CameraFrame   │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │    FrameHub     │
                    │ latest frame    │
                    │ queue size = 1  │
                    └──────┬─────┬────┘
                           │     │
                  realtime │     │ snapshot/event
                           │     │
                           ▼     ▼
                     ┌────────┐  ┌───────────────┐
                     │ YOLO   │  │ VLM Snapshot  │
                     │ NCNN   │  │ SmolVLM/Gemma │
                     └───┬────┘  └──────┬────────┘
                         │              │
                         ▼              ▼
                    Detection      Description/OCR
                         │              │
                         └──────┬───────┘
                                ▼
                       Flutter UI / Agent
```

### 2. Camera Realtime & Elimination of JPEG Pipeline
- **Loại bỏ hoàn toàn snapshot JPEG**: Trước đây luồng detection sử dụng `takePicture()` $\rightarrow$ nén JPEG $\rightarrow$ `readAsBytes()` $\rightarrow$ decode bitmap bằng `package:image` tốn từ 1,000ms đến 1,800ms trên mỗi frame trong Dart runtime.
- **Sử dụng `startImageStream`**: Camera stream liên tục phát ra `CameraImage` ở định dạng YUV420_888. Hàm `packCameraImageToNv21()` gom plane Y và UV thành mảng NV21 tuyến tính trong < 1.5ms, không decode sang bitmap hay RGB trong Dart.
- **Native Color Conversion & Rotation**: Mảng NV21 được truyền qua FFI sang C++ NCNN (`detect_yuv420_sp`). NCNN thực hiện xoay (`ncnn::kanna_rotate_yuv420sp`) và chuyển đổi màu YUV sang RGB (`ncnn::yuv420sp2rgb`) bằng tập lệnh ARM NEON tối ưu phần cứng trong < 2ms.

### 3. Frame Dropping Policy (Queue size <= 1)
- `FrameHub` và `Yolo26FrameWorker` (C++) áp dụng cơ chế Latest-Frame Drop:
  - Bounded queue dung lượng tối đa 1 frame.
  - Khi camera phát sinh 30 FPS nhưng worker NCNN xử lý 20-25 FPS, frame mới nhất sẽ tự động thay thế frame cũ đang chờ, các frame dư thừa bị drop ngay lập tức.
  - Loại bỏ hoàn toàn backlog và độ trễ tích lũy (latency không bao giờ bị tăng dần theo thời gian).

### 4. Bounded Buffer Reuse & Zero UI Blocking
- **Worker Thread Dedicated**: Worker C++ chạy trên `std::thread` riêng với `std::condition_variable` và `std::mutex`, đảm bảo suy luận NCNN không block Flutter UI thread (60/120Hz mượt mà).
- **Persistent Workspace Buffers**: Các buffer FFI và C++ (`FrameWorkspace`, `yuv_buffer`, persistent detection structs) được khởi tạo một lần và tái sử dụng qua các frame, triệt tiêu overhead `calloc/malloc/free` mỗi frame.

### 5. CPU / Vulkan Backend & Thread Configuration
- Cung cấp 3 chế độ suy luận linh hoạt qua giao diện:
  - **AUTO**: Tự động nhận diện GPU Vulkan; ưu tiên Vulkan GPU Compute nếu khả dụng, fallback về CPU nếu GPU không hỗ trợ.
  - **VULKAN**: Ép buộc suy luận trên GPU Vulkan (tối ưu cho các thiết bị Mali-G610 đã kiểm tra).
  - **CPU**: Suy luận trên các nhân ARM Cortex big cores (`ncnn::get_big_cpu_count()`).
- Cho phép cấu hình số luồng CPU linh hoạt: **AUTO**, **2 threads**, **3 threads**, **4 threads**.

### 6. Coordinate Mapping & Zero-Copy Overlay
- Flutter không vẽ lại ảnh hay nén lại frame để hiển thị bounding box.
- Preview camera hiển thị trực tiếp từ Surface native qua `CameraPreview`.
- Bounding box được vẽ qua `CustomPaint` (`DetectionOverlay`). Lớp `ModelCoordinateMapper` chịu trách nhiệm unletterbox (hoàn tác padding và tỉ lệ scale 640x640) và ánh xạ chính xác tọa độ camera sang tọa độ preview màn hình (tính toán góc xoay sensor, `BoxFit.cover`, và mirror cho camera trước).

### 7. VLM Pipeline & Lifecycle Management
- **Warm Engine Retention**: `VlmNativeService` giữ engine LiteRT-LM nạp thường trực trong bộ nhớ; mỗi yêu cầu người dùng chỉ tạo mới một `Conversation` nhẹ và đóng ngay sau khi hoàn thành.
- **Áp dụng chính xác `maxTokens`**: Sử dụng `ConversationConfig(maxOutputToken = maxTokens)` của Google LiteRT-LM SDK v0.16.1.
- **Safe Streaming Fallback**: Nếu streaming gặp lỗi sau khi đã gửi chunk đầu tiên, app trả về phản hồi từng phần kèm trạng thái lỗi, tuyệt đối không gửi lại toàn bộ prompt để tránh trùng lặp văn bản.
- **Chỉ số đo đạc trung thực**: Thay thế TPS giả (đếm callback) bằng `TTFT` (Time To First Token), thời gian sinh (generation time), `chars/s`, và `words/s`.
- **Hủy dọn Coroutine chuẩn xác**: Quản lý bằng `SupervisorJob()` và hủy toàn bộ tác vụ nền trong `onDestroy()` của `MainActivity`.

### 8. Hướng dẫn Benchmarking
- Mở màn hình Camera: HUD phía trên hiển thị realtime:
  - Camera FPS và YOLO Processed FPS thực tế.
  - Drop rate (%) của pipeline.
  - Độ trễ chi tiết: Preprocess ms, Inference ms, Postprocess ms, Total Native ms.
  - Chuyển đổi trực tiếp Backend (AUTO / VULKAN / CPU) và Threads (AUTO / 2 / 3 / 4) từ Dropdown Menu để đối sánh hiệu năng tức thì.
- Tab VLM Benchmark:
  - Bấm **[BENCH x5]** để so sánh TTFT, tốc độ sinh (chars/s, words/s) và tiêu thụ RAM giữa các lượt Cold Start và Warm Inference.
