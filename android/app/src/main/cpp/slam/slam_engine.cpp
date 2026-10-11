#include "slam_engine.h"

#include <android/log.h>
#include <chrono>
#include <cmath>
#include <fstream>
#include <opencv2/imgcodecs.hpp>
#include <sys/stat.h>

#include "System.h"
#include "ImuTypes.h"

#define SLAM_TAG "ORB_SLAM_NATIVE"
#define SLAM_LOGI(...) __android_log_print(ANDROID_LOG_INFO, SLAM_TAG, __VA_ARGS__)
#define SLAM_LOGW(...) __android_log_print(ANDROID_LOG_WARN, SLAM_TAG, __VA_ARGS__)
#define SLAM_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, SLAM_TAG, __VA_ARGS__)

namespace orbslam_bridge {

namespace {

inline bool check_file_exists(const std::string& path) {
    struct stat buffer;
    return (stat(path.c_str(), &buffer) == 0);
}

} // namespace

SlamEngine& SlamEngine::instance() {
    static SlamEngine s_instance;
    return s_instance;
}

SlamEngine::SlamEngine() {
    status_.api_version = 1;
    status_.run_state = static_cast<int32_t>(SlamRunState::UNINITIALIZED);
    status_.tracking_state = static_cast<int32_t>(SlamTrackingState::SYSTEM_NOT_READY);
    status_.sensor_mode = static_cast<int32_t>(SlamSensorMode::MONOCULAR);
}

SlamEngine::~SlamEngine() {
    shutdown();
}

void SlamEngine::set_error_locked(int code, const std::string& message) {
    last_error_ = message;
    status_.error_code = code;
    status_.run_state = static_cast<int32_t>(SlamRunState::ERROR);
    SLAM_LOGE("[SlamEngine] Error %d: %s", code, message.c_str());
}

int SlamEngine::initialize(
    const std::string& vocabulary_path,
    const std::string& settings_path,
    SlamSensorMode sensor_mode)
{
    stop_replay();

    std::lock_guard<std::mutex> lock(mutex_);

    if (vocabulary_path.empty() || !check_file_exists(vocabulary_path)) {
        set_error_locked(-3, "ORB vocabulary file not found: " + vocabulary_path);
        return -3;
    }

    if (settings_path.empty() || !check_file_exists(settings_path)) {
        set_error_locked(-3, "Settings YAML file not found: " + settings_path);
        return -3;
    }

    vocabulary_path_ = vocabulary_path;
    settings_path_ = settings_path;
    sensor_mode_ = sensor_mode;

    // Safely shutdown and recreate system
    if (slam_) {
        try {
            slam_->Shutdown();
        } catch (...) {}
        slam_.reset();
    }

    ORB_SLAM3::System::eSensor orb_sensor =
        (sensor_mode == SlamSensorMode::MONO_INERTIAL)
            ? ORB_SLAM3::System::IMU_MONOCULAR
            : ORB_SLAM3::System::MONOCULAR;

    SLAM_LOGI("[SlamEngine] Initializing ORB-SLAM3 (sensor=%d, vocab=%s, settings=%s)...",
              static_cast<int>(sensor_mode), vocabulary_path.c_str(), settings_path.c_str());

    try {
        // useViewer = false for headless Android operation
        slam_ = std::make_unique<ORB_SLAM3::System>(
            vocabulary_path,
            settings_path,
            orb_sensor,
            false);
    } catch (const std::exception& e) {
        set_error_locked(-5, "Failed to construct ORB_SLAM3::System: " + std::string(e.what()));
        return -5;
    } catch (...) {
        set_error_locked(-5, "Unknown native exception while constructing ORB_SLAM3::System");
        return -5;
    }

    status_.run_state = static_cast<int32_t>(SlamRunState::READY);
    status_.tracking_state = static_cast<int32_t>(SlamTrackingState::NOT_INITIALIZED);
    status_.sensor_mode = static_cast<int32_t>(sensor_mode);
    status_.error_code = 0;
    status_.current_frame = 0;
    status_.keyframe_count = 0;
    status_.map_point_count = 0;
    status_.last_track_ms = 0.0;
    status_.average_track_ms = 0.0;
    status_.replay_elapsed_s = 0.0;
    status_.finished = 0;

    trajectory_.clear();
    last_pose_ = SlamPoseC{};

    SLAM_LOGI("[SlamEngine] ORB-SLAM3 initialized successfully.");
    return 0;
}

int SlamEngine::load_euroc_dataset(const std::string& sequence_root) {
    stop_replay();

    std::lock_guard<std::mutex> lock(mutex_);

    std::string err;
    if (!dataset_.load(sequence_root, &err)) {
        set_error_locked(-4, "Dataset load failed: " + err);
        return -4;
    }

    if (sensor_mode_ == SlamSensorMode::MONO_INERTIAL && dataset_.imu_sample_count() == 0) {
        set_error_locked(-4, "Mono-inertial mode requested but imu0/data.csv contains 0 samples.");
        return -4;
    }

    status_.total_frames = static_cast<int32_t>(dataset_.camera_frame_count());
    status_.current_frame = 0;
    status_.run_state = static_cast<int32_t>(SlamRunState::DATASET_LOADED);
    status_.finished = 0;
    status_.error_code = 0;

    SLAM_LOGI("[SlamEngine] Dataset loaded: %zu camera frames, %zu IMU samples.",
              dataset_.camera_frame_count(), dataset_.imu_sample_count());
    return 0;
}

int SlamEngine::start_replay(SlamReplayMode replay_mode, double speed_factor) {
    if (running_.load()) {
        return -6; // Already running
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!slam_) {
            set_error_locked(-2, "ORB-SLAM3 not initialized.");
            return -2;
        }
        if (dataset_.camera_frame_count() == 0) {
            set_error_locked(-2, "No dataset loaded.");
            return -2;
        }

        replay_mode_ = replay_mode;
        speed_factor_ = speed_factor > 0.0 ? speed_factor : 1.0;

        stop_requested_ = false;
        pause_requested_ = false;
        running_ = true;

        status_.run_state = static_cast<int32_t>(SlamRunState::RUNNING);
        status_.finished = 0;
    }

    replay_thread_ = std::thread(&SlamEngine::replay_loop, this);
    return 0;
}

void SlamEngine::wait_if_paused() {
    std::unique_lock<std::mutex> lock(pause_mutex_);
    pause_cv_.wait(lock, [this]() {
        return !pause_requested_.load() || stop_requested_.load();
    });
}

int SlamEngine::pause_replay() {
    if (!running_.load()) return -2;

    pause_requested_ = true;
    std::lock_guard<std::mutex> lock(mutex_);
    status_.run_state = static_cast<int32_t>(SlamRunState::PAUSED);
    SLAM_LOGI("[SlamEngine] Replay paused.");
    return 0;
}

int SlamEngine::resume_replay() {
    if (!running_.load()) return -2;

    pause_requested_ = false;
    pause_cv_.notify_all();

    std::lock_guard<std::mutex> lock(mutex_);
    status_.run_state = static_cast<int32_t>(SlamRunState::RUNNING);
    SLAM_LOGI("[SlamEngine] Replay resumed.");
    return 0;
}

int SlamEngine::stop_replay() {
    stop_requested_ = true;
    pause_requested_ = false;
    pause_cv_.notify_all();

    if (replay_thread_.joinable()) {
        replay_thread_.join();
    }

    running_ = false;

    std::lock_guard<std::mutex> lock(mutex_);
    if (status_.run_state == static_cast<int32_t>(SlamRunState::RUNNING) ||
        status_.run_state == static_cast<int32_t>(SlamRunState::PAUSED)) {
        status_.run_state = static_cast<int32_t>(SlamRunState::READY);
    }
    return 0;
}

int SlamEngine::reset() {
    stop_replay();

    std::string vocab = vocabulary_path_;
    std::string settings = settings_path_;
    SlamSensorMode sensor = sensor_mode_;

    if (!vocab.empty() && !settings.empty()) {
        return initialize(vocab, settings, sensor);
    }
    return 0;
}

void SlamEngine::shutdown() {
    stop_replay();

    std::lock_guard<std::mutex> lock(mutex_);
    if (slam_) {
        SLAM_LOGI("[SlamEngine] Shutting down ORB-SLAM3...");
        try {
            slam_->Shutdown();
        } catch (...) {}
        slam_.reset();
    }

    dataset_.clear();
    trajectory_.clear();
    status_.run_state = static_cast<int32_t>(SlamRunState::UNINITIALIZED);
    status_.tracking_state = static_cast<int32_t>(SlamTrackingState::SYSTEM_NOT_READY);
    SLAM_LOGI("[SlamEngine] Shutdown complete.");
}

void SlamEngine::replay_loop() {
    SLAM_LOGI("[SlamEngine] Replay loop started.");

    const auto& camera_frames = dataset_.camera_frames();
    if (camera_frames.empty()) {
        running_ = false;
        return;
    }

    const double dataset_start_ts = camera_frames.front().timestamp_s;
    auto wall_start = std::chrono::steady_clock::now();
    std::chrono::nanoseconds accumulated_pause(0);

    size_t imu_idx = 0;
    double total_track_time_ms = 0.0;
    int processed_count = 0;

    for (size_t i = 0; i < camera_frames.size(); ++i) {
        if (stop_requested_.load()) {
            break;
        }

        // Handle pause
        if (pause_requested_.load()) {
            auto pause_begin = std::chrono::steady_clock::now();
            wait_if_paused();
            auto pause_end = std::chrono::steady_clock::now();
            accumulated_pause += std::chrono::duration_cast<std::chrono::nanoseconds>(pause_end - pause_begin);
        }

        if (stop_requested_.load()) {
            break;
        }

        const auto& camera = camera_frames[i];

        // Timing regulation for REALTIME replay
        if (replay_mode_ == SlamReplayMode::REALTIME) {
            double elapsed_dataset_s = (camera.timestamp_s - dataset_start_ts) / speed_factor_;
            auto target_wall_time = wall_start + accumulated_pause +
                                    std::chrono::duration_cast<std::chrono::nanoseconds>(
                                        std::chrono::duration<double>(elapsed_dataset_s));

            std::this_thread::sleep_until(target_wall_time);
        }

        if (!process_frame(camera.image_path, camera.timestamp_s, imu_idx)) {
            break; // Stop on fatal error
        }

        processed_count++;
        total_track_time_ms += status_.last_track_ms;

        // Periodic logging (every 100 frames or 1st frame)
        if (i == 0 || i % 100 == 0 || i == camera_frames.size() - 1) {
            SLAM_LOGI("[SlamEngine] Frame %zu/%zu: track=%.2f ms, state=%d, keyframes=%d, mapPoints=%d",
                      i + 1, camera_frames.size(), status_.last_track_ms,
                      status_.tracking_state, status_.keyframe_count, status_.map_point_count);
        }
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        running_ = false;
        if (!stop_requested_.load() && status_.run_state != static_cast<int32_t>(SlamRunState::ERROR)) {
            status_.run_state = static_cast<int32_t>(SlamRunState::FINISHED);
            status_.finished = 1;
        }
    }

    SLAM_LOGI("[SlamEngine] Replay loop ended (processed %d frames).", processed_count);
}

bool SlamEngine::process_frame(
    const std::string& image_path,
    double timestamp_s,
    size_t& imu_idx)
{
    cv::Mat im = cv::imread(image_path, cv::IMREAD_GRAYSCALE);
    if (im.empty()) {
        std::lock_guard<std::mutex> lock(mutex_);
        set_error_locked(-7, "Failed to decode frame image: " + image_path);
        return false;
    }

    // Collect IMU samples up to current camera timestamp
    std::vector<ORB_SLAM3::IMU::Point> imu_batch;
    if (sensor_mode_ == SlamSensorMode::MONO_INERTIAL) {
        const auto& imu = dataset_.imu_samples();
        static double last_camera_ts = -1.0;

        while (imu_idx < imu.size() && imu[imu_idx].timestamp_s <= timestamp_s) {
            const auto& s = imu[imu_idx];
            if (last_camera_ts < 0.0 || s.timestamp_s > last_camera_ts) {
                // ORB_SLAM3 Point constructor: ax, ay, az, wx, wy, wz, timestamp
                imu_batch.emplace_back(s.ax, s.ay, s.az, s.gx, s.gy, s.gz, s.timestamp_s);
            }
            ++imu_idx;
        }
        last_camera_ts = timestamp_s;
    }

    auto t_start = std::chrono::steady_clock::now();

    Sophus::SE3f Tcw;
    try {
        if (sensor_mode_ == SlamSensorMode::MONO_INERTIAL) {
            Tcw = slam_->TrackMonocular(im, timestamp_s, imu_batch);
        } else {
            Tcw = slam_->TrackMonocular(im, timestamp_s);
        }
    } catch (const std::exception& e) {
        std::lock_guard<std::mutex> lock(mutex_);
        set_error_locked(-7, "Exception inside TrackMonocular: " + std::string(e.what()));
        return false;
    } catch (...) {
        std::lock_guard<std::mutex> lock(mutex_);
        set_error_locked(-7, "Unknown native exception inside TrackMonocular.");
        return false;
    }

    auto t_end = std::chrono::steady_clock::now();
    double track_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    int tracking_state = slam_->GetTrackingState();

    // Convert Tcw (World to Camera) to Twc (Camera in World coordinates)
    Sophus::SE3f Twc = Tcw.inverse();
    Eigen::Vector3f t = Twc.translation();
    Eigen::Quaternionf q = Twc.unit_quaternion();

    bool is_finite = std::isfinite(t.x()) && std::isfinite(t.y()) && std::isfinite(t.z()) &&
                     std::isfinite(q.x()) && std::isfinite(q.y()) && std::isfinite(q.z()) && std::isfinite(q.w());

    bool is_pose_valid = is_finite && (tracking_state == 2 || tracking_state == 3); // OK or initialized

    SlamPoseC current_pose{};
    current_pose.timestamp_s = timestamp_s;
    current_pose.tx = t.x();
    current_pose.ty = t.y();
    current_pose.tz = t.z();
    current_pose.qx = q.x();
    current_pose.qy = q.y();
    current_pose.qz = q.z();
    current_pose.qw = q.w();
    current_pose.valid = is_pose_valid ? 1 : 0;

    // Update status and trajectory under short mutex lock
    {
        std::lock_guard<std::mutex> lock(mutex_);
        last_pose_ = current_pose;

        if (is_pose_valid) {
            trajectory_.push_back(current_pose);
        }

        status_.current_frame++;
        status_.tracking_state = tracking_state;
        status_.dataset_timestamp_s = timestamp_s;
        status_.last_track_ms = track_ms;

        // Cumulative running average
        if (status_.current_frame > 0) {
            status_.average_track_ms =
                (status_.average_track_ms * (status_.current_frame - 1) + track_ms) / status_.current_frame;
        }

        // Tracked map points from current frame; Atlas keyframe collection is omitted per Section 49
        status_.map_point_count = static_cast<int32_t>(slam_->GetTrackedMapPoints().size());
        status_.keyframe_count = -1;
    }

    return true;
}

SlamStatusC SlamEngine::status() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return status_;
}

SlamPoseC SlamEngine::pose() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return last_pose_;
}

int SlamEngine::copy_trajectory(SlamPoseC* out, int max_count) const {
    if (!out || max_count <= 0) return 0;

    std::lock_guard<std::mutex> lock(mutex_);
    int total = static_cast<int>(trajectory_.size());
    if (total == 0) return 0;

    if (total <= max_count) {
        for (int i = 0; i < total; ++i) {
            out[i] = trajectory_[i];
        }
        return total;
    }

    // Uniformly sample poses across trajectory
    double step = static_cast<double>(total - 1) / (max_count - 1);
    for (int i = 0; i < max_count; ++i) {
        int idx = static_cast<int>(std::round(i * step));
        if (idx >= total) idx = total - 1;
        out[i] = trajectory_[idx];
    }
    return max_count;
}

std::string SlamEngine::last_error() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return last_error_;
}

} // namespace orbslam_bridge
