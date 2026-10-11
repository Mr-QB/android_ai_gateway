#include "native_ai_bridge.h"

#include <algorithm>
#include <android/log.h>
#include <chrono>
#include <memory>
#include <vector>

#include "gpu.h"
#include "net.h"
#include "yolo26_engine.h"

#define LOG_TAG "NativeAIEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {
Yolo26Engine g_yolo26_engine;
std::unique_ptr<Yolo26FrameWorker> g_yolo26_worker;
}

extern "C" {

AI_EXPORT int32_t get_ai_engine_version(void) {
    return 140; // 1.4.0: Realtime YUV Stream + Worker + Profiling Metrics
}

AI_EXPORT int32_t get_ncnn_has_vulkan(void) {
#if NCNN_VULKAN
    return ncnn::get_gpu_count() > 0 ? 1 : 0;
#else
    return 0;
#endif
}

AI_EXPORT int32_t load_yolo26_model_v2(
    const char* param_path,
    const char* bin_path,
    int32_t backend_mode,
    int32_t num_threads
) {
    BackendMode mode = BackendMode::AUTO;
    if (backend_mode == 0) mode = BackendMode::CPU;
    else if (backend_mode == 1) mode = BackendMode::VULKAN;

    const int ret = g_yolo26_engine.load(param_path, bin_path, mode, num_threads);
    if (ret == 0) {
        if (!g_yolo26_worker) {
            g_yolo26_worker = std::make_unique<Yolo26FrameWorker>(g_yolo26_engine);
        }
    }
    return ret;
}

AI_EXPORT int32_t load_yolo26_model(
    const char* param_path,
    const char* bin_path,
    int32_t use_gpu
) {
    return load_yolo26_model_v2(
        param_path,
        bin_path,
        use_gpu == 1 ? 1 : 0,
        0
    );
}

AI_EXPORT int32_t is_yolo26_model_loaded(void) {
    return g_yolo26_engine.is_loaded() ? 1 : 0;
}

AI_EXPORT int32_t get_yolo26_backend(void) {
    if (!g_yolo26_engine.is_loaded()) {
        return -1;
    }
    return g_yolo26_engine.is_using_gpu() ? 1 : 0;
}

AI_EXPORT int32_t get_yolo26_threads(void) {
    return g_yolo26_engine.get_thread_count();
}

AI_EXPORT void unload_yolo26_model(void) {
    if (g_yolo26_worker) {
        g_yolo26_worker->stop();
        g_yolo26_worker.reset();
    }
    g_yolo26_engine.unload();
}

AI_EXPORT int32_t detect_rgb_image(
    const uint8_t* rgb_bytes,
    int32_t width,
    int32_t height,
    float probability_threshold,
    float nms_threshold,
    AIDetection* output,
    int32_t max_output,
    float* inference_time_ms
) {
    if (output == nullptr || max_output <= 0 || inference_time_ms == nullptr) {
        return -4;
    }

    AIProfilingMetrics metrics{};
    const int count = detect_rgb_image_with_metrics(
        rgb_bytes,
        width,
        height,
        probability_threshold,
        nms_threshold,
        output,
        max_output,
        &metrics
    );

    *inference_time_ms = metrics.inference_time_ms;
    return count;
}

AI_EXPORT int32_t detect_rgb_image_with_metrics(
    const uint8_t* rgb_bytes,
    int32_t width,
    int32_t height,
    float probability_threshold,
    float nms_threshold,
    AIDetection* output,
    int32_t max_output,
    AIProfilingMetrics* metrics
) {
    if (output == nullptr || max_output <= 0) {
        return -4;
    }

    std::vector<Yolo26Object> objects;
    Yolo26ProfilingMetrics p_metrics{};

    const int result = g_yolo26_engine.detect_rgb(
        rgb_bytes,
        width,
        height,
        objects,
        probability_threshold,
        nms_threshold,
        &p_metrics
    );

    if (result != 0) {
        return result;
    }

    if (metrics != nullptr) {
        metrics->preprocess_time_ms = p_metrics.preprocess_time_ms;
        metrics->inference_time_ms = p_metrics.inference_time_ms;
        metrics->postprocess_time_ms = p_metrics.postprocess_time_ms;
        metrics->total_native_time_ms = p_metrics.total_native_time_ms;
    }

    const int count = std::min(
        static_cast<int>(objects.size()),
        static_cast<int>(max_output)
    );

    for (int index = 0; index < count; ++index) {
        output[index].class_id = objects[index].class_id;
        output[index].confidence = objects[index].confidence;
        output[index].x = objects[index].x;
        output[index].y = objects[index].y;
        output[index].width = objects[index].width;
        output[index].height = objects[index].height;
    }

    return count;
}

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
) {
    if (output == nullptr || max_output <= 0) {
        return -4;
    }

    std::vector<Yolo26Object> objects;
    Yolo26ProfilingMetrics p_metrics{};

    const int result = g_yolo26_engine.detect_yuv420sp(
        yuv_bytes,
        width,
        height,
        rotation_degrees,
        is_nv12 == 1,
        objects,
        probability_threshold,
        nms_threshold,
        &p_metrics
    );

    if (result != 0) {
        return result;
    }

    if (metrics != nullptr) {
        metrics->preprocess_time_ms = p_metrics.preprocess_time_ms;
        metrics->inference_time_ms = p_metrics.inference_time_ms;
        metrics->postprocess_time_ms = p_metrics.postprocess_time_ms;
        metrics->total_native_time_ms = p_metrics.total_native_time_ms;
    }

    const int count = std::min(
        static_cast<int>(objects.size()),
        static_cast<int>(max_output)
    );

    for (int index = 0; index < count; ++index) {
        output[index].class_id = objects[index].class_id;
        output[index].confidence = objects[index].confidence;
        output[index].x = objects[index].x;
        output[index].y = objects[index].y;
        output[index].width = objects[index].width;
        output[index].height = objects[index].height;
    }

    return count;
}

// -----------------------------------------------------------------------------
// Realtime FrameWorker Implementation
// -----------------------------------------------------------------------------

AI_EXPORT int32_t start_yolo26_worker(void) {
    if (!g_yolo26_engine.is_loaded()) {
        return -1;
    }
    if (!g_yolo26_worker) {
        g_yolo26_worker = std::make_unique<Yolo26FrameWorker>(g_yolo26_engine);
    }
    g_yolo26_worker->start();
    return 0;
}

AI_EXPORT void stop_yolo26_worker(void) {
    if (g_yolo26_worker) {
        g_yolo26_worker->stop();
    }
}

AI_EXPORT int32_t is_yolo26_worker_running(void) {
    return (g_yolo26_worker && g_yolo26_worker->is_running()) ? 1 : 0;
}

AI_EXPORT int32_t push_yolo26_yuv_frame(
    const uint8_t* yuv_bytes,
    int32_t width,
    int32_t height,
    int32_t rotation_degrees,
    int32_t is_nv12,
    float probability_threshold,
    float nms_threshold
) {
    if (!g_yolo26_worker || !g_yolo26_worker->is_running()) {
        return -1;
    }
    const bool pushed = g_yolo26_worker->push_yuv_frame(
        yuv_bytes,
        width,
        height,
        rotation_degrees,
        is_nv12 == 1,
        probability_threshold,
        nms_threshold
    );
    return pushed ? 0 : -2;
}

AI_EXPORT int32_t get_yolo26_latest_results(
    AIDetection* output,
    int32_t max_output,
    AIProfilingMetrics* metrics,
    uint64_t* frame_id
) {
    if (!g_yolo26_worker) {
        return -1;
    }

    std::vector<Yolo26Object> objects(max_output);
    Yolo26ProfilingMetrics p_metrics{};

    const int count = g_yolo26_worker->get_latest_results(
        objects.data(),
        max_output,
        &p_metrics,
        frame_id
    );

    if (metrics != nullptr) {
        metrics->preprocess_time_ms = p_metrics.preprocess_time_ms;
        metrics->inference_time_ms = p_metrics.inference_time_ms;
        metrics->postprocess_time_ms = p_metrics.postprocess_time_ms;
        metrics->total_native_time_ms = p_metrics.total_native_time_ms;
    }

    for (int i = 0; i < count; ++i) {
        output[i].class_id = objects[i].class_id;
        output[i].confidence = objects[i].confidence;
        output[i].x = objects[i].x;
        output[i].y = objects[i].y;
        output[i].width = objects[i].width;
        output[i].height = objects[i].height;
    }

    return count;
}

AI_EXPORT void get_yolo26_worker_stats(
    int32_t* received,
    int32_t* processed,
    int32_t* dropped
) {
    if (g_yolo26_worker) {
        g_yolo26_worker->get_stats(received, processed, dropped);
    } else {
        if (received) *received = 0;
        if (processed) *processed = 0;
        if (dropped) *dropped = 0;
    }
}

AI_EXPORT void reset_yolo26_worker_stats(void) {
    if (g_yolo26_worker) {
        g_yolo26_worker->reset_stats();
    }
}

// -----------------------------------------------------------------------------
// Legacy Aliases
// -----------------------------------------------------------------------------
AI_EXPORT AIInferenceResult process_image_frame(
    const uint8_t* image_bytes,
    int32_t width,
    int32_t height,
    int32_t format
) {
    (void)image_bytes;
    (void)format;
    AIInferenceResult result{};
    result.width = width;
    result.height = height;
    result.channels = 3;
    result.inference_time_ms = 0.0f;
    result.detected_class_id = -1;
    result.confidence = 0.0f;
    return result;
}

AI_EXPORT int32_t load_nanodet_model(const char* p, const char* b, int32_t g) {
    return load_yolo26_model(p, b, g);
}
AI_EXPORT int32_t is_nanodet_model_loaded(void) {
    return is_yolo26_model_loaded();
}
AI_EXPORT int32_t get_nanodet_backend(void) {
    return get_yolo26_backend();
}
AI_EXPORT void unload_nanodet_model(void) {
    unload_yolo26_model();
}

} // extern "C"
