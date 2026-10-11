#pragma once

#include "slam_types.h"
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

int32_t slam_api_version();

int32_t slam_initialize(
    const char* vocabulary_path,
    const char* settings_path,
    int32_t sensor_mode);

int32_t slam_load_euroc_dataset(
    const char* sequence_root);

int32_t slam_start_replay(
    int32_t replay_mode,
    double speed_factor);

int32_t slam_pause_replay();
int32_t slam_resume_replay();
int32_t slam_stop_replay();
int32_t slam_reset();

int32_t slam_get_status(
    SlamStatusC* out_status);

int32_t slam_get_pose(
    SlamPoseC* out_pose);

int32_t slam_copy_trajectory(
    SlamPoseC* out_poses,
    int32_t max_count);

const char* slam_get_last_error();

void slam_shutdown();

#ifdef __cplusplus
}
#endif
