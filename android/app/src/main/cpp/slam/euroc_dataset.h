#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace orbslam_bridge {

struct EurocCameraFrame {
    int64_t timestamp_ns;
    double timestamp_s;
    std::string image_path;
};

struct EurocImuSample {
    int64_t timestamp_ns;
    double timestamp_s;

    // Gyroscope (rad/s)
    float gx;
    float gy;
    float gz;

    // Accelerometer (m/s^2)
    float ax;
    float ay;
    float az;
};

class EurocDataset {
public:
    EurocDataset() = default;
    ~EurocDataset() = default;

    bool load(const std::string& sequence_root, std::string* error);

    const std::vector<EurocCameraFrame>& camera_frames() const { return camera_frames_; }
    const std::vector<EurocImuSample>& imu_samples() const { return imu_samples_; }

    size_t camera_frame_count() const { return camera_frames_.size(); }
    size_t imu_sample_count() const { return imu_samples_.size(); }

    void clear();

private:
    bool parse_camera_csv(const std::string& csv_path, const std::string& data_dir, std::string* error);
    bool parse_imu_csv(const std::string& csv_path, std::string* error);

    std::vector<EurocCameraFrame> camera_frames_;
    std::vector<EurocImuSample> imu_samples_;
};

} // namespace orbslam_bridge
