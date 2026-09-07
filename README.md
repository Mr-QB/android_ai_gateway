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
   - Từ lần chạy thứ 2 trở đi (**Warm Inference**), trọng số mô hình, OpenCL GPU shaders, tokenizer và bộ nhớ đệm được **tái sử dụng 100%**, thời gian **Model Load = 0 ms**.
   - Mỗi câu hỏi/ảnh mới chỉ khởi tạo `Conversation(ConversationConfig())` siêu nhẹ (< 5 ms) trên warm engine có sẵn, giúp dọn sạch KV-cache của ảnh trước và tránh tràn giới hạn context token (`Task failed with state: 7`).

2. **Cơ chế Chuyển đổi Model An toàn (Xiaomi 12T - RAM 8GB)**:
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

## 📥 Hướng dẫn Tải & Nạp Model vào Xiaomi 12T bằng ADB

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

## 📊 Kết quả Benchmark Tham khảo (Xiaomi 12T - MediaTek Dimensity 8100-Ultra / GPU Mali-G610 MC6)

### SmolVLM2-500M (OpenCL GPU Delegate)
* **Cold Start Load**: ~6,800 ms (biên dịch OpenCL kernels vào Mali-G610 VRAM).
* **Warm Model Load**: **0 ms** (Engine resident).
* **TTFT (Time To First Token)**: ~350 - 550 ms.
* **Tốc độ sinh (Decode Speed)**: ~14 - 18 tokens/giây.
* **Bộ nhớ RAM sử dụng**: Native Heap ~800 MB, Java Heap ~18 MB.

### Gemma-4-E2B-it (GPU Bundle)
* **Cold Start Load**: ~12,000 - 16,000 ms.
* **Warm Model Load**: **0 ms** (Engine resident).
* **TTFT**: ~1,200 - 1,800 ms.
* **Tốc độ sinh (Decode Speed)**: ~6 - 9 tokens/giây.
* **Bộ nhớ RAM sử dụng**: Native Heap ~3.2 GB, Java Heap ~24 MB.
