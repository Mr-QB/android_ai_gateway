#include "native_ai_bridge.h"
#include <android/log.h>
#include <chrono>

// NCNN Includes
#include "net.h"
#include "gpu.h"

#define LOG_TAG "NativeAIEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

AI_EXPORT int32_t get_ai_engine_version(void) {
    LOGI("get_ai_engine_version called from Flutter Dart FFI");
    return 100; // Version 1.0.0
}

AI_EXPORT int32_t get_ncnn_has_vulkan(void) {
#if NCNN_VULKAN
    int has_khr = ncnn::get_gpu_count() > 0;
    LOGI("NCNN Vulkan GPU Count: %d", ncnn::get_gpu_count());
    return has_khr ? 1 : 0;
#else
    LOGI("NCNN compiled without Vulkan support");
    return 0;
#endif
}

AI_EXPORT AIInferenceResult process_image_frame(
    const uint8_t* image_bytes,
    int32_t width,
    int32_t height,
    int32_t format
) {
    auto start_time = std::chrono::high_resolution_clock::now();

    LOGI("NCNN Processing frame: %dx%d (Format: %d)", width, height, format);

    // Demonstration of NCNN Mat creation
    if (image_bytes != nullptr && width > 0 && height > 0) {
        ncnn::Mat in = ncnn::Mat::from_pixels(image_bytes, ncnn::Mat::PIXEL_RGB, width, height);
        LOGI("NCNN Mat created successfully: %dx%d, channels: %d", in.w, in.h, in.c);
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float, std::milli> duration = end_time - start_time;

    AIInferenceResult result;
    result.width = width;
    result.height = height;
    result.channels = 3;
    result.inference_time_ms = duration.count();
    result.detected_class_id = 1;
    result.confidence = 0.98f;

    return result;
}

}
