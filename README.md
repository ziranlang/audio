# Audio for Ziran

Reusable Opus encoding/decoding, Ogg Opus inspection, best-quality sinc
sample-rate conversion and WAV I/O, with a native `audio` command. There is
no Kryon, Raylib, audio-device or runtime subprocess dependency. GUI hosts
choose their own playback sink and call the same modules as command-line tools.

## Build and use

Install Ziran plus the development/link libraries for **libopus** and
**libsamplerate** (`libopus-dev` and `libsamplerate0-dev` on Debian-family
Linux), then run:

```sh
make
build/bin/audio --help
build/bin/audio encode input.wav output.opus --bitrate 64000 --vbr on
build/bin/audio encode voice.wav voice.opus --bitrate 24000 --application voice --bandwidth wide --vbr constrained
build/bin/audio inspect output.opus
build/bin/audio decode output.opus decoded.wav
build/bin/audio transcode input.opus smaller.opus --bitrate 32000
build/bin/audio resample input.wav speech.wav --rate 16000
```

The CLI supports PCM16 and IEEE float32 RIFF WAV input, and mapping-family-0
Ogg Opus (mono/stereo) with the exact 19-byte version-1 identification header.
Other Opus header versions/extensions are outside this bounded profile.
Decoded WAV output is PCM16 at 48 kHz. `resample`
accepts either format and writes PCM16 WAV at the requested 8000–192000 Hz
rate. `transcode` decodes WAV/Opus and encodes Opus; it is a lossy re-encode
when its source is already Opus. Other audio formats belong to separate
modules; existing `std/vorbis` and `std/vorbis_linux` support is independent.

Encoder options are `--bitrate` in bits/second (6000–510000), `--vbr`
`on|off|constrained`, `--bandwidth` `auto|narrow|wide|superwide|full`,
`--application` `audio|voice|lowdelay`, `--complexity` 0–10 and `--frame-ms`
5, 10, 20, 40 or 60. Defaults are 96000 bps, VBR, automatic bandwidth,
audio application, complexity 10 and 20 ms. The bandwidth option is a **cap**;
libopus still chooses its actual bandwidth. Constrained VBR is a separate
rate-control setting. The six-kilohertz medium-band cap is omitted because
libopus can choose a wide-band CELT packet for that setting. Neither a bitrate target nor constrained VBR guarantees
a particular file size or quality.

Non-48-kHz input is converted with libsamplerate's `SRC_SINC_BEST_QUALITY`
before encoding. This is a band-limited sinc converter, including for 44.1→48
kHz. Float PCM keeps finite headroom through resampling/encoding; sinc can
overshoot a normalized transient. `ValidPCM` admits finite values in [-16,16].
PCM16 WAV and Kryon's PCM16 sink explicitly clip to [-1,32767/32768] at the
integer boundary. There is no implicit loudness normalization.

Files contain up to 200 ms of packets per Ogg page, bounded by the format's
255 lacing entries and 65025 body bytes. This amortizes page overhead for
low-bitrate audio. The packet API retains individual frames for callers that
need lower latency. On the tested synthetic three-second mono 440 Hz fixture,
16 kbps voice-mode output occupied 6877 bytes including 18 pages, versus
288044 bytes of PCM16 WAV. This is a fixture measurement, not a speech or
music quality benchmark.

CLI operations validate/process into memory before touching the destination.
They stage output in an exclusively created `OUTPUT.audio-part` file beside
the destination and rename it only after a complete write/close. Errors preserve
an existing output. An existing staging file causes an error and is preserved.
Literal and resolved source/destination aliases are rejected. The CLI does
not play audio or open audio devices.

## Callable modules

Exports are `audio/types`, `audio/ogg`, `audio/wav`, `audio/opus`,
`audio/resample` and `audio/pipeline`.
Full-pipeline native consumers declare `links = ["opus", "samplerate", "m"]` in their
root manifest's `[package]` table, or use equivalent linker flags in a custom
host. Ziran does not inherit system links from dependencies. Codec-only consumers need
only `links = ["opus", "m"]`; `audio/opus` does not import the resampler.

```zi
Types :: #import "audio/types"
Pipeline :: #import "audio/pipeline"
#import "std/vec"

EncodeAudio :: (pcm: *Types.PCM, output: *Vec(u8)) -> s32 {
    options := Types.DefaultOptions()
    options.bitrate = 64000
    options.bandwidth = Types.Bandwidth.Full
    return Pipeline.Encode(pcm, options, output)
}
```

`PCM` owns interleaved `Vec(float32)` samples plus `rate:s32` and
`channels:s32`. Pass it by pointer. Ordinary vector cleanup releases sample
storage. `SwapSamples(*PCM,*Vec(float32))` transfers sample ownership without
copying. Whole-buffer convenience calls leave their output unchanged on an
error and return a status from `audio/types` (`ErrorText` gives a short message):

- `audio/pipeline.Encode(*PCM, Options, *Vec(u8)) -> s32`
- `Decode([]u8, max_frames:s64, *PCM) -> s32`
- `Resample(*PCM, target_rate:s32, *PCM) -> s32`, with distinct input/output
- `Inspect([]u8, *Info) -> s32`, clearing `Info` on failure
- `WavDecode([]u8, max_frames:s64, *PCM) -> s32`
- `WavEncode(*PCM, *Vec(u8)) -> s32`

`Info` reports channels, 48000-Hz output rate, original-rate header hint,
logical frame count, pre-skip, signed Q8 gain and packet count. Decode applies
the header gain, discards pre-skip and honors final-granule end trim. Original
sample rate is informational and does not change the Ogg 48-kHz timebase.

Whole-buffer PCM is limited to 28800000 frames and encoded/input bytes to
256 MiB. `max_frames` can impose a smaller eager-decoding cap. Inspection
and incremental decode instead permit up to 24 hours at 48 kHz, without
allocating full PCM. Ogg packets/comments are bounded to 65536 bytes. These
limits are explicit capability boundaries, including on otherwise valid input.

## Incremental APIs and ownership

`DecoderOpen(*Decoder, input:[]u8, max_frames:s64) -> s32` validates the
single logical stream, then `DecoderRead(*Decoder, output:[]float32,
frames:*s64) -> s32` fills caller-owned interleaved scratch. Output may be as
small as one frame. `OK` with zero returned frames means logical EOF. A
failed read may already have filled a prefix; discard that read on error.
`DecoderRewind(*Decoder) -> s32` resets the codec over the previously validated
input without scanning the whole file again. `DecoderClose(*Decoder)` is
idempotent and releases native state. Scratch is bounded to one 120 ms Opus
packet plus one 65536-byte Ogg packet, regardless of track duration. Input
bytes are borrowed: keep them alive **and unchanged** until close.

`EncoderOpen(*Encoder, channels:s32, Options) -> s32` opens a 48-kHz encoder.
`EncoderPacket(*Encoder, pcm:[]float32, packet:[]u8, written:*s32) -> s32`
requires exactly its configured frame size and caller-owned packet storage
(4096 bytes is sufficient for supported frame durations). It produces a raw
Opus packet; it does not attach Ogg headers or timing. `Encoder.lookahead`
is the required Ogg pre-skip. Close it with `EncoderClose(*Encoder)`.

`SincOpen(*SincState, channels, from_rate, to_rate) -> s32` selects best sinc.
`SincProcess(*SincState, input:[]float32, output:[]float32, final:bool,
used:*s64, generated:*s64) -> s32` reports **frame** counts, not sample counts.
Buffers must be disjoint. Retain unconsumed input; on the final chunk use
`final=true`, then drain with an empty input until zero output. The state marks
itself ended after that drain. `SincClose(*SincState)` is idempotent. A whole
conversion and irregular streaming chunks share the same filter state/quality.

Live encoder/decoder/sinc states have one owner. Do not copy them, call them
concurrently, or replace their borrowed storage. Use separate states for
separate streams. The CLI conveniences are bounded whole-file operations;
only the explicit state APIs stream PCM.

## Android

The manifest pins the codec sources as `source = true` dependencies:
`libopus` (xiph/opus v1.5.2) and `libsamplerate` (libsndfile/libsamplerate
0.2.2). An NDK CMake build includes `native/AudioCodecs.cmake` and calls
`ziran_audio_codecs("<libopus>" "<libsamplerate>")` with the paths from
`ziran pkg path libopus` / `ziran pkg path libsamplerate`. It defines static,
position-independent `opus` and `samplerate` targets (float API; no programs,
tests or DNN extensions) to link into the app's native library. Generate the
app's C with Breeze's Android defines, `--define ANDROID_BUILD` plus the ABI's
`__aarch64__`, `__arm__`, `__i386__` or `__x86_64__`; `std` file mapping and
renames need them on bionic.

`make android-test` (after `make test`) builds both libraries and the CLI with
NDK 28.2.13676358 at API 21 for arm64-v8a, armeabi-v7a, x86 and x86_64
(`ANDROID_NDK_HOME`, `ANDROID_API` and `ANDROID_ABIS` override this). With
`ANDROID_SERIAL=SERIAL` it runs inspect, decode, resample and encode on that
device and compares the output with the Linux CLI. On a Moto e6 play
(armeabi-v7a, Android 9), decoded and resampled PCM16 matched Linux exactly
and the device-encoded stream decoded on Linux at the source duration. The
other three ABIs are build-tested only.

## Windows

The same recipe builds static `libopus.a` and `libsamplerate.a` for
x86_64 MinGW. With the pinned sources from `ziran pkg path`:

```sh
cmake -S native -B build/windows/native -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_SYSTEM_PROCESSOR=AMD64 -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_BUILD_TYPE=Release \
    -DOPUS_DIR="$(ziran pkg path libopus)" -DSAMPLERATE_DIR="$(ziran pkg path libsamplerate)"
cmake --build build/windows/native
```

The archives are `build/windows/native/libopus/libopus.a` and
`build/windows/native/libsamplerate/src/libsamplerate.a` (a CMake consumer
calls `ziran_audio_codecs` and links the `opus` target). Generate C with
`--define _WIN32 --define __x86_64__`; no other define is needed. libopus
keeps its default stack protector and `_FORTIFY_SOURCE=2`, so a MinGW link
adds GCC's `-lssp` after the archives: decoder-only consumers link
`libopus.a -lssp -lm`, full-pipeline consumers `libopus.a libsamplerate.a
-lssp -lm`. With `-static -static-libgcc` the programs import only
`kernel32`, `msvcrt` and `advapi32`.

`make windows-test` (after `make test`; `WINDOWS_CC` names the compiler)
builds both archives and two codec programs, then runs them in a private
Wine prefix under a private Xvfb display and compares them with the Linux
CLI. The decoder-only program streams nine mono/stereo fixtures through
`DecoderOpen`/`DecoderRead` in 997-frame chunks, rewinds with
`DecoderRewind` and requires an identical second pass. Its inspection
lines, five malformed-stream rejections and decoded frame counts matched
Linux; PCM16 differed by at most 2 LSBs against the system libopus build
(3 of 9 bit-exact). The full-pipeline program encoded `voice.wav` with the
CLI's 24 kbps voice settings to the same size as Linux; Linux decoded it to
the source duration. This was tested with Nix MinGW GCC 15.3.0 and Debian
Wine 10.0, not on Windows hardware. Windows sinc resampling still returns
`Unsupported`, so the pipeline accepts only 48-kHz input there. The `audio`
CLI itself is not built for Windows: Ziran's `std/file_tree_linux` has no
Win32 implementation.

## Validation and target support

Ogg inspection checks capture/version, CRC, stream serial, page sequence,
BOS/EOS, continuation/lacing, bounded tags, TOC durations, granule monotonicity,
pre-skip and end trim. This bounded profile requires nonempty Ogg pages.
It rejects truncation, trailing/chained/multiplexed
streams, multichannel mappings and nonzero initial timeline offsets. Inspection
validates the container and declared packet duration; libopus validates packet
payloads as they are decoded. It does not claim to validate an unheard packet's
compressed bitstream. Rewind assumes the validated bytes stayed unchanged.

Native codec and sinc execution is tested with Linux x86-64 C against the
system libopus 1.5.2 and libsamplerate 0.2.2, and on Android (see below). The
SRC_DATA C-long ABI is represented by `isize` on Unix C targets, including
32-bit Android. Windows sinc execution returns `Unsupported` before FFI,
because Windows C `long` is 32 bits. Windows x86_64 codec execution is
tested under Wine (see above); macOS codec execution is unverified. Kryon's
native provider plays Ogg Opus through these modules on Linux, Android
(Kryon commit 34e552d) and Windows MinGW (Kryon commit 34d0ce4, linking
`libopus.a -lssp -lm`); macOS still reports `Unsupported`, and browser
playback uses the browser's own WebAudio decoder. Codec FFI and sinc are not
portable VM implementations; reachable native calls reject bundling instead
of fabricating output. Portable Ogg/WAV modules execute from source and saved
IR in C, Go and `.zx` without codec libraries. The CLI's variadic libopus
controls require the C target; Go CLI/native codec builds are not supported.

Run `make test` for source/saved-IR native codec+CLI tests, portable VM/Go
execution, FFI rejection, streaming parity, alias rejection, transients,
malformed data, atomic output and FFmpeg interoperability. Python and FFmpeg
are test tools only. Strict voice/chirp PCM comparison forces FFmpeg's
libopus decoder (within 1 PCM16 LSB). FFmpeg's independent decoder also checks
duration and the CELT sine fixtures; SILK/resampler implementations can differ
without a container timing error. No listening score or universal compression
quality claim follows from these tests.

References: [Opus public API 1.5](https://www.opus-codec.org/docs/opus_api-1.5.pdf),
[RFC 7845 Ogg Opus](https://www.rfc-editor.org/rfc/rfc7845.html),
[libsamplerate state API](https://libsndfile.github.io/libsamplerate/api_full.html).
