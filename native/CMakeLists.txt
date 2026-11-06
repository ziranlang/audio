# Standalone build of the static codec archives, used by tests/android.sh.
cmake_minimum_required(VERSION 3.22)
project(ziran_audio_native C)
include("${CMAKE_CURRENT_LIST_DIR}/AudioCodecs.cmake")
ziran_audio_codecs("${OPUS_DIR}" "${SAMPLERATE_DIR}")
add_custom_target(codecs ALL DEPENDS opus samplerate)
