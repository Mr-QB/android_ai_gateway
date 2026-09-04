#ifndef YOLO26_ENGINE_H
#define YOLO26_ENGINE_H

#include <cstdint>
#include <mutex>
#include <vector>

#include "net.h"

struct Yolo26Object {
    int32_t class_id = -1;
    float confidence = 0.0f;
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
};

class Yolo26Engine {
public:
    Yolo26Engine() = default;
    ~Yolo26Engine();

    Yolo26Engine(const Yolo26Engine&) = delete;
    Yolo26Engine& operator=(const Yolo26Engine&) = delete;

    int load(
        const char* param_path,
        const char* bin_path,
        bool request_gpu
    );

    int detect(
        const uint8_t* rgb_bytes,
        int width,
        int height,
        std::vector<Yolo26Object>& objects,
        float probability_threshold,
        float nms_threshold,
        float* inference_time_ms
    );

    void unload();
    bool is_loaded() const;
    bool is_using_gpu() const;

private:
    void clear_unlocked();

    mutable std::mutex mutex_;
    ncnn::Net net_;

    bool loaded_ = false;
    bool using_gpu_ = false;

    const int target_size_ = 640;
    const float mean_values_[3] = {0.0f, 0.0f, 0.0f};
    const float norm_values_[3] = {
        1.0f / 255.0f,
        1.0f / 255.0f,
        1.0f / 255.0f,
    };
};

#endif // YOLO26_ENGINE_H
