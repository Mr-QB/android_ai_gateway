#include "euroc_dataset.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

namespace orbslam_bridge {

namespace {

inline bool file_exists(const std::string& path) {
    struct stat buffer;
    return (stat(path.c_str(), &buffer) == 0);
}

inline std::string trim(const std::string& str) {
    size_t first = str.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\r\n");
    return str.substr(first, (last - first + 1));
}

} // namespace

void EurocDataset::clear() {
    camera_frames_.clear();
    imu_samples_.clear();
}

bool EurocDataset::load(const std::string& sequence_root, std::string* error) {
    clear();

    if (sequence_root.empty()) {
        if (error) *error = "Sequence root path is empty.";
        return false;
    }

    // Resolve cam0 path (support both root/mav0/cam0 and root/cam0)
    std::string cam0_csv = sequence_root + "/mav0/cam0/data.csv";
    std::string cam0_data = sequence_root + "/mav0/cam0/data";
    if (!file_exists(cam0_csv)) {
        cam0_csv = sequence_root + "/cam0/data.csv";
        cam0_data = sequence_root + "/cam0/data";
    }

    if (!file_exists(cam0_csv)) {
        if (error) {
            *error = "EuRoC cam0/data.csv not found in: " + sequence_root +
                     " (checked /mav0/cam0/data.csv and /cam0/data.csv)";
        }
        return false;
    }

    if (!parse_camera_csv(cam0_csv, cam0_data, error)) {
        return false;
    }

    // Resolve imu0 path (support both root/mav0/imu0 and root/imu0)
    std::string imu0_csv = sequence_root + "/mav0/imu0/data.csv";
    if (!file_exists(imu0_csv)) {
        imu0_csv = sequence_root + "/imu0/data.csv";
    }

    if (file_exists(imu0_csv)) {
        if (!parse_imu_csv(imu0_csv, error)) {
            // If IMU is present but invalid, return error
            return false;
        }
    }

    return true;
}

bool EurocDataset::parse_camera_csv(const std::string& csv_path, const std::string& data_dir, std::string* error) {
    std::ifstream file(csv_path);
    if (!file.is_open()) {
        if (error) *error = "Failed to open camera CSV file: " + csv_path;
        return false;
    }

    std::string line;
    while (std::getline(file, line)) {
        std::string trimmed = trim(line);
        if (trimmed.empty() || trimmed[0] == '#') {
            continue;
        }

        std::stringstream ss(trimmed);
        std::string ts_str, filename;

        if (!std::getline(ss, ts_str, ',') || !std::getline(ss, filename)) {
            continue;
        }

        ts_str = trim(ts_str);
        filename = trim(filename);

        if (ts_str.empty() || filename.empty()) {
            continue;
        }

        try {
            int64_t ts_ns = std::stoll(ts_str);
            double ts_s = static_cast<double>(ts_ns) * 1e-9;
            std::string img_path = data_dir + "/" + filename;

            EurocCameraFrame frame;
            frame.timestamp_ns = ts_ns;
            frame.timestamp_s = ts_s;
            frame.image_path = img_path;

            camera_frames_.push_back(std::move(frame));
        } catch (const std::exception& e) {
            // Skip invalid timestamp line
            continue;
        }
    }

    if (camera_frames_.empty()) {
        if (error) *error = "Camera CSV contained no valid frames: " + csv_path;
        return false;
    }

    // Ensure camera frames are strictly ordered by timestamp
    bool is_sorted = std::is_sorted(camera_frames_.begin(), camera_frames_.end(),
        [](const EurocCameraFrame& a, const EurocCameraFrame& b) {
            return a.timestamp_ns < b.timestamp_ns;
        });

    if (!is_sorted) {
        std::sort(camera_frames_.begin(), camera_frames_.end(),
            [](const EurocCameraFrame& a, const EurocCameraFrame& b) {
                return a.timestamp_ns < b.timestamp_ns;
            });
    }

    return true;
}

bool EurocDataset::parse_imu_csv(const std::string& csv_path, std::string* error) {
    std::ifstream file(csv_path);
    if (!file.is_open()) {
        if (error) *error = "Failed to open IMU CSV file: " + csv_path;
        return false;
    }

    std::string line;
    while (std::getline(file, line)) {
        std::string trimmed = trim(line);
        if (trimmed.empty() || trimmed[0] == '#') {
            continue;
        }

        std::stringstream ss(trimmed);
        std::string col;
        std::vector<std::string> cols;

        while (std::getline(ss, col, ',')) {
            cols.push_back(trim(col));
        }

        if (cols.size() < 7) {
            continue;
        }

        try {
            int64_t ts_ns = std::stoll(cols[0]);
            double ts_s = static_cast<double>(ts_ns) * 1e-9;

            // EuRoC format: timestamp, w_x, w_y, w_z (gyro), a_x, a_y, a_z (accel)
            float gx = std::stof(cols[1]);
            float gy = std::stof(cols[2]);
            float gz = std::stof(cols[3]);

            float ax = std::stof(cols[4]);
            float ay = std::stof(cols[5]);
            float az = std::stof(cols[6]);

            if (!std::isfinite(gx) || !std::isfinite(gy) || !std::isfinite(gz) ||
                !std::isfinite(ax) || !std::isfinite(ay) || !std::isfinite(az)) {
                continue;
            }

            EurocImuSample sample;
            sample.timestamp_ns = ts_ns;
            sample.timestamp_s = ts_s;
            sample.gx = gx;
            sample.gy = gy;
            sample.gz = gz;
            sample.ax = ax;
            sample.ay = ay;
            sample.az = az;

            imu_samples_.push_back(sample);
        } catch (const std::exception& e) {
            continue;
        }
    }

    // Sort IMU by timestamp if needed
    bool is_sorted = std::is_sorted(imu_samples_.begin(), imu_samples_.end(),
        [](const EurocImuSample& a, const EurocImuSample& b) {
            return a.timestamp_ns < b.timestamp_ns;
        });

    if (!is_sorted) {
        std::sort(imu_samples_.begin(), imu_samples_.end(),
            [](const EurocImuSample& a, const EurocImuSample& b) {
                return a.timestamp_ns < b.timestamp_ns;
            });
    }

    return true;
}

} // namespace orbslam_bridge
