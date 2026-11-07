cmake_minimum_required(VERSION 3.22.1)
project(simwheel_moonlight LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(MOONLIGHT_ROOT "${CMAKE_CURRENT_LIST_DIR}/../jni/moonlight-core")
set(MOONLIGHT_COMMON "${MOONLIGHT_ROOT}/moonlight-common-c")
set(MBEDTLS_ROOT "${MOONLIGHT_ROOT}/mbedtls")

set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
add_subdirectory("${MBEDTLS_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/mbedtls")

add_library(moonlight-opus STATIC IMPORTED)
set_target_properties(moonlight-opus PROPERTIES
    IMPORTED_LOCATION "${MOONLIGHT_ROOT}/opus/${ANDROID_ABI}/libopus.a")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build Moonlight core as a static library" FORCE)
set(USE_MBEDTLS ON CACHE BOOL "Use the bundled Mbed TLS crypto backend" FORCE)
add_subdirectory("${MOONLIGHT_COMMON}" "${CMAKE_CURRENT_BINARY_DIR}/moonlight-common-c")
target_include_directories(moonlight-common-c SYSTEM PRIVATE "${MBEDTLS_ROOT}/include")

add_library(moonlight-core SHARED
    "${MOONLIGHT_ROOT}/simplejni.c"
    "${MOONLIGHT_ROOT}/callbacks.c"
    "${MOONLIGHT_ROOT}/minisdl.c"
    "${ANDROID_NDK}/sources/android/cpufeatures/cpu-features.c")

target_include_directories(moonlight-core PRIVATE
    "${MOONLIGHT_ROOT}"
    "${MOONLIGHT_ROOT}/opus/include"
    "${MBEDTLS_ROOT}/include"
    "${MOONLIGHT_COMMON}/src"
    "${MOONLIGHT_COMMON}/enet/include"
    "${MOONLIGHT_COMMON}/nanors"
    "${MOONLIGHT_COMMON}/nanors/deps/obl"
    "${ANDROID_NDK}/sources/android/cpufeatures")

target_compile_definitions(moonlight-core PRIVATE
    LC_ANDROID
    HAS_SOCKLEN_T=1
    HAVE_CLOCK_GETTIME=1)

target_link_libraries(moonlight-core PRIVATE
    moonlight-common-c
    moonlight-opus
    mbedcrypto
    log
    android
    dl)
