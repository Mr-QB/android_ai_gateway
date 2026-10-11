#pragma once

#include "slam_types.h"
#include "euroc_dataset.h"

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ORB_SLAM3 {
class System;
}

namespace orbslam_bridge {

class SlamEngine {
public:
    static SlamEngine& instance();

    int initialize(
        const std::string& vocabulary_path,
        const std::string& settings_path,
        SlamSensorMode sensor_mode);

    int load_euroc_dataset(const std::string& sequence_root);

    int start_replay(SlamReplayMode replay_mode, double speed_factor);
    int pause_replay();
    int resume_replay();
    int stop_replay();
    int reset();
    void shutdown();

    SlamStatusC status() const;
    SlamPoseC pose() const;

    int copy_trajectory(SlamPoseC* out, int max_count) const;

    std::string last_error() const;

private:
    SlamEngine();
    ~SlamEngine();

    SlamEngine(const SlamEngine&) = delete;
    SlamEngine& operator=(const SlamEngine&) = delete;

    void replay_loop();
    void set_error_locked(int code, const std::string& message);
    void wait_if_paused();

    bool process_frame(
        const std::string& image_path,
        double timestamp_s,
        size_t& imu_idx);

private:
    mutable std::mutex mutex_;

    std::unique_ptr<ORB_SLAM3::System> slam_;
    EurocDataset dataset_;

    std::thread replay_thread_;

    std::atomic<bool> stop_requested_{false};
    std::atomic<bool> pause_requested_{false};
    std::atomic<bool> running_{false};

    std::condition_variable pause_cv_;
    std::mutex pause_mutex_;

    std::string vocabulary_path_;
    std::string settings_path_;

    SlamSensorMode sensor_mode_{SlamSensorMode::MONOCULAR};
    SlamReplayMode replay_mode_{SlamReplayMode::REALTIME};
    double speed_factor_{1.0};

    SlamStatusC status_{};
    SlamPoseC last_pose_{};

    std::vector<SlamPoseC> trajectory_;

    std::string last_error_;
};

} // namespace orbslam_bridge
