cmake_minimum_required(VERSION 3.18.1)

project("native_ai_engine" LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure NCNN SDK Path for Android ABI
set(NCNN_VERSION "20260526")
set(NCNN_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ncnn")
set(NCNN_DIR_PATH "${NCNN_ROOT_DIR}/ncnn-${NCNN_VERSION}-android-vulkan")
set(NCNN_ZIP_PATH "${CMAKE_CURRENT_SOURCE_DIR}/ncnn-${NCNN_VERSION}-android-vulkan.zip")
set(NCNN_URL "https://github.com/Tencent/ncnn/releases/download/${NCNN_VERSION}/ncnn-${NCNN_VERSION}-android-vulkan.zip")

if(NOT EXISTS "${NCNN_DIR_PATH}")
    message(STATUS "[NCNN] SDK not found at ${NCNN_DIR_PATH}. Downloading from ${NCNN_URL}...")
    file(DOWNLOAD "${NCNN_URL}" "${NCNN_ZIP_PATH}"
        SHOW_PROGRESS
        STATUS DOWNLOAD_STATUS
        TLS_VERIFY ON
    )
    list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
    list(GET DOWNLOAD_STATUS 1 ERROR_MESSAGE)
    if(NOT STATUS_CODE EQUAL 0)
        message(FATAL_ERROR "[NCNN] Failed to download NCNN SDK: ${ERROR_MESSAGE}")
    endif()

    message(STATUS "[NCNN] Extracting NCNN SDK to ${NCNN_ROOT_DIR}...")
    file(ARCHIVE_EXTRACT INPUT "${NCNN_ZIP_PATH}" DESTINATION "${NCNN_ROOT_DIR}")
    file(REMOVE "${NCNN_ZIP_PATH}")
endif()

set(ncnn_DIR ${NCNN_DIR_PATH}/${ANDROID_ABI}/lib/cmake/ncnn)
find_package(ncnn REQUIRED)

add_library(
    native_ai_engine
    SHARED
    native_ai_bridge.cpp
    yolo26_engine.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    native_ai_engine
    ncnn
    ${log-lib}
)

# -------------------------------------------------------------
# ORB-SLAM3 Native Module (liborbslam_native.so)
# -------------------------------------------------------------

set(ORB_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/orbslam3")
set(OPENCV_SDK_DIR "${ORB_ROOT}/OpenCV-android-sdk")
set(OpenCV_DIR "${OPENCV_SDK_DIR}/sdk/native/jni/abi-${ANDROID_ABI}")

find_package(OpenCV REQUIRED)

set(EIGEN3_INCLUDE_DIR "${ORB_ROOT}/Thirdparty/eigen-3.4.0")

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/slam
    ${ORB_ROOT}
    ${ORB_ROOT}/include
    ${ORB_ROOT}/include/CameraModels
    ${ORB_ROOT}/Thirdparty/Sophus
    ${EIGEN3_INCLUDE_DIR}
    ${ORB_ROOT}/Thirdparty/DBoW2/include
    ${ORB_ROOT}/Thirdparty/DBoW2/include/DBoW2
)

# Disable G2O extras for fast headless compile
set(G2O_BUILD_APPS OFF CACHE BOOL "" FORCE)
set(G2O_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(G2O_USE_OPENGL OFF CACHE BOOL "" FORCE)
set(G2O_USE_CSPARSE OFF CACHE BOOL "" FORCE)
set(G2O_USE_CHOLMOD OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${ORB_ROOT}/Thirdparty/g2o" g2o_build)

include_directories(
    ${g2o_BINARY_DIR}
    ${ORB_ROOT}/Thirdparty/g2o
)

file(GLOB DBOW2_SOURCES "${ORB_ROOT}/Thirdparty/DBoW2/src/*.cpp")

add_library(
    orbslam_native
    SHARED
    slam/slam_bridge.cpp
    slam/slam_engine.cpp
    slam/euroc_dataset.cpp
    ${ORB_ROOT}/src/System.cc
    ${ORB_ROOT}/src/Tracking.cc
    ${ORB_ROOT}/src/LocalMapping.cc
    ${ORB_ROOT}/src/LoopClosing.cc
    ${ORB_ROOT}/src/ORBextractor.cc
    ${ORB_ROOT}/src/ORBmatcher.cc
    ${ORB_ROOT}/src/Converter.cc
    ${ORB_ROOT}/src/MapPoint.cc
    ${ORB_ROOT}/src/KeyFrame.cc
    ${ORB_ROOT}/src/Atlas.cc
    ${ORB_ROOT}/src/Map.cc
    ${ORB_ROOT}/src/Optimizer.cc
    ${ORB_ROOT}/src/Frame.cc
    ${ORB_ROOT}/src/KeyFrameDatabase.cc
    ${ORB_ROOT}/src/Sim3Solver.cc
    ${ORB_ROOT}/src/ImuTypes.cc
    ${ORB_ROOT}/src/G2oTypes.cc
    ${ORB_ROOT}/src/CameraModels/Pinhole.cpp
    ${ORB_ROOT}/src/CameraModels/KannalaBrandt8.cpp
    ${ORB_ROOT}/src/OptimizableTypes.cpp
    ${ORB_ROOT}/src/MLPnPsolver.cpp
    ${ORB_ROOT}/src/GeometricTools.cc
    ${ORB_ROOT}/src/TwoViewReconstruction.cc
    ${ORB_ROOT}/src/Config.cc
    ${ORB_ROOT}/src/Settings.cc
    ${DBOW2_SOURCES}
)

target_link_libraries(
    orbslam_native
    ${OpenCV_LIBS}
    g2o::types_sba
    g2o::types_sim3
    g2o::core
    g2o::stuff
    ${log-lib}
    android
)
