cmake_minimum_required(VERSION 3.18.1)

project("native_ai_engine" LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(
    native_ai_engine
    SHARED
    native_ai_bridge.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    native_ai_engine
    ${log-lib}
)
