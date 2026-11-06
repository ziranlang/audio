#!/bin/sh
# Windows x86_64 MinGW build of the pinned libopus/libsamplerate sources and
# two codec programs, run under Wine and compared with the Linux CLI on the
# `make test` fixtures. Invoke through build-queue (`make windows-test`).
# WINDOWS_CC names the MinGW compiler (default x86_64-w64-mingw32-gcc).
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
ZIRAN=${ZIRAN:-ziran}
CMAKE=${CMAKE:-cmake}
windows_cc=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}
command -v "$windows_cc" >/dev/null 2>&1 || { echo "MinGW compiler $windows_cc not found (set WINDOWS_CC)" >&2; exit 1; }
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER GDK_DISPLAY LISTEN_PID LISTEN_FDS LISTEN_FDNAMES NOTIFY_SOCKET LDFLAGS LDLIBS
export YUE_DESKTOP_RECOVERY=0 WINEDEBUG=-all
fixtures=build/tests/fixtures
decoded="short voice chirp external-1 external-2 full narrow vbr-off encoded-2"
rejected="bad-crc truncated chained trailing bad-preskip"
for name in $decoded $rejected; do
    test -f "$fixtures/$name.opus" || { echo "missing $fixtures/$name.opus; run make test first" >&2; exit 1; }
done
test -f "$fixtures/voice.wav" && test -x build/bin/audio || { echo "missing Linux fixtures/CLI; run make test first" >&2; exit 1; }
out=build/windows
git check-ignore -q "$out/probe"
mkdir -p "$out/run" "$out/home" "$out/config" "$out/data" "$out/cache" "$out/runtime" "$out/tmp"
chmod 700 "$out/runtime"

opus=$("$ZIRAN" pkg path libopus --offline)
samplerate=$("$ZIRAN" pkg path libsamplerate --offline)
# Static archives only, so configure checks need no Windows executable link.
"$CMAKE" -S native -B "$out/native" -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=AMD64 \
    -DCMAKE_C_COMPILER="$(command -v "$windows_cc")" -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_BUILD_TYPE=Release -DOPUS_DIR="$opus" -DSAMPLERATE_DIR="$samplerate" >"$out/cmake.log" 2>&1 &&
    "$CMAKE" --build "$out/native" --parallel 2 >>"$out/cmake.log" 2>&1 || { tail -n 40 "$out/cmake.log" >&2; exit 1; }
libopus=$out/native/libopus/libopus.a
libsamplerate=$out/native/libsamplerate/src/libsamplerate.a
test -f "$libopus" && test -f "$libsamplerate"

# Nix splits mcfgthread's static runtime from its GCC wrapper; follow only
# this compiler's declared inputs. Distribution MinGW needs no extra path.
set --
if [ "$("$windows_cc" -print-file-name=libmcfgthread.a)" = libmcfgthread.a ]; then
    cc_root=$(dirname "$(dirname "$(readlink -f "$(command -v "$windows_cc")")")")
    inputs="$cc_root/nix-support/propagated-target-target-deps"
    if [ -f "$inputs" ]; then
        for input in $(cat "$inputs"); do
            for runtime in "$input" $(cat "$input/nix-support/propagated-build-inputs" 2>/dev/null || :); do
                if [ -f "$runtime/lib/libmcfgthread.a" ]; then set -- "-L$runtime/lib"; break; fi
            done
            [ "$#" -eq 0 ] || break
        done
    fi
fi
ziran_root=$("$ZIRAN" pkg path ziran --offline)
test -f "$ziran_root/include/zir_vec.h" || { echo "no Ziran C headers under $ziran_root" >&2; exit 1; }
# libopus keeps its default stack protector and _FORTIFY_SOURCE, which on
# MinGW resolve from GCC's static libssp.
for program in decode encode; do
    libs="$libopus"
    test "$program" = decode || libs="$libopus $libsamplerate"
    rm -rf "$out/$program-c"
    "$ZIRAN" build --target=c --no-main --define _WIN32 --define __x86_64__ --root tests \
        --module-path src -o "$out/$program-c" "tests/windows_$program.zi"
    # shellcheck disable=SC2086
    "$windows_cc" "$@" -O2 -std=c11 -ffunction-sections -fdata-sections -I"$out/$program-c" -I"$ziran_root/include" \
        "$out/$program-c"/*.c $libs -lssp -lm -Wl,--gc-sections -static -static-libgcc -o "$out/run/windows_$program.exe"
    objdump -p "$out/run/windows_$program.exe" | sed -n 's/^\s*DLL Name: //p' | tr 'A-Z' 'a-z' | sort -u >"$out/$program.dlls"
    if grep -v -E '^(kernel32|msvcrt|ucrtbase|api-ms-win-crt-.*|advapi32|user32|shell32|ntdll)\.dll$' "$out/$program.dlls"; then
        echo "windows_$program.exe imports a non-system DLL" >&2; exit 1
    fi
done
printf 'windows: libopus, libsamplerate and codec programs built with %s\n' "$("$windows_cc" -dumpversion)"

cd "$out/run"
for name in $decoded $rejected; do cp "$root/$fixtures/$name.opus" .; done
cp "$root/$fixtures/voice.wav" .
mkdir -p linux
{
    for name in $decoded; do echo "inspect $name.opus"; echo "decode $name.opus $name-decoded.wav"; done
    for name in $rejected; do echo "reject $name.opus"; done
} >decode.commands
# Linux reference: the CLI on the same inputs (reject = CLI decode status).
rm -f linux/*
(cd linux && for name in $decoded; do
    "$root/build/bin/audio" inspect "../$name.opus"
    "$root/build/bin/audio" decode "../$name.opus" "$name-decoded.wav" >/dev/null
done && for name in $rejected; do "$root/build/bin/audio" decode "../$name.opus" rejected.wav || :; done
"$root/build/bin/audio" encode ../voice.wav voice.opus --bitrate 24000 --application voice --bandwidth wide --vbr constrained >/dev/null) >linux/linux.log
rm -f ./*-decoded.wav windows-voice.opus
# Wine state stays private to this output; package lookups above keep the
# normal Ziran cache.
export TMPDIR="$root/$out/tmp" XDG_CONFIG_HOME="$root/$out/config" XDG_DATA_HOME="$root/$out/data" \
    XDG_CACHE_HOME="$root/$out/cache" XDG_RUNTIME_DIR="$root/$out/runtime" WINEPREFIX="$root/$out/wine"
wine=$(command -v wine)
WINESERVER=$(command -v wineserver 2>/dev/null || :)
if [ -z "$WINESERVER" ]; then
    for server in "$(dirname "$(readlink -f "$wine")")/wineserver" /usr/lib/x86_64-linux-gnu/wine/wineserver /usr/lib/wine/wineserver; do
        if [ -x "$server" ]; then WINESERVER=$server; break; fi
    done
fi
[ -n "$WINESERVER" ] && [ -x "$WINESERVER" ] || { echo 'Windows test requires the Wine server (install wine64)' >&2; exit 1; }
export WINESERVER
# Debian Wine 10 frees secure_getenv("TMPDIR") without /run/user/$uid
# (Debian #1110936), so Wine alone runs without TMPDIR. The private Xvfb only
# serves wineboot; no desktop display or input is used.
xvfb-run -a -n 400 -s '-screen 0 640x480x24' env -u TMPDIR HOME="$root/$out/home" sh -eu -c '
    unset WINEARCH WINELOADER WINEDLLPATH WINEDLLOVERRIDES WINELOADERNOEXEC
    export WINEARCH=win64
    cleanup() {
        result=$?
        trap - EXIT HUP INT TERM
        "$WINESERVER" -k || :
        "$WINESERVER" -w || :
        exit "$result"
    }
    trap cleanup EXIT
    trap "exit 129" HUP; trap "exit 130" INT; trap "exit 143" TERM
    WINEDEBUG=err+all "$1" wineboot.exe --init 2>wineboot.log || { cat wineboot.log >&2; echo "Wine bootstrap failed" >&2; exit 1; }
    while read -r line; do "$1" windows_decode.exe $line; done <decode.commands >windows.log
    "$1" windows_encode.exe encode voice.wav windows-voice.opus >>windows.log
    "$1" windows_encode.exe resample voice.wav 16000 >resample.log
    "$1" windows_decode.exe decode windows-voice.opus windows-voice-decoded.wav >>windows.log
' sh "$wine"
cd "$root"
python3 tests/windows_compare.py "$out/run" build/bin/audio $decoded -- $rejected
