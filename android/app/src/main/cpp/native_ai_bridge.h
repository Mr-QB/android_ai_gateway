#ifndef NATIVE_AI_BRIDGE_H
#define NATIVE_AI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define AI_EXPORT __declspec(dllexport)
#else
#define AI_EXPORT \
    __attribute__((visibility("default"))) \
    __attribute__((used))
#endif

// Metrics chi tiết từng giai đoạn suy luận
typedef struct {
    float preprocess_time_ms;
    float inference_time_ms;
    float postprocess_time_ms;
    float total_native_time_ms;
} AIProfilingMetrics;

// Cấu trúc một vật thể phát hiện
typedef struct {
    int32_t class_id;
    float confidence;
    float x;
    float y;
    float width;
    float height;
} AIDetection;

// Thông tin engine
AI_EXPORT int32_t get_ai_engine_version(void);
AI_EXPORT int32_t get_ncnn_has_vulkan(void);

// Quản lý model YOLO26
// backend_mode: 0 = CPU, 1 = VULKAN, 2 = AUTO
// num_threads: 0 = AUTO (big cores), hoặc 1..N
AI_EXPORT int32_t load_yolo26_model_v2(
    const char* param_path,
    const char* bin_path,
    int32_t backend_mode,
    int32_t num_threads
);

// Tương thích ngược: use_gpu = 1 -> VULKAN, 0 -> CPU
AI_EXPORT int32_t load_yolo26_model(
    const char* param_path,
    const char* bin_path,
    int32_t use_gpu
);

AI_EXPORT int32_t is_yolo26_model_loaded(void);
AI_EXPORT int32_t get_yolo26_backend(void);
AI_EXPORT int32_t get_yolo26_threads(void);
AI_EXPORT void unload_yolo26_model(void);

// Suy luận đồng bộ từ RGB (tương thích ngược)
AI_EXPORT int32_t detect_rgb_image(
    const uint8_t* rgb_bytes,
    int32_t width,
    int32_t height,
    float probability_threshold,
    float nms_threshold,
    AIDetection* output,
    int32_t max_output,
    float* inference_time_ms
);

// Suy luận đồng bộ từ RGB với full metrics
AI_EXPORT int32_t detect_rgb_image_with_metrics(
    const uint8_t* rgb_bytes,
    int32_t width,
    int32_t height,
    float probability_threshold,
    float nms_threshold,
    AIDetection* output,
    int32_t max_output,
    AIProfilingMetrics* metrics
);

// Suy luận đồng bộ trực tiếp từ Camera YUV420SP (NV21 / NV12)
AI_EXPORT int32_t detect_yuv420_sp(
    const uint8_t* yuv_bytes,
    int32_t width,
    int32_t height,
    int32_t rotation_degrees,
    int32_t is_nv12,
    float probability_threshold,
    float nms_threshold,
    AIDetection* output,
    int32_t max_output,
    AIProfilingMetrics* metrics
);

// -----------------------------------------------------------------------------
// Realtime FrameWorker API (Queue size = 1, Drop-frame, không block UI)
// -----------------------------------------------------------------------------
AI_EXPORT int32_t start_yolo26_worker(void);
AI_EXPORT void stop_yolo26_worker(void);
AI_EXPORT int32_t is_yolo26_worker_running(void);

AI_EXPORT int32_t push_yolo26_yuv_frame(
    const uint8_t* yuv_bytes,
    int32_t width,
    int32_t height,
    int32_t rotation_degrees,
    int32_t is_nv12,
    float probability_threshold,
    float nms_threshold
);

AI_EXPORT int32_t get_yolo26_latest_results(
    AIDetection* output,
    int32_t max_output,
    AIProfilingMetrics* metrics,
    uint64_t* frame_id
);

AI_EXPORT void get_yolo26_worker_stats(
    int32_t* received,
    int32_t* processed,
    int32_t* dropped
);

AI_EXPORT void reset_yolo26_worker_stats(void);

// -----------------------------------------------------------------------------
// Legacy & Deprecated Aliases (cho tương thích ngược)
// -----------------------------------------------------------------------------
typedef struct {
    int32_t width;
    int32_t height;
    int32_t channels;
    float inference_time_ms;
    int32_t detected_class_id;
    float confidence;
} AIInferenceResult;

// DEPRECATED: Giữ lại để không phá FFI cũ nếu có caller nào vẫn tham chiếu
AI_EXPORT AIInferenceResult process_image_frame(
    const uint8_t* image_bytes,
    int32_t width,
    int32_t height,
    int32_t format
);

AI_EXPORT int32_t load_nanodet_model(const char* p, const char* b, int32_t g);
AI_EXPORT int32_t is_nanodet_model_loaded(void);
AI_EXPORT int32_t get_nanodet_backend(void);
AI_EXPORT void unload_nanodet_model(void);

#ifdef __cplusplus
}
#endif

#endif // NATIVE_AI_BRIDGE_H
