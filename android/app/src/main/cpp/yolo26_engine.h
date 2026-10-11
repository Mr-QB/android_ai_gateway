#ifndef YOLO26_ENGINE_H
#define YOLO26_ENGINE_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#include "net.h"

// Trạng thái vòng đời của model YOLO
enum class EngineState {
    UNLOADED = 0,
    LOADING = 1,
    READY = 2,
    ERROR = 3
};

// Cấu hình backend suy luận
enum class BackendMode {
    CPU = 0,
    VULKAN = 1,
    AUTO = 2
};

struct Yolo26Object {
    int32_t class_id = -1;
    float confidence = 0.0f;
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
};

struct Yolo26ProfilingMetrics {
    float preprocess_time_ms = 0.0f;
    float inference_time_ms = 0.0f;
    float postprocess_time_ms = 0.0f;
    float total_native_time_ms = 0.0f;
};

// Reusable memory workspace để loại bỏ malloc/free ở từng frame
struct FrameWorkspace {
    std::vector<uint8_t> rgb_buffer;
    std::vector<uint8_t> rotated_yuv_buffer;

    void ensure_rgb_capacity(size_t size) {
        if (rgb_buffer.size() < size) {
            rgb_buffer.resize(size);
        }
    }

    void ensure_rotated_yuv_capacity(size_t size) {
        if (rotated_yuv_buffer.size() < size) {
            rotated_yuv_buffer.resize(size);
        }
    }
};

class Yolo26Engine {
public:
    Yolo26Engine() = default;
    ~Yolo26Engine();

    Yolo26Engine(const Yolo26Engine&) = delete;
    Yolo26Engine& operator=(const Yolo26Engine&) = delete;

    // Tải mô hình với lựa chọn backend và số luồng CPU
    int load(
        const char* param_path,
        const char* bin_path,
        BackendMode backend_mode = BackendMode::AUTO,
        int num_threads = 0
    );

    // Tương thích ngược: use_gpu = 1 -> VULKAN, 0 -> CPU
    int load_legacy(
        const char* param_path,
        const char* bin_path,
        bool request_gpu
    );

    // Suy luận từ buffer RGB
    int detect_rgb(
        const uint8_t* rgb_bytes,
        int width,
        int height,
        std::vector<Yolo26Object>& objects,
        float probability_threshold,
        float nms_threshold,
        Yolo26ProfilingMetrics* metrics
    );

    // Suy luận trực tiếp từ camera YUV420SP (NV21/NV12)
    int detect_yuv420sp(
        const uint8_t* yuv_bytes,
        int width,
        int height,
        int rotation_degrees,
        bool is_nv12,
        std::vector<Yolo26Object>& objects,
        float probability_threshold,
        float nms_threshold,
        Yolo26ProfilingMetrics* metrics
    );

    void unload();
    bool is_loaded() const;
    bool is_using_gpu() const;
    int get_thread_count() const;
    EngineState get_state() const;

private:
    void clear_unlocked();

    mutable std::mutex mutex_;
    ncnn::Net net_;

    std::atomic<EngineState> state_{EngineState::UNLOADED};
    bool using_gpu_ = false;
    int configured_threads_ = 0;

    const int target_size_ = 640;
    const float mean_values_[3] = {0.0f, 0.0f, 0.0f};
    const float norm_values_[3] = {
        1.0f / 255.0f,
        1.0f / 255.0f,
        1.0f / 255.0f,
    };

    FrameWorkspace workspace_;
};

// Worker luồng nền C++ xử lý hàng đợi latest-frame (queue capacity <= 1)
class Yolo26FrameWorker {
public:
    explicit Yolo26FrameWorker(Yolo26Engine& engine);
    ~Yolo26FrameWorker();

    void start();
    void stop();
    bool is_running() const;

    // Gửi frame camera vào queue: nếu worker đang bận, frame cũ trong hàng đợi sẽ bị drop
    bool push_yuv_frame(
        const uint8_t* yuv_bytes,
        int width,
        int height,
        int rotation_degrees,
        bool is_nv12,
        float probability_threshold,
        float nms_threshold
    );

    // Đọc kết quả nhận diện mới nhất (không block)
    int get_latest_results(
        Yolo26Object* output,
        int max_output,
        Yolo26ProfilingMetrics* metrics,
        uint64_t* frame_id
    );

    void get_stats(int32_t* received, int32_t* processed, int32_t* dropped);
    void reset_stats();

private:
    void worker_loop();

    Yolo26Engine& engine_;
    std::thread worker_thread_;
    std::mutex queue_mutex_;
    std::condition_variable cv_;
    std::atomic<bool> running_{false};

    // Frame đang chờ xử lý (Queue size = 1)
    std::vector<uint8_t> pending_bytes_;
    int pending_width_ = 0;
    int pending_height_ = 0;
    int pending_rotation_ = 0;
    bool pending_is_nv12_ = false;
    float pending_prob_thresh_ = 0.40f;
    float pending_nms_thresh_ = 0.50f;
    bool has_pending_frame_ = false;

    // Kết quả inference mới nhất
    std::mutex results_mutex_;
    std::vector<Yolo26Object> latest_detections_;
    Yolo26ProfilingMetrics latest_metrics_{};
    uint64_t frame_counter_ = 0;

    // Thống kê frames
    std::atomic<int32_t> received_frames_{0};
    std::atomic<int32_t> processed_frames_{0};
    std::atomic<int32_t> dropped_frames_{0};
};

#endif // YOLO26_ENGINE_H
