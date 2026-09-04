#include "yolo26_engine.h"

#include <algorithm>
#include <android/log.h>
#include <cfloat>
#include <chrono>
#include <cmath>
#include <cstring>
#include <vector>

#include "cpu.h"
#include "gpu.h"
#include "mat.h"

#define LOG_TAG "NativeAIEngine_YOLO26"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

struct Candidate {
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
    int label = -1;
    float probability = 0.0f;
};

float intersection_area(const Candidate& a, const Candidate& b) {
    const float left = std::max(a.x, b.x);
    const float top = std::max(a.y, b.y);
    const float right = std::min(a.x + a.width, b.x + b.width);
    const float bottom = std::min(a.y + a.height, b.y + b.height);

    const float width = std::max(0.0f, right - left);
    const float height = std::max(0.0f, bottom - top);
    return width * height;
}

void sort_candidates(std::vector<Candidate>& candidates) {
    std::sort(
        candidates.begin(),
        candidates.end(),
        [](const Candidate& a, const Candidate& b) {
            return a.probability > b.probability;
        }
    );
}

void nms_sorted_bboxes(
    const std::vector<Candidate>& candidates,
    std::vector<int>& picked,
    float nms_threshold
) {
    picked.clear();

    std::vector<float> areas(candidates.size());
    for (size_t i = 0; i < candidates.size(); ++i) {
        areas[i] = candidates[i].width * candidates[i].height;
    }

    for (size_t i = 0; i < candidates.size(); ++i) {
        const Candidate& a = candidates[i];
        bool keep = true;

        for (int picked_index : picked) {
            const Candidate& b = candidates[picked_index];

            // Class-aware NMS
            if (a.label != b.label) {
                continue;
            }

            const float inter = intersection_area(a, b);
            const float union_area = areas[i] + areas[picked_index] - inter;
            const float iou = union_area > 0.0f ? (inter / union_area) : 0.0f;

            if (iou > nms_threshold) {
                keep = false;
                break;
            }
        }

        if (keep) {
            picked.push_back(static_cast<int>(i));
        }
    }
}

} // namespace

Yolo26Engine::~Yolo26Engine() {
    unload();
}

void Yolo26Engine::clear_unlocked() {
    net_.clear();
    loaded_ = false;
    using_gpu_ = false;
}

int Yolo26Engine::load(
    const char* param_path,
    const char* bin_path,
    bool request_gpu
) {
    std::lock_guard<std::mutex> guard(mutex_);
    clear_unlocked();

    if (param_path == nullptr ||
        bin_path == nullptr ||
        std::strlen(param_path) == 0 ||
        std::strlen(bin_path) == 0) {
        LOGE("YOLO26 model paths are invalid");
        return -1;
    }

    int thread_count = ncnn::get_big_cpu_count();
    if (thread_count < 1) {
        thread_count = 1;
    }

    ncnn::set_cpu_powersave(2);
    ncnn::set_omp_num_threads(thread_count);

    bool enable_gpu = false;
#if NCNN_VULKAN
    if (request_gpu) {
        const int gpu_count = ncnn::get_gpu_count();
        enable_gpu = gpu_count > 0;
        LOGI("YOLO26 GPU requested. NCNN GPU count: %d", gpu_count);
    }
#else
    (void)request_gpu;
#endif

    net_.opt = ncnn::Option();
    net_.opt.num_threads = thread_count;
    net_.opt.use_fp16_packed = true;
    net_.opt.use_fp16_storage = true;
    net_.opt.use_fp16_arithmetic = true;
#if NCNN_VULKAN
    net_.opt.use_vulkan_compute = enable_gpu;
#endif

    LOGI("Loading YOLO26 param: %s", param_path);
    const int param_result = net_.load_param(param_path);
    if (param_result != 0) {
        LOGE("Failed to load YOLO26 param. Code: %d", param_result);
        clear_unlocked();
        return -2;
    }

    LOGI("Loading YOLO26 bin: %s", bin_path);
    const int model_result = net_.load_model(bin_path);
    if (model_result != 0) {
        LOGE("Failed to load YOLO26 bin. Code: %d", model_result);
        clear_unlocked();
        return -3;
    }

    loaded_ = true;
    using_gpu_ = enable_gpu;
    LOGI(
        "YOLO26n model loaded successfully. Backend: %s, threads: %d",
        using_gpu_ ? "Vulkan GPU" : "CPU",
        thread_count
    );
    return 0;
}

int Yolo26Engine::detect(
    const uint8_t* rgb_bytes,
    int width,
    int height,
    std::vector<Yolo26Object>& objects,
    float probability_threshold,
    float nms_threshold,
    float* inference_time_ms
) {
    std::lock_guard<std::mutex> guard(mutex_);
    objects.clear();

    if (inference_time_ms != nullptr) {
        *inference_time_ms = 0.0f;
    }

    if (!loaded_) {
        return -1;
    }

    if (rgb_bytes == nullptr || width <= 0 || height <= 0) {
        return -2;
    }

    probability_threshold = std::clamp(probability_threshold, 0.01f, 0.99f);
    nms_threshold = std::clamp(nms_threshold, 0.01f, 0.99f);

    const auto start = std::chrono::high_resolution_clock::now();

    // Letterbox preserving aspect ratio to target_size_ (640x640)
    const float scale = std::min(
        static_cast<float>(target_size_) / static_cast<float>(width),
        static_cast<float>(target_size_) / static_cast<float>(height)
    );

    const int resized_w = std::clamp(
        static_cast<int>(std::round(width * scale)),
        1,
        target_size_
    );
    const int resized_h = std::clamp(
        static_cast<int>(std::round(height * scale)),
        1,
        target_size_
    );

    const int wpad = target_size_ - resized_w;
    const int hpad = target_size_ - resized_h;
    const int top = hpad / 2;
    const int bottom = hpad - top;
    const int left = wpad / 2;
    const int right = wpad - left;

    ncnn::Mat input = ncnn::Mat::from_pixels_resize(
        rgb_bytes,
        ncnn::Mat::PIXEL_RGB,
        width,
        height,
        resized_w,
        resized_h
    );

    if (input.empty()) {
        return -3;
    }

    ncnn::Mat padded_input;
    ncnn::copy_make_border(
        input,
        padded_input,
        top,
        bottom,
        left,
        right,
        ncnn::BORDER_CONSTANT,
        114.0f
    );

    padded_input.substract_mean_normalize(mean_values_, norm_values_);

    ncnn::Extractor extractor = net_.create_extractor();
    if (extractor.input("in0", padded_input) != 0) {
        LOGE("YOLO26 input 'in0' failed");
        return -3;
    }

    ncnn::Mat pred;
    if (extractor.extract("out0", pred) != 0) {
        LOGE("YOLO26 extract 'out0' failed");
        return -3;
    }

    // Expected shape: dims=2, w=8400, h=84
    // Row 0..3: cx, cy, w, h
    // Row 4..83: 80 class sigmoid probabilities
    if (pred.dims != 2 || pred.h < 5) {
        LOGE("YOLO26 unexpected output shape: dims=%d, w=%d, h=%d", pred.dims, pred.w, pred.h);
        return -3;
    }

    const int num_proposals = pred.w;
    const int num_classes = pred.h - 4;

    const float* ptr_cx = pred.row(0);
    const float* ptr_cy = pred.row(1);
    const float* ptr_w  = pred.row(2);
    const float* ptr_h  = pred.row(3);

    std::vector<Candidate> candidates;
    candidates.reserve(64);

    for (int i = 0; i < num_proposals; ++i) {
        int best_label = -1;
        float best_score = 0.0f;

        for (int c = 0; c < num_classes; ++c) {
            const float score = pred.row(4 + c)[i];
            if (score > best_score) {
                best_score = score;
                best_label = c;
            }
        }

        if (best_score < probability_threshold) {
            continue;
        }

        const float cx = ptr_cx[i];
        const float cy = ptr_cy[i];
        const float bw = ptr_w[i];
        const float bh = ptr_h[i];

        // Map back from 640x640 padded letterbox coordinates to original image coordinates
        float orig_x0 = (cx - 0.5f * bw - static_cast<float>(left)) / scale;
        float orig_y0 = (cy - 0.5f * bh - static_cast<float>(top)) / scale;
        float orig_x1 = (cx + 0.5f * bw - static_cast<float>(left)) / scale;
        float orig_y1 = (cy + 0.5f * bh - static_cast<float>(top)) / scale;

        orig_x0 = std::clamp(orig_x0, 0.0f, static_cast<float>(width));
        orig_y0 = std::clamp(orig_y0, 0.0f, static_cast<float>(height));
        orig_x1 = std::clamp(orig_x1, 0.0f, static_cast<float>(width));
        orig_y1 = std::clamp(orig_y1, 0.0f, static_cast<float>(height));

        const float box_w = orig_x1 - orig_x0;
        const float box_h = orig_y1 - orig_y0;

        if (box_w > 1.0f && box_h > 1.0f) {
            Candidate candidate;
            candidate.x = orig_x0;
            candidate.y = orig_y0;
            candidate.width = box_w;
            candidate.height = box_h;
            candidate.label = best_label;
            candidate.probability = best_score;
            candidates.push_back(candidate);
        }
    }

    if (!candidates.empty()) {
        sort_candidates(candidates);
        std::vector<int> picked;
        nms_sorted_bboxes(candidates, picked, nms_threshold);

        objects.reserve(picked.size());
        for (int index : picked) {
            const Candidate& c = candidates[index];
            Yolo26Object obj;
            obj.class_id = c.label;
            obj.confidence = c.probability;
            obj.x = c.x;
            obj.y = c.y;
            obj.width = c.width;
            obj.height = c.height;
            objects.push_back(obj);
        }
    }

    const auto end = std::chrono::high_resolution_clock::now();
    const std::chrono::duration<float, std::milli> duration = end - start;

    if (inference_time_ms != nullptr) {
        *inference_time_ms = duration.count();
    }

    LOGI(
        "YOLO26 detected %zu objects in %.2f ms",
        objects.size(),
        duration.count()
    );

    return 0;
}

void Yolo26Engine::unload() {
    std::lock_guard<std::mutex> guard(mutex_);
    clear_unlocked();
    LOGI("YOLO26 model unloaded");
}

bool Yolo26Engine::is_loaded() const {
    std::lock_guard<std::mutex> guard(mutex_);
    return loaded_;
}

bool Yolo26Engine::is_using_gpu() const {
    std::lock_guard<std::mutex> guard(mutex_);
    return loaded_ && using_gpu_;
}
