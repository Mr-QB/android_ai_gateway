#pragma once

#include <cstdint>

enum class SlamSensorMode : int32_t {
    MONOCULAR = 0,
    MONO_INERTIAL = 1,
};

enum class SlamReplayMode : int32_t {
    REALTIME = 0,
    MAXIMUM_SPEED = 1,
};

enum class SlamRunState : int32_t {
    UNINITIALIZED = 0,
    READY = 1,
    DATASET_LOADED = 2,
    RUNNING = 3,
    PAUSED = 4,
    FINISHED = 5,
    ERROR = 6,
};

enum class SlamTrackingState : int32_t {
    SYSTEM_NOT_READY = 0,
    NO_IMAGES_YET = 1,
    NOT_INITIALIZED = 2,
    OK = 3,
    RECENTLY_LOST = 4,
    LOST = 5,
};

struct SlamPoseC {
    double timestamp_s;

    float tx;
    float ty;
    float tz;

    float qx;
    float qy;
    float qz;
    float qw;

    int32_t valid;
};

struct SlamStatusC {
    int32_t api_version;

    int32_t run_state;
    int32_t tracking_state;
    int32_t sensor_mode;

    int32_t current_frame;
    int32_t total_frames;

    int32_t keyframe_count;
    int32_t map_point_count;

    double dataset_timestamp_s;

    double last_track_ms;
    double average_track_ms;
    double replay_elapsed_s;

    int32_t finished;
    int32_t error_code;
};
