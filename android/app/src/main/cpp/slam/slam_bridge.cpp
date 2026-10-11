#include "slam_bridge.h"
#include "slam_engine.h"

#include <cstring>
#include <string>

using namespace orbslam_bridge;

namespace {
thread_local std::string g_last_error_cache;
}

extern "C" {

int32_t slam_api_version() {
    return 1;
}

int32_t slam_initialize(
    const char* vocabulary_path,
    const char* settings_path,
    int32_t sensor_mode)
{
    if (!vocabulary_path || !settings_path) {
        return -1;
    }

    try {
        std::string vocab(vocabulary_path);
        std::string settings(settings_path);
        auto sensor = static_cast<SlamSensorMode>(sensor_mode);

        return SlamEngine::instance().initialize(vocab, settings, sensor);
    } catch (...) {
        return -7;
    }
}

int32_t slam_load_euroc_dataset(const char* sequence_root) {
    if (!sequence_root) {
        return -1;
    }

    try {
        std::string root(sequence_root);
        return SlamEngine::instance().load_euroc_dataset(root);
    } catch (...) {
        return -7;
    }
}

int32_t slam_start_replay(int32_t replay_mode, double speed_factor) {
    try {
        auto mode = static_cast<SlamReplayMode>(replay_mode);
        return SlamEngine::instance().start_replay(mode, speed_factor);
    } catch (...) {
        return -7;
    }
}

int32_t slam_pause_replay() {
    try {
        return SlamEngine::instance().pause_replay();
    } catch (...) {
        return -7;
    }
}

int32_t slam_resume_replay() {
    try {
        return SlamEngine::instance().resume_replay();
    } catch (...) {
        return -7;
    }
}

int32_t slam_stop_replay() {
    try {
        return SlamEngine::instance().stop_replay();
    } catch (...) {
        return -7;
    }
}

int32_t slam_reset() {
    try {
        return SlamEngine::instance().reset();
    } catch (...) {
        return -7;
    }
}

int32_t slam_get_status(SlamStatusC* out_status) {
    if (!out_status) return -1;
    try {
        *out_status = SlamEngine::instance().status();
        return 0;
    } catch (...) {
        return -7;
    }
}

int32_t slam_get_pose(SlamPoseC* out_pose) {
    if (!out_pose) return -1;
    try {
        *out_pose = SlamEngine::instance().pose();
        return 0;
    } catch (...) {
        return -7;
    }
}

int32_t slam_copy_trajectory(SlamPoseC* out_poses, int32_t max_count) {
    if (!out_poses || max_count <= 0) return 0;
    try {
        return SlamEngine::instance().copy_trajectory(out_poses, max_count);
    } catch (...) {
        return 0;
    }
}

const char* slam_get_last_error() {
    try {
        g_last_error_cache = SlamEngine::instance().last_error();
        return g_last_error_cache.c_str();
    } catch (...) {
        return "Unknown error";
    }
}

void slam_shutdown() {
    try {
        SlamEngine::instance().shutdown();
    } catch (...) {}
}

} // extern "C"
