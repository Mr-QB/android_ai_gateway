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

