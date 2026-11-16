#!/bin/sh
# Android NDK build of the pinned libopus/libsamplerate/dr_libs/stb sources
# and the audio CLI for every ABI Breeze ships, then (with ANDROID_SERIAL) a
# device run that decodes, inspects, resamples and encodes the `make test`
# fixtures and the committed MP3 and Vorbis fixtures and checks them against
# the Linux CLI. Invoke through build-queue (`make android-test`).
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
ZIRAN=${ZIRAN:-ziran}
CMAKE=${CMAKE:-cmake}
ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Android/Sdk/ndk/28.2.13676358}}
api=${ANDROID_API:-21}
abis=${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86 x86_64}
toolchain=$ndk/build/cmake/android.toolchain.cmake
test -f "$toolchain" || { echo "Android NDK not found at $ndk (set ANDROID_NDK_HOME)" >&2; exit 1; }
bin=$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin
opus=$("$ZIRAN" pkg path libopus --offline)
samplerate=$("$ZIRAN" pkg path libsamplerate --offline)
dr_libs=$("$ZIRAN" pkg path dr_libs --offline)
stb=$("$ZIRAN" pkg path stb --offline)
fixtures=build/tests/fixtures
mp3s="cbr.mp3 vbr.mp3 mono.mp3 mpeg2.mp3 mpeg25.mp3 noxing.mp3 id3.mp3 layer2.mp2 long.mp3"
# Vorbis copies are prefixed: mono and long also name MP3 fixtures.
oggs="vorbis-stereo.ogg vorbis-mono.ogg vorbis-rate22.ogg vorbis-rate48.ogg vorbis-comments.ogg vorbis-long.ogg"
for name in short.opus voice.opus chirp.opus voice.wav chirp.wav; do
    test -f "$fixtures/$name" || { echo "missing $fixtures/$name; run make test first" >&2; exit 1; }
done
test -x build/bin/audio || { echo "missing build/bin/audio; run make test first" >&2; exit 1; }
unset LDFLAGS DISPLAY WAYLAND_DISPLAY

for abi in $abis; do
    case $abi in
        arm64-v8a) triple=aarch64-linux-android; arch=__aarch64__; cpu=arm64 ;;
        armeabi-v7a) triple=armv7a-linux-androideabi; arch=__arm__; cpu=none ;;
        x86) triple=i686-linux-android; arch=__i386__; cpu=none ;;
        x86_64) triple=x86_64-linux-android; arch=__x86_64__; cpu=x64 ;;
        *) echo "unsupported Android ABI: $abi" >&2; exit 1 ;;
    esac
    out=build/android/$abi
    mkdir -p "$out"
    "$CMAKE" -S native -B "$out/native" -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$api" -DCMAKE_BUILD_TYPE=Release \
        -DOPUS_DIR="$opus" -DSAMPLERATE_DIR="$samplerate" -DDR_LIBS_DIR="$dr_libs" -DSTB_DIR="$stb" >"$out/cmake.log"
    "$CMAKE" --build "$out/native" --parallel 2 >>"$out/cmake.log"
    libopus=$(find "$out/native" -name libopus.a | head -n 1)
    libsamplerate=$(find "$out/native" -name libsamplerate.a | head -n 1)
    libmp3=$out/native/libziran_mp3.a
    libvorbis=$out/native/libziran_vorbis.a
    test -n "$libopus" && test -n "$libsamplerate" && test -f "$libmp3" && test -f "$libvorbis"
    CC="$bin/$triple$api-clang" CFLAGS="-O2 -Wno-parentheses-equality" LDLIBS="$libmp3 $libvorbis $libopus $libsamplerate -lm" \
        "$ZIRAN" build --target=c --exe --target-os android --target-cpu "$cpu" --define ANDROID_BUILD --define "$arch" \
        --root src --module-path src --entry audio:main -o "$out/bin" src/audio.zi
    file "$out/bin/audio" | grep -q 'ELF'
    printf 'android %s: libopus, libsamplerate, libziran_mp3, libziran_vorbis and audio CLI built (API %s)\n' "$abi" "$api"
done

serial=${ANDROID_SERIAL:-}
if test -z "$serial"; then
    echo "Android ABIs built; set ANDROID_SERIAL to run the device decode test"
    exit 0
fi
abi=$(adb -s "$serial" shell getprop ro.product.cpu.abi | tr -d '\r')
test -x "build/android/$abi/bin/audio" || { echo "device ABI $abi was not built" >&2; exit 1; }
remote=/data/local/tmp/ziran-audio-test
host=build/android/device
rm -rf "$host"; mkdir -p "$host/linux"
adb -s "$serial" shell "rm -rf $remote && mkdir -p $remote" >/dev/null
adb -s "$serial" push "build/android/$abi/bin/audio" "$remote/audio" >/dev/null
for name in short.opus voice.opus chirp.opus voice.wav chirp.wav; do
    adb -s "$serial" push "$fixtures/$name" "$remote/$name" >/dev/null
done
for name in $mp3s; do adb -s "$serial" push "tests/fixtures/mp3/$name" "$remote/$name" >/dev/null; done
for name in $oggs; do adb -s "$serial" push "tests/fixtures/vorbis/${name#vorbis-}" "$remote/$name" >/dev/null; done
# The same commands run on the device and with the Linux CLI.
cat >"$host/commands" <<'EOF'
inspect short.opus
inspect voice.opus
decode short.opus short.wav
decode voice.opus voice-decoded.wav
decode chirp.opus chirp-decoded.wav
resample voice.wav voice-16k.wav --rate 16000
resample chirp.wav chirp-44k.wav --rate 44100
encode voice.wav voice-encoded.opus --bitrate 24000 --application voice --bandwidth wide --vbr constrained
resample vbr.mp3 vbr-48k.wav --rate 48000
resample vorbis-stereo.ogg vorbis-48k.wav --rate 48000
EOF
for name in $mp3s $oggs; do printf 'inspect %s\ndecode %s %s-decoded.wav\n' "$name" "$name" "${name%.*}" >>"$host/commands"; done
script="cd $remote && chmod 755 audio"
while read -r line; do script="$script && ./audio $line"; done <"$host/commands"
adb -s "$serial" shell "$script" >"$host/device.log" 2>&1 || { cat "$host/device.log" >&2; exit 1; }
for name in short.wav voice-decoded.wav chirp-decoded.wav voice-16k.wav chirp-44k.wav voice-encoded.opus vbr-48k.wav vorbis-48k.wav; do
    adb -s "$serial" pull "$remote/$name" "$host/$name" >/dev/null
done
for name in $mp3s $oggs; do adb -s "$serial" pull "$remote/${name%.*}-decoded.wav" "$host/${name%.*}-decoded.wav" >/dev/null; done
adb -s "$serial" shell "rm -rf $remote" >/dev/null
for name in short.opus voice.opus chirp.opus voice.wav chirp.wav; do cp "$fixtures/$name" "$host/linux/$name"; done
for name in $mp3s; do cp "tests/fixtures/mp3/$name" "$host/linux/$name"; done
for name in $oggs; do cp "tests/fixtures/vorbis/${name#vorbis-}" "$host/linux/$name"; done
(cd "$host/linux" && while read -r line; do "$root/build/bin/audio" $line; done <../commands) >"$host/linux.log" 2>&1
# shellcheck disable=SC2086
python3 tests/android_compare.py "$host" "$abi" "$serial" $mp3s $oggs
