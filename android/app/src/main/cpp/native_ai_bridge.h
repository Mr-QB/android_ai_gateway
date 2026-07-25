#ifndef NATIVE_AI_BRIDGE_H
#define NATIVE_AI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define AI_EXPORT __declspec(dllexport)
#else
#define AI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct {
    int32_t width;
    int32_t height;
    int32_t channels;
    float inference_time_ms;
    int32_t detected_class_id;
    float confidence;
} AIInferenceResult;

AI_EXPORT int32_t get_ai_engine_version(void);

AI_EXPORT int32_t get_ncnn_has_vulkan(void);

AI_EXPORT AIInferenceResult process_image_frame(
    const uint8_t* image_bytes,
    int32_t width,
    int32_t height,
    int32_t format
);

#ifdef __cplusplus
}
#endif

#endif // NATIVE_AI_BRIDGE_H
