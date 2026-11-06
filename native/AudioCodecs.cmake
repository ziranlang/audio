# Static libopus and libsamplerate recipe for native consumers (Android NDK and
# other cross builds). Sources are this package's pinned `libopus` and
# `libsamplerate` source dependencies (`ziran pkg path NAME`).
#   include("<audio-package>/native/AudioCodecs.cmake")
#   ziran_audio_codecs("<libopus-source>" "<libsamplerate-source>")
# Defines static, position-independent targets `opus` and `samplerate`.
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
