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
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
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

inline float intersection_area(const Candidate& a, const Candidate& b) {
    const float left = std::max(a.x, b.x);
    const float top = std::max(a.y, b.y);
    const float right = std::min(a.x + a.width, b.x + b.width);
    const float bottom = std::min(a.y + a.height, b.y + b.height);

    const float width = std::max(0.0f, right - left);
    const float height = std::max(0.0f, bottom - top);
    return width * height;
}

inline void sort_candidates(std::vector<Candidate>& candidates) {
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
    state_ = EngineState::UNLOADED;
    using_gpu_ = false;
    configured_threads_ = 0;
}

int Yolo26Engine::load_legacy(
    const char* param_path,
    const char* bin_path,
    bool request_gpu
) {
    return load(
        param_path,
        bin_path,
        request_gpu ? BackendMode::VULKAN : BackendMode::CPU,
        0
    );
}

int Yolo26Engine::load(
    const char* param_path,
    const char* bin_path,
    BackendMode backend_mode,
    int num_threads
) {
    std::lock_guard<std::mutex> guard(mutex_);
    clear_unlocked();
    state_ = EngineState::LOADING;

    if (param_path == nullptr || bin_path == nullptr ||
        std::strlen(param_path) == 0 || std::strlen(bin_path) == 0) {
        LOGE("YOLO26 model paths are invalid");
        state_ = EngineState::ERROR;
        return -1;
    }

    // Configure CPU threads
    int thread_count = num_threads;
    if (thread_count <= 0) {
        thread_count = ncnn::get_big_cpu_count();
        if (thread_count < 1) {
            thread_count = 1;
        }
    }

    ncnn::set_cpu_powersave(2); // Bind to big/performance cores
    ncnn::set_omp_num_threads(thread_count);

    bool want_gpu = false;
#if NCNN_VULKAN
    const int gpu_count = ncnn::get_gpu_count();
    if (backend_mode == BackendMode::VULKAN) {
        want_gpu = gpu_count > 0;
        if (!want_gpu) {
            LOGW("Vulkan requested but no GPU found. Falling back to CPU.");
        }
    } else if (backend_mode == BackendMode::AUTO) {
        want_gpu = gpu_count > 0;
    }
#else
    if (backend_mode == BackendMode::VULKAN) {
        LOGW("NCNN was compiled without Vulkan. Falling back to CPU.");
    }
#endif

    // Attempt loading with Vulkan first if requested
    bool loaded_successfully = false;
    if (want_gpu) {
        net_.opt = ncnn::Option();
        net_.opt.num_threads = thread_count;
        net_.opt.use_fp16_packed = true;
        net_.opt.use_fp16_storage = true;
        net_.opt.use_fp16_arithmetic = true;
#if NCNN_VULKAN
        net_.opt.use_vulkan_compute = true;
#endif
        LOGI("Attempting YOLO26 load on Vulkan GPU (threads=%d)...", thread_count);
        if (net_.load_param(param_path) == 0 && net_.load_model(bin_path) == 0) {
            loaded_successfully = true;
            using_gpu_ = true;
            LOGI("YOLO26 successfully loaded on Vulkan GPU");
        } else {
            LOGW("Failed to load on Vulkan GPU. Retrying on CPU...");
            net_.clear();
        }
    }

    // Fallback to CPU if not loaded yet
    if (!loaded_successfully) {
        net_.opt = ncnn::Option();
        net_.opt.num_threads = thread_count;
        net_.opt.use_fp16_packed = true;
        net_.opt.use_fp16_storage = true;
        net_.opt.use_fp16_arithmetic = true;
#if NCNN_VULKAN
        net_.opt.use_vulkan_compute = false;
#endif
        LOGI("Loading YOLO26 on CPU (threads=%d)...", thread_count);
        if (net_.load_param(param_path) != 0) {
            LOGE("Failed to load YOLO26 param file on CPU");
            clear_unlocked();
            state_ = EngineState::ERROR;
            return -2;
        }
        if (net_.load_model(bin_path) != 0) {
            LOGE("Failed to load YOLO26 bin file on CPU");
            clear_unlocked();
            state_ = EngineState::ERROR;
            return -3;
        }
        using_gpu_ = false;
    }

    configured_threads_ = thread_count;
    state_ = EngineState::READY;
    LOGI(
        "YOLO26 model READY. Backend: %s, threads: %d",
        using_gpu_ ? "Vulkan GPU" : "CPU",
        configured_threads_
    );
    return 0;
}

int Yolo26Engine::detect_rgb(
    const uint8_t* rgb_bytes,
    int width,
    int height,
    std::vector<Yolo26Object>& objects,
    float probability_threshold,
    float nms_threshold,
    Yolo26ProfilingMetrics* metrics
) {
    std::lock_guard<std::mutex> guard(mutex_);
    objects.clear();

    if (metrics != nullptr) {
        *metrics = Yolo26ProfilingMetrics{};
    }

    if (state_ != EngineState::READY) {
        return -1;
    }

    if (rgb_bytes == nullptr || width <= 0 || height <= 0) {
        return -2;
    }

    probability_threshold = std::clamp(probability_threshold, 0.01f, 0.99f);
    nms_threshold = std::clamp(nms_threshold, 0.01f, 0.99f);

    const auto t_total_start = std::chrono::high_resolution_clock::now();

    // 1. PREPROCESSING: Letterbox preserving aspect ratio
    const auto t_pre_start = std::chrono::high_resolution_clock::now();

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
    const auto t_pre_end = std::chrono::high_resolution_clock::now();

    // 2. INFERENCE: NCNN graph execution
    const auto t_inf_start = std::chrono::high_resolution_clock::now();
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
    const auto t_inf_end = std::chrono::high_resolution_clock::now();

    // 3. POSTPROCESSING: Proposal decoding & class-aware NMS
    const auto t_post_start = std::chrono::high_resolution_clock::now();

    // Output shape: dims=2, w=8400, h=84
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

        // Map back from 640x640 letterbox coordinates to original image coordinates
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
    const auto t_post_end = std::chrono::high_resolution_clock::now();
    const auto t_total_end = std::chrono::high_resolution_clock::now();

    if (metrics != nullptr) {
        metrics->preprocess_time_ms = std::chrono::duration<float, std::milli>(t_pre_end - t_pre_start).count();
        metrics->inference_time_ms = std::chrono::duration<float, std::milli>(t_inf_end - t_inf_start).count();
        metrics->postprocess_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
        metrics->total_native_time_ms = std::chrono::duration<float, std::milli>(t_total_end - t_total_start).count();
    }

    return 0;
}

int Yolo26Engine::detect_yuv420sp(
    const uint8_t* yuv_bytes,
    int width,
    int height,
    int rotation_degrees,
    bool is_nv12,
    std::vector<Yolo26Object>& objects,
    float probability_threshold,
    float nms_threshold,
    Yolo26ProfilingMetrics* metrics
) {
    if (yuv_bytes == nullptr || width <= 0 || height <= 0) {
        return -2;
    }

    const auto t_yuv_start = std::chrono::high_resolution_clock::now();

    // Map rotation degrees to NCNN kanna_rotate type:
    // 0 = no rotation
    // 90 = rotate 90 deg clockwise (type 1)
    // 180 = rotate 180 deg (type 2)
    // 270 = rotate 270 deg (type 3)
    int rot_type = 0;
    if (rotation_degrees == 90) rot_type = 1;
    else if (rotation_degrees == 180) rot_type = 2;
    else if (rotation_degrees == 270) rot_type = 3;

    int eff_width = width;
    int eff_height = height;
    const uint8_t* eff_yuv = yuv_bytes;

    if (rot_type != 0) {
        const size_t yuv_size = static_cast<size_t>(width * height * 3 / 2);
        workspace_.ensure_rotated_yuv_capacity(yuv_size);

        if (rot_type == 1 || rot_type == 3) {
            eff_width = height;
            eff_height = width;
        }

        ncnn::kanna_rotate_yuv420sp(
            yuv_bytes,
            width,
            height,
            workspace_.rotated_yuv_buffer.data(),
            eff_width,
            eff_height,
            rot_type
        );
        eff_yuv = workspace_.rotated_yuv_buffer.data();
    }

    // Convert YUV420SP (NV21 / NV12) directly to RGB in native memory
    const size_t rgb_size = static_cast<size_t>(eff_width * eff_height * 3);
    workspace_.ensure_rgb_capacity(rgb_size);

    if (is_nv12) {
        ncnn::yuv420sp2rgb_nv12(eff_yuv, eff_width, eff_height, workspace_.rgb_buffer.data());
    } else {
        ncnn::yuv420sp2rgb(eff_yuv, eff_width, eff_height, workspace_.rgb_buffer.data());
    }

    const auto t_yuv_end = std::chrono::high_resolution_clock::now();
    const float yuv_prep_ms = std::chrono::duration<float, std::milli>(t_yuv_end - t_yuv_start).count();

    // Run core detection on the converted RGB frame
    Yolo26ProfilingMetrics sub_metrics{};
    const int ret = detect_rgb(
        workspace_.rgb_buffer.data(),
        eff_width,
        eff_height,
        objects,
        probability_threshold,
        nms_threshold,
        &sub_metrics
    );

    if (metrics != nullptr) {
        metrics->preprocess_time_ms = sub_metrics.preprocess_time_ms + yuv_prep_ms;
        metrics->inference_time_ms = sub_metrics.inference_time_ms;
        metrics->postprocess_time_ms = sub_metrics.postprocess_time_ms;
        metrics->total_native_time_ms = sub_metrics.total_native_time_ms + yuv_prep_ms;
    }

    return ret;
}

void Yolo26Engine::unload() {
    std::lock_guard<std::mutex> guard(mutex_);
    clear_unlocked();
    LOGI("YOLO26 model unloaded");
}

bool Yolo26Engine::is_loaded() const {
    return state_ == EngineState::READY;
}

bool Yolo26Engine::is_using_gpu() const {
    return state_ == EngineState::READY && using_gpu_;
}

int Yolo26Engine::get_thread_count() const {
    return configured_threads_;
}

EngineState Yolo26Engine::get_state() const {
    return state_;
}

// -----------------------------------------------------------------------------
// Yolo26FrameWorker Implementation
// -----------------------------------------------------------------------------

Yolo26FrameWorker::Yolo26FrameWorker(Yolo26Engine& engine)
    : engine_(engine) {}

Yolo26FrameWorker::~Yolo26FrameWorker() {
    stop();
}

void Yolo26FrameWorker::start() {
    if (running_.exchange(true)) {
        return; // Already running
    }
    worker_thread_ = std::thread(&Yolo26FrameWorker::worker_loop, this);
    LOGI("Yolo26FrameWorker thread started");
}

void Yolo26FrameWorker::stop() {
    if (!running_.exchange(false)) {
        return; // Already stopped
    }
    cv_.notify_all();
    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }
    LOGI("Yolo26FrameWorker thread stopped");
}

bool Yolo26FrameWorker::is_running() const {
    return running_;
}

bool Yolo26FrameWorker::push_yuv_frame(
    const uint8_t* yuv_bytes,
    int width,
    int height,
    int rotation_degrees,
    bool is_nv12,
    float probability_threshold,
    float nms_threshold
) {
    if (!running_ || yuv_bytes == nullptr || width <= 0 || height <= 0) {
        return false;
    }

    const size_t yuv_size = static_cast<size_t>(width * height * 3 / 2);
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);

        // If there is already an unprocessed pending frame, it gets dropped
        if (has_pending_frame_) {
            dropped_frames_++;
        }

        if (pending_bytes_.size() < yuv_size) {
            pending_bytes_.resize(yuv_size);
        }
        std::memcpy(pending_bytes_.data(), yuv_bytes, yuv_size);

        pending_width_ = width;
        pending_height_ = height;
        pending_rotation_ = rotation_degrees;
        pending_is_nv12_ = is_nv12;
        pending_prob_thresh_ = probability_threshold;
        pending_nms_thresh_ = nms_threshold;
        has_pending_frame_ = true;

        received_frames_++;
    }

    cv_.notify_one();
    return true;
}

int Yolo26FrameWorker::get_latest_results(
    Yolo26Object* output,
    int max_output,
    Yolo26ProfilingMetrics* metrics,
    uint64_t* frame_id
) {
    std::unique_lock<std::mutex> lock(results_mutex_);
    if (latest_detections_.empty()) {
        if (metrics != nullptr) *metrics = latest_metrics_;
        if (frame_id != nullptr) *frame_id = frame_counter_;
        return 0;
    }

    const int count = std::min(static_cast<int>(latest_detections_.size()), max_output);
    if (output != nullptr && count > 0) {
        std::memcpy(output, latest_detections_.data(), count * sizeof(Yolo26Object));
    }

    if (metrics != nullptr) {
        *metrics = latest_metrics_;
    }
    if (frame_id != nullptr) {
        *frame_id = frame_counter_;
    }

    return count;
}

void Yolo26FrameWorker::get_stats(
    int32_t* received,
    int32_t* processed,
    int32_t* dropped
) {
    if (received != nullptr) *received = received_frames_.load();
    if (processed != nullptr) *processed = processed_frames_.load();
    if (dropped != nullptr) *dropped = dropped_frames_.load();
}

void Yolo26FrameWorker::reset_stats() {
    received_frames_ = 0;
    processed_frames_ = 0;
    dropped_frames_ = 0;
}

void Yolo26FrameWorker::worker_loop() {
    std::vector<uint8_t> local_frame;
    int local_w = 0;
    int local_h = 0;
    int local_rot = 0;
    bool local_nv12 = false;
    float local_prob = 0.40f;
    float local_nms = 0.50f;

    while (running_) {
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            cv_.wait(lock, [this] {
                return !running_ || has_pending_frame_;
            });

            if (!running_) {
                break;
            }

            // Extract the latest frame from the bounded queue
            const size_t size = static_cast<size_t>(pending_width_ * pending_height_ * 3 / 2);
            if (local_frame.size() < size) {
                local_frame.resize(size);
            }
            std::memcpy(local_frame.data(), pending_bytes_.data(), size);

            local_w = pending_width_;
            local_h = pending_height_;
            local_rot = pending_rotation_;
            local_nv12 = pending_is_nv12_;
            local_prob = pending_prob_thresh_;
            local_nms = pending_nms_thresh_;

            has_pending_frame_ = false;
        }

        // Run inference without holding the queue lock!
        std::vector<Yolo26Object> detected_objects;
        Yolo26ProfilingMetrics metrics{};

        const int ret = engine_.detect_yuv420sp(
            local_frame.data(),
            local_w,
            local_h,
            local_rot,
            local_nv12,
            detected_objects,
            local_prob,
            local_nms,
            &metrics
        );

        if (ret == 0) {
            std::unique_lock<std::mutex> lock(results_mutex_);
            latest_detections_ = std::move(detected_objects);
            latest_metrics_ = metrics;
            frame_counter_++;
            processed_frames_++;
        }
    }
}
