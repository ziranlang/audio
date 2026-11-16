# Audio for Ziran

Reusable Opus encoding/decoding, MP3 and Ogg Vorbis decoding, Ogg Opus, Ogg
Vorbis and MPEG audio inspection, best-quality sinc sample-rate conversion and
WAV I/O, with a native `audio` command. There is
no Kryon, Raylib, audio-device or runtime subprocess dependency. GUI hosts
choose their own playback sink and call the same modules as command-line tools.

## Build and use

Install Ziran, CMake plus the development/link libraries for **libopus** and
**libsamplerate** (`libopus-dev` and `libsamplerate0-dev` on Debian-family
Linux). The MP3 and Vorbis decoders are compiled from the pinned `dr_libs`
and `stb` sources: `make` builds `build/native/linux/libziran_mp3.a` and
`build/native/linux/libziran_vorbis.a` through `native/CMakeLists.txt` before
the CLI. Then run:

```sh
make
build/bin/audio --help
build/bin/audio encode input.wav output.opus --bitrate 64000 --vbr on
build/bin/audio encode voice.wav voice.opus --bitrate 24000 --application voice --bandwidth wide --vbr constrained
build/bin/audio inspect output.opus
build/bin/audio decode output.opus decoded.wav
build/bin/audio transcode input.opus smaller.opus --bitrate 32000
build/bin/audio resample input.wav speech.wav --rate 16000
build/bin/audio inspect song.mp3
build/bin/audio decode song.mp3 song.wav
build/bin/audio resample song.mp3 song-48k.wav --rate 48000
build/bin/audio inspect music.ogg
build/bin/audio decode music.ogg music.wav
build/bin/audio resample music.ogg music-48k.wav --rate 48000
```

Formats are chosen from the content, not the file name: `OggS` whose first
packet is a Vorbis identification header is Ogg Vorbis, any other `OggS` is
Ogg Opus, `RIFF` is WAV, anything else is read as MPEG audio. `inspect` on an
MP3 prints the MPEG version and layer, channels, rate, exact frames and
duration, bitrate, VBR or CBR, the LAME delay/padding and the frame count:

```text
MP3: MPEG-1 Layer III, 2 channels, 44100 Hz, 13230 frames, 0.300 s, 128000 bps CBR, delay 1105, padding 641, 13 MPEG frames
```

On Ogg Vorbis it prints the channels, rate, exact frames and duration, the
nominal bitrate hint, the block sizes, mode count, end trim and packet and
comment counts, then the vendor string and each comment (control bytes shown
as `?`):

```text
Vorbis: 1 channels, 32000 Hz, 9600 frames, 0.300 s, 52000 bps nominal, blocks 256/2048, 2 modes, end trim 0, 13 packets, 4 comments
Vorbis vendor: ffmpeg
Vorbis comment: encoder=Lavc libvorbis
Vorbis comment: title=Ziran fixture
Vorbis comment: artist=Ziran audio
Vorbis comment: DESCRIPTION=Vorbis comments, ünïcödé
```

The CLI supports PCM16 and IEEE float32 RIFF WAV input, and mapping-family-0
Ogg Opus (mono/stereo) with the exact 19-byte version-1 identification header.
Other Opus header versions/extensions are outside this bounded profile.
Decoded Opus WAV output is PCM16 at 48 kHz; decoded MP3 and Vorbis WAV
output is PCM16 at the stream's own rate. `resample`
accepts either format and writes PCM16 WAV at the requested 8000–192000 Hz
rate. `transcode` decodes WAV, Opus, Vorbis or MP3 and encodes Opus; it is a
lossy re-encode unless its source is WAV. Ziran's whole-file `std/vorbis` and
`std/vorbis_linux` are independent of `audio/vorbis`.

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
`audio/resample`, `audio/pipeline`, `audio/mpeg_audio`, `audio/mp3`,
`audio/mp3_resample`, `audio/ogg_vorbis`, `audio/vorbis` and
`audio/vorbis_resample`.
Full-pipeline native consumers declare `links = ["opus", "samplerate", "m"]` in their
root manifest's `[package]` table, or use equivalent linker flags in a custom
host. Ziran does not inherit system links from dependencies. Codec-only consumers need
only `links = ["opus", "m"]`; `audio/opus` does not import the resampler.
MP3 decode-only consumers link `libziran_mp3.a` and `-lm`
(`links = ["ziran_mp3", "m"]` with the archive's directory in `LDFLAGS`);
`audio/mp3_resample` adds `samplerate`. `audio/mpeg_audio` is portable.
Vorbis decode-only consumers likewise link `libziran_vorbis.a` and `-lm`
(`links = ["ziran_vorbis", "m"]`); `audio/vorbis_resample` adds
`samplerate`, and `audio/ogg_vorbis` is portable.

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

## MP3

`audio/mp3` decodes MPEG-1, MPEG-2 and MPEG-2.5 audio, Layers I, II and III,
mono and stereo, through [dr_mp3](https://github.com/mackron/dr_libs) (public
domain or MIT-0; its `LICENSE` is in the pinned source). The manifest pins
`dr_libs` at commit `f12e197fd462e4c22873fbd70d11b1d2f2c1dc3c` (dr_mp3 0.7.5)
as a `source = true` dependency. `native/ziran_mp3.c` is dr_mp3's one
implementation unit, built with float output and no stdio, plus two calls
that size and free the native decoder state. Redistributors ship dr_libs'
`LICENSE` alongside the binary as they do libopus' `COPYING`.

- `Mp3Inspect([]u8, *Mp3Info) -> s32` (`audio/mpeg_audio`, portable)
- `Mp3DecoderOpen(*Mp3Decoder, input:[]u8, max_frames:s64) -> s32`, or
  `Mp3DecoderOpenFile(*Mp3Decoder, path, max_frames)`, which reads the file
  (at most 256 MiB) into the decoder
- `Mp3DecoderRead(*Mp3Decoder, []float32, frames:*s64)` and
  `Mp3DecoderReadS16(*Mp3Decoder, []s16, frames:*s64)`: interleaved chunks
  of whole frames
- `Mp3DecoderSeek(*Mp3Decoder, frame:s64)`, `Mp3DecoderRewind`, and the
  idempotent `Mp3DecoderClose`
- `Mp3Decode([]u8, max_frames, *PCM)` and
  `Mp3DecodeS16([]u8, max_frames, *Vec(s16), *Mp3Info)`: whole file
- `Mp3DecodeResampled([]u8, max_frames, rate, *PCM)` (`audio/mp3_resample`):
  whole file through `audio/resample`'s best sinc

`Mp3Info` gives the MPEG version (1, 2 or 25) and layer, channels, rate,
exact PCM `frames`, `mp3_frames`, `frame_samples`, LAME `delay`/`padding`,
`bitrate` (nominal for CBR, average for VBR), `vbr`, and the frame byte range;
`Mp3Seconds` converts frames to seconds. With a Xing/Info header the frame
count is its declared frames times the frame length less the LAME encoder
delay (+529) and padding (−529), so duration is exact without decoding, as
FFmpeg trims it; without one it is the walked frames times the frame length.
VBR is a Xing or VBRI header or a bitrate change between frames.

Inspection walks every frame header before dr_mp3 sees the bytes. It skips
leading ID3v2 tags (several, with footers) and trailing ID3v1 and APEv2 tags,
then requires complete frames that keep the first frame's version, layer,
rate and channel count, optionally followed by zero padding. A partial last
frame, fewer frames than a Xing header declares, junk between frames, a
mono/stereo or rate change (`Unsupported`), free-format frames
(`Unsupported`) and non-MPEG input are rejected; dr_mp3 is then opened over
just the validated frame bytes. A decoder that ends before the declared frame
count fails the read with `Malformed`. Lyrics3 tags and mid-stream tags are
outside this bounded profile.

Reads behave like `DecoderRead`: caller-owned interleaved scratch of whole
frames, `OK` with zero frames at the logical end, and a failed read may have
filled a prefix. S16 samples are the float output through `Pcm16` (clip to
[-1, 32767/32768], scale by 32768, truncate), the same PCM16 boundary
`WavEncode` uses, so they equal the CLI's decoded WAV. Seeks
land on the exact requested frame: the decoder binds a seek table of about
one point per second (at most 16384) at open, starts up to 16 frames before
the target and decodes forward, so the samples after a seek are bit-identical
to a linear decode. Input bytes are borrowed until close, as for Opus. Live
decoders have one owner and must not be copied or shared across threads.
For streaming at another rate, pass `Mp3DecoderRead` chunks to
`SincOpen`/`SincProcess`.

## Ogg Vorbis

`audio/vorbis` decodes Ogg Vorbis (Vorbis I, floor 1, mono and stereo,
8–192 kHz) through [stb_vorbis](https://github.com/nothings/stb) (public
domain or MIT; its `LICENSE` is in the pinned source). The manifest pins
`stb` at commit `9600522de53973336fa033a289858a4354cbb04c` (stb_vorbis 1.24)
as a `source = true` dependency. `native/ziran_vorbis.c` is stb_vorbis' one
implementation unit, built without stdio, the pushdata API, integer
conversion or comment parsing, plus open, read and seek calls.
Redistributors ship stb's `LICENSE` alongside the binary.

- `VorbisProbe([]u8) -> bool` and `VorbisInspect([]u8, *VorbisInfo) -> s32`
  (`audio/ogg_vorbis`, portable); `VorbisInspectComments([]u8, *VorbisInfo,
  *VorbisComments)` also copies the comment header
- `VorbisDecoderOpen(*VorbisDecoder, input:[]u8, max_frames:s64) -> s32`, or
  `VorbisDecoderOpenFile(*VorbisDecoder, path, max_frames)`, which reads the
  file (at most 256 MiB) into the decoder
- `VorbisDecoderRead(*VorbisDecoder, []float32, frames:*s64)` and
  `VorbisDecoderReadS16(*VorbisDecoder, []s16, frames:*s64)`: interleaved
  chunks of whole frames
- `VorbisDecoderSeek(*VorbisDecoder, frame:s64)`, `VorbisDecoderRewind`, and
  the idempotent `VorbisDecoderClose`
- `VorbisDecode([]u8, max_frames, *PCM)` and
  `VorbisDecodeS16([]u8, max_frames, *Vec(s16), *VorbisInfo)`: whole file
- `VorbisDecodeResampled([]u8, max_frames, rate, *PCM)`
  (`audio/vorbis_resample`): whole file through `audio/resample`'s best sinc
- `VorbisVendor`, `VorbisCommentCount`, `VorbisComment(*VorbisComments,
  index)` and `VorbisCommentValue(*VorbisComments, field)`, which matches the
  field name without regard to ASCII case; an open decoder holds its
  stream's comments in `decoder.comments`

`VorbisInfo` gives channels, rate, exact PCM `frames`, the header's nominal,
maximum and minimum bitrate hints (0 when unset), the short and long block
sizes, the mode count, audio `packets`, the comment count and `end_trim`;
`VorbisSeconds` converts frames to seconds. `frames` is the final granule
position, which trims the last packet, so the duration is exact without
decoding; libvorbisfile's `ov_pcm_total` agrees on every fixture.

Inspection reads the whole stream before stb_vorbis sees it, because
stb_vorbis checks neither page CRCs nor serial numbers. `audio/ogg`'s reader
checks every page (capture, CRC, one serial, sequence, BOS/EOS, lacing).
The identification header must be a 30-byte version-0 header on its own BOS
page; the comment header's vendor, comments and framing bit must fit its
packet; the setup header must end its page. The mode table is read
backwards from the setup header's framing bit, as FFmpeg's and liboggz's
parsers do, so every audio packet's block size, and with it each page's
granule position, is checked: the timeline must start at zero, and the
final granule may only trim frames that were decoded. Truncation (even one
byte), CRC errors, trailing bytes, non-audio packets and granule mismatches
are `Malformed`; chained or multiplexed streams (a second beginning-of-stream
page), a timeline not starting at zero, more than two channels and rates
outside 8000–192000 Hz are `Unsupported`. Floor 0 streams (pre-2004
encoders) fail to open in stb_vorbis and return `Malformed`. A decoder that
ends before the final granule position fails the read with `Malformed`.

Reads behave like `DecoderRead`: caller-owned interleaved scratch of whole
frames, `OK` with zero frames at the logical end, and a failed read may have
filled a prefix. `ziran_vorbis_read` keeps decoding past frames that return
no samples, which stb_vorbis' own interleaved reader treats as the end. S16
samples are the float output through `Pcm16`, as for MP3. Seeks land on the
exact requested frame: stb_vorbis bisects the pages for the one holding it,
then decodes forward from the packet before, so the samples after a seek
are bit-identical to a linear decode. Input bytes are borrowed until close.
Live decoders have one owner and must not be copied or shared across
threads. For streaming at another rate, pass `VorbisDecoderRead` chunks to
`SincOpen`/`SincProcess`.

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
`libopus` (xiph/opus v1.5.2), `libsamplerate` (libsndfile/libsamplerate
0.2.2), `dr_libs` (mackron/dr_libs, dr_mp3 0.7.5) and `stb` (nothings/stb,
stb_vorbis 1.24). An NDK CMake build includes `native/AudioCodecs.cmake` and
calls `ziran_audio_codecs("<libopus>" "<libsamplerate>")`,
`ziran_audio_mp3("<dr_libs>")` and `ziran_audio_vorbis("<stb>")` with the
paths from `ziran pkg path NAME`. They define static, position-independent
`opus`, `samplerate`, `ziran_mp3` and `ziran_vorbis` targets (float API; no
programs, tests or DNN extensions) to link into the app's native library.
`native/CMakeLists.txt` builds whichever of `OPUS_DIR`+`SAMPLERATE_DIR`,
`DR_LIBS_DIR` and `STB_DIR` it is given. Generate the
app's C with `--target-os android` and `--target-cpu` (`arm64`, `x64`, or
`none` for 32-bit ABIs) plus Breeze's Android defines, `--define
ANDROID_BUILD` and the ABI's `__aarch64__`, `__arm__`, `__i386__` or
`__x86_64__`. `std` file mapping and renames select bionic's calls from the
target OS; without it a 32-bit build calls `mmap` with a 64-bit offset and
every input fails to map.

`make android-test` (after `make test`) builds both libraries and the CLI with
NDK 28.2.13676358 at API 21 for arm64-v8a, armeabi-v7a, x86 and x86_64
(`ANDROID_NDK_HOME`, `ANDROID_API` and `ANDROID_ABIS` override this). With
`ANDROID_SERIAL=SERIAL` it runs inspect, decode, resample and encode on that
device and compares the output with the Linux CLI, including the nine MP3
and six Vorbis fixtures (inspect and decode) and an MP3 and a Vorbis stream
resampled to 48 kHz. On a Moto e6 play (armeabi-v7a, Android 9), decoded and
resampled PCM16 matched Linux exactly, MP3 and Vorbis included, and the
device-encoded stream decoded on Linux at the source duration. The other three ABIs are build-tested only. Native
consumers link `libziran_mp3.a` from `ziran_audio_mp3` and
`libziran_vorbis.a` from `ziran_audio_vorbis` with `-lm`.

## Windows

The same recipe builds static `libopus.a`, `libsamplerate.a`,
`libziran_mp3.a` and `libziran_vorbis.a` for x86_64 MinGW. With the pinned
sources from `ziran pkg path`:

```sh
cmake -S native -B build/windows/native -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_SYSTEM_PROCESSOR=AMD64 -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_BUILD_TYPE=Release \
    -DOPUS_DIR="$(ziran pkg path libopus)" -DSAMPLERATE_DIR="$(ziran pkg path libsamplerate)" \
    -DDR_LIBS_DIR="$(ziran pkg path dr_libs)" -DSTB_DIR="$(ziran pkg path stb)"
cmake --build build/windows/native
```

The archives are `build/windows/native/libopus/libopus.a`,
`build/windows/native/libsamplerate/src/libsamplerate.a`,
`build/windows/native/libziran_mp3.a` and
`build/windows/native/libziran_vorbis.a` (a CMake consumer calls
`ziran_audio_codecs`/`ziran_audio_mp3`/`ziran_audio_vorbis` and links the
`opus`/`ziran_mp3`/`ziran_vorbis` targets). Generate C with
`--define _WIN32 --define __x86_64__`; no other define is needed. libopus
keeps its default stack protector and `_FORTIFY_SOURCE=2`, so a MinGW link
adds GCC's `-lssp` after the archives: decoder-only consumers link
`libopus.a -lssp -lm` (plus `libziran_mp3.a` and `libziran_vorbis.a`
before it for MP3 and Vorbis),
full-pipeline consumers `libopus.a libsamplerate.a -lssp -lm`. With `-static -static-libgcc` the programs import only
`kernel32`, `msvcrt` and `advapi32`.

`make windows-test` (after `make test`; `WINDOWS_CC` names the compiler)
builds both archives and two codec programs, then runs them in a private
Wine prefix under a private Xvfb display and compares them with the Linux
CLI. The decoder-only program streams nine mono/stereo fixtures through
`DecoderOpen`/`DecoderRead` in 997-frame chunks, rewinds with
`DecoderRewind` and requires an identical second pass. It streams the nine
MP3 fixtures the same way through `Mp3DecoderRead`, also requires a
mid-stream `Mp3DecoderSeek` and a rewind to reproduce the first pass, and
rejects a truncated MP3; their inspection lines and PCM16 matched Linux
bit-exactly. The six Vorbis fixtures take the same path through
`VorbisDecoderRead` and `VorbisDecoderSeek`, and a truncated Vorbis file is
rejected; their inspection and comment lines and PCM16 matched Linux
bit-exactly too. Its Opus inspection
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
portable implementations; reachable native calls reject bundling instead
of fabricating output. Portable Ogg/WAV modules execute from source and saved
IR in C, Go and `.zx` without codec libraries. The CLI's variadic libopus
controls require the C target; Go CLI/native codec builds are not supported.

Run `make test` for source/saved-IR native codec+CLI tests, engine/Go
execution, FFI rejection, streaming parity, alias rejection, transients,
malformed data, atomic output and FFmpeg interoperability. Python and FFmpeg
are test tools only. Strict voice/chirp PCM comparison forces FFmpeg's
libopus decoder (within 1 PCM16 LSB). FFmpeg's independent decoder also checks
duration and the CELT sine fixtures; SILK/resampler implementations can differ
without a container timing error. No listening score or universal compression
quality claim follows from these tests.

MP3 tests (`tests/mp3_contracts.zi`, run by the native contracts) decode the
committed FFmpeg/libmp3lame fixtures in `tests/fixtures/mp3` (CBR, Xing VBR,
mono, 22.05 kHz MPEG-2, 11.025 kHz MPEG-2.5, no Xing header, Layer II and
ID3v2+ID3v1 tags; the README there lists the commands) against FFmpeg's own
PCM16 decode: at most 1.5 PCM16 steps and 0.5 steps RMS. Measured, Layer III
differs by at most 0.505 steps (the reference's own rounding) and Layer II by
1.04. Durations equal FFmpeg's exactly. Irregular streamed chunks, rewinds and
s16 reads equal the whole-file decode; seeks forward and back on an 8-second
32 kbps stream return bit-identical samples. One-byte and larger truncation,
garbage, silence, text, WAV, tags alone, free format, mid-stream tags and
mono/stereo changes are rejected, and 600 corrupted-payload decodes return a
status without crashing. `tests/portable.zi` checks inspection of synthetic
streams in the `.zx` engine and Go.

Vorbis tests (`tests/vorbis_contracts.zi`, run by the native contracts)
decode the committed FFmpeg/libvorbis fixtures in `tests/fixtures/vorbis`
(44.1 kHz stereo and mono, 22.05 kHz, 48 kHz, and a 32 kHz stream with
title, artist and UTF-8 comments; the README there lists the commands)
against FFmpeg's own PCM16 decode over the frames both hold: at most 1 PCM16
step and 0.35 steps RMS; measured, at most 0.501 steps (the reference's own
rounding) and 0.29 RMS. Lengths equal the final granule positions, which
ffprobe and libvorbisfile also report; FFmpeg's own decode ends up to a block
away from them. Irregular streamed chunks, rewinds and s16 reads equal the
whole-file decode, and seeks forward and back on an 8-second stream and two
short ones (into the end-trimmed tail too) return bit-identical samples.
Comments read back verbatim and by field name. Truncation, garbage, silence,
text, WAV, a CRC error, trailing bytes and synthetic streams with a timeline
offset, six channels, a 4 kHz rate, a granule past the decoded frames or no
audio are rejected; chained streams are `Unsupported`; an Ogg Opus stream is
not Vorbis and still inspects as Opus; and 600 decodes of fixtures with
corrupted setup-header or audio bytes behind refreshed CRCs return a status
without crashing. `tests/portable.zi` checks Vorbis inspection of a synthetic
stream in the `.zx` engine and Go. `make sanitize-test` runs the native
contracts with dr_mp3 and stb_vorbis (assertions on) and the generated C
under AddressSanitizer and UndefinedBehaviorSanitizer.

References: [Opus public API 1.5](https://www.opus-codec.org/docs/opus_api-1.5.pdf),
[RFC 7845 Ogg Opus](https://www.rfc-editor.org/rfc/rfc7845.html),
[libsamplerate state API](https://libsndfile.github.io/libsamplerate/api_full.html).
