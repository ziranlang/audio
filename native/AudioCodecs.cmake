# Static libopus, libsamplerate, MP3 and Vorbis decoder recipe for native
# consumers (Linux, Android NDK, Windows MinGW and other cross builds).
# Sources are this package's pinned `libopus`, `libsamplerate`, `dr_libs` and
# `stb` source dependencies (`ziran pkg path NAME`).
#   include("<audio-package>/native/AudioCodecs.cmake")
#   ziran_audio_codecs("<libopus-source>" "<libsamplerate-source>")
#   ziran_audio_mp3("<dr_libs-source>")
#   ziran_audio_vorbis("<stb-source>")
# Defines static, position-independent targets `opus`, `samplerate`,
# `ziran_mp3` and `ziran_vorbis`. Each function is independent; call only
# what is linked.
include_guard(GLOBAL)

function(ziran_audio_codecs opus_dir samplerate_dir)
    if(TARGET opus OR TARGET samplerate)
        message(FATAL_ERROR "ziran_audio_codecs: opus/samplerate targets already exist")
    endif()
    if(NOT EXISTS "${opus_dir}/CMakeLists.txt" OR NOT EXISTS "${opus_dir}/src/opus_decoder.c")
        message(FATAL_ERROR "No libopus source at ${opus_dir}")
    endif()
    if(NOT EXISTS "${samplerate_dir}/CMakeLists.txt" OR NOT EXISTS "${samplerate_dir}/src/src_sinc.c")
        message(FATAL_ERROR "No libsamplerate source at ${samplerate_dir}")
    endif()
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    set(BUILD_SHARED_LIBS OFF)
    # Float decoder/encoder API; no programs, tests, DNN extensions or install rules.
    foreach(option BUILD_SHARED_LIBRARY BUILD_TESTING BUILD_PROGRAMS CUSTOM_MODES
            FIXED_POINT DRED OSCE INSTALL_PKG_CONFIG_MODULE INSTALL_CMAKE_CONFIG_MODULE)
        set(OPUS_${option} OFF CACHE BOOL "" FORCE)
    endforeach()
    set(OPUS_ENABLE_FLOAT_API ON CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(LIBSAMPLERATE_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LIBSAMPLERATE_INSTALL OFF CACHE BOOL "" FORCE)
    add_subdirectory("${opus_dir}" "${CMAKE_CURRENT_BINARY_DIR}/libopus" EXCLUDE_FROM_ALL)
    add_subdirectory("${samplerate_dir}" "${CMAKE_CURRENT_BINARY_DIR}/libsamplerate" EXCLUDE_FROM_ALL)
    foreach(codec_target opus samplerate)
        target_compile_options("${codec_target}" PRIVATE -ffunction-sections -fdata-sections)
        set_target_properties("${codec_target}" PROPERTIES POSITION_INDEPENDENT_CODE ON)
    endforeach()
endfunction()

# dr_mp3 is a single header; ziran_mp3.c is its one implementation unit plus
# the decoder-state calls audio/mp3 binds. Link `libziran_mp3.a` (and `-lm`).
function(ziran_audio_mp3 dr_libs_dir)
    if(TARGET ziran_mp3)
        message(FATAL_ERROR "ziran_audio_mp3: ziran_mp3 target already exists")
    endif()
    if(NOT EXISTS "${dr_libs_dir}/dr_mp3.h" OR NOT EXISTS "${dr_libs_dir}/LICENSE")
        message(FATAL_ERROR "No dr_libs source at ${dr_libs_dir}")
    endif()
    add_library(ziran_mp3 STATIC "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/ziran_mp3.c")
    target_include_directories(ziran_mp3 PRIVATE "${dr_libs_dir}")
    target_compile_options(ziran_mp3 PRIVATE -ffunction-sections -fdata-sections)
    set_target_properties(ziran_mp3 PROPERTIES POSITION_INDEPENDENT_CODE ON C_STANDARD 99)
endfunction()

# stb_vorbis is a single source file; ziran_vorbis.c is its one
# implementation unit plus the open/read/seek calls audio/vorbis binds. Link
# `libziran_vorbis.a` (and `-lm`).
function(ziran_audio_vorbis stb_dir)
    if(TARGET ziran_vorbis)
        message(FATAL_ERROR "ziran_audio_vorbis: ziran_vorbis target already exists")
    endif()
    if(NOT EXISTS "${stb_dir}/stb_vorbis.c" OR NOT EXISTS "${stb_dir}/LICENSE")
        message(FATAL_ERROR "No stb source at ${stb_dir}")
    endif()
    add_library(ziran_vorbis STATIC "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/ziran_vorbis.c")
    target_include_directories(ziran_vorbis PRIVATE "${stb_dir}")
    target_compile_options(ziran_vorbis PRIVATE -ffunction-sections -fdata-sections)
    set_target_properties(ziran_vorbis PROPERTIES POSITION_INDEPENDENT_CODE ON C_STANDARD 99)
endfunction()
