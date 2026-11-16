# Standalone build of the static codec archives, used by the Makefile and
# tests/android.sh / tests/windows.sh. OPUS_DIR with SAMPLERATE_DIR builds
# `opus` and `samplerate`; DR_LIBS_DIR builds `ziran_mp3`.
cmake_minimum_required(VERSION 3.22)
project(ziran_audio_native C)
include("${CMAKE_CURRENT_LIST_DIR}/AudioCodecs.cmake")
set(codec_targets)
if(DEFINED OPUS_DIR OR DEFINED SAMPLERATE_DIR)
    ziran_audio_codecs("${OPUS_DIR}" "${SAMPLERATE_DIR}")
    list(APPEND codec_targets opus samplerate)
endif()
if(DEFINED DR_LIBS_DIR)
    ziran_audio_mp3("${DR_LIBS_DIR}")
    list(APPEND codec_targets ziran_mp3)
endif()
if(NOT codec_targets)
    message(FATAL_ERROR "Pass OPUS_DIR and SAMPLERATE_DIR, DR_LIBS_DIR, or both")
endif()
add_custom_target(codecs ALL DEPENDS ${codec_targets})
