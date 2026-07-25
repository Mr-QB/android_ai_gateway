#include "native_ai_bridge.h"
#include <android/log.h>
#include <chrono>

#define LOG_TAG "NativeAIEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

AI_EXPORT int32_t get_ai_engine_version(void) {
    LOGI("get_ai_engine_version called from Flutter Dart FFI");
    return 100; // Version 1.0.0
}

AI_EXPORT AIInferenceResult process_image_frame(
    const uint8_t* image_bytes,
    int32_t width,
    int32_t height,
    int32_t format
) {
    auto start_time = std::chrono::high_resolution_clock::now();

    // Simulated C++ AI Preprocessing / Inference logic
    // In real implementation, pass image_bytes to OpenCV / ONNX Runtime / NNC / TFLite C API
    LOGI("Processing frame: %dx%d (Format: %d)", width, height, format);

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float, std::milli> duration = end_time - start_time;

    AIInferenceResult result;
    result.width = width;
    result.height = height;
    result.channels = 3;
    result.inference_time_ms = duration.count();
    result.detected_class_id = 1;
    result.confidence = 0.95f;

    return result;
}

}
