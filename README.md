# Audio for Ziran

Optional Opus encoding/decoding and best-quality sinc conversion for Ziran,
with an `audio` command that also uses the core WAV, MP3 and Vorbis modules.
The mixer, PCM streams, SDL/Android/WebAudio sinks and general decoders live in
Ziran's standard library and work without Kryon. Import `audio/decode_opus`
to register optional Opus decoding with `std/audio`; link libopus.

## Build and use

Install Ziran, CMake and the development/link libraries for **libopus**,
**libsamplerate** (`libopus-dev` and `libsamplerate0-dev` on Debian-family
Linux). `make` builds MP3 and the SHA256-pinned Xiph Vorbis archives with
Ziran's `std/native/AudioCodecs.cmake` recipes before the CLI.
Then run:

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
lossy re-encode unless its source is WAV. Vorbis inspection and decoding use `std/vorbis` and `std/vorbis_linux`.

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
PCM16 WAV and the core PCM16 sink explicitly clip to [-1,32767/32768] at the
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

Exports are `audio/types` (Opus settings/metadata), `audio/ogg_opus`,
`audio/opus`, `audio/decode_opus`, `audio/resample`, `audio/pipeline`,
`audio/mp3_resample` and `audio/vorbis_resample`. Shared PCM/status helpers,
WAV, MPEG/MP3 and Ogg/Vorbis APIs are imported directly from `std`.
Full CLI consumers link `ziran_mp3`, `vorbisfile`, `vorbis`, `ogg`, `opus`,
`samplerate` and `m`; use the core MP3 archive directory in `LDFLAGS`.
Opus decoder-only consumers need only `opus` and `m`; the package does not
make std depend on Opus or quality resampling. Sinc adapters add `samplerate`.
Ziran does not inherit system links from dependencies.

```zi
Types :: #import "std/audio_types"
OpusTypes :: #import "audio/types"
Pipeline :: #import "audio/pipeline"
#import "std/vec"

EncodeAudio :: (pcm: *Types.PCM, output: *Vec(u8)) -> s32 {
    options := OpusTypes.DefaultOptions()
    options.bitrate = 64000
    options.bandwidth = OpusTypes.Bandwidth.Full
    return Pipeline.Encode(pcm, options, output)
}
```

`PCM` owns interleaved `Vec(float32)` samples plus `rate:s32` and
`channels:s32`. Pass it by pointer. Ordinary vector cleanup releases sample
storage. `SwapSamples(*PCM,*Vec(float32))` transfers sample ownership without
copying. Whole-buffer convenience calls leave their output unchanged on an
error and return a status from `std/audio_types` (`ErrorText` gives a short message):

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

## Core decoders and optional resampling

`std/audio_mp3` provides incremental MP3 read/seek and bounded whole-file
float/PCM16 output. `std/audio_mpeg` performs portable MPEG inspection.
Build `ziran_audio_mp3()` from Ziran's `std/native/AudioCodecs.cmake` and
ship its pinned dr_mp3 license. The optional `audio/mp3_resample` combines
that decoder with `audio/resample`'s best sinc converter.

`std/vorbis` validates CRCs, page ordering, headers and exact packet timelines,
and exposes bitrate/block metadata, vendor and user comments.
`std/vorbis_linux` uses guarded libvorbisfile for whole-file and incremental
float/PCM16 decoding, exact seeking and file ownership. Link `vorbisfile`,
`vorbis` and `ogg`; cross builds use the core `ziran_audio_vorbis()` recipe.
`audio/vorbis_resample` adds best-quality sinc conversion. Both adapters leave
output unchanged on error and return `std/audio_types` status codes.

The package contains no duplicate WAV, MPEG, MP3, Ogg-container or Vorbis
implementation. See [the core audio guide](https://ziran-lang.org/guide/usage)
and the standard modules' API references for their complete contracts.

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

## Native platform tests

`native/AudioCodecs.cmake` builds the package's pinned optional Opus/sinc
sources through `ziran_audio_codecs(opus_dir, samplerate_dir)`. MP3 and
Vorbis sources/recipes are owned by Ziran; cross-build CMake passes
`-DZIRAN_STDLIB="$(ziran pkg path ziran)/std"` to reuse them.

Run `make test` for source/saved native contracts, portable ZX/Go inspection,
CLI interoperability and real manifest consumers, including optional Opus
mixer registration without a resampler dependency. `make sanitize-test`
runs native contracts under ASan/UBSan. After `make test`,
`ANDROID_SERIAL=ZE2223BQZT make android-test` builds Android ABIs and compares
actual Moto output with Linux; `make windows-test` cross-links MinGW programs
and runs them under Wine on a private display. These are local tests, not
proof of native Windows hardware execution or an app installation.
