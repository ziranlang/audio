# MP3 test fixtures

Generated on 2026-11-15 with FFmpeg 7.1.5 (Debian 7.1.5-0+deb13u1): its
libmp3lame encoder for Layer III and its native `mp2` encoder for Layer II.
Each `NAME.wav` is FFmpeg's own decode of `NAME.mp3`/`NAME.mp2` (PCM16,
LAME gapless trims applied), the independent reference that
`tests/mp3_contracts.zi` compares against. `long.mp3` has no reference:
its seeks are checked against this package's own linear decode.

FFmpeg's MP3 muxer writes an ID3v2.4 header (empty unless metadata is set)
before every `.mp3`. The 0.3 s source is a 440 Hz left / 660 Hz right tone plus seeded noise:

```sh
SRC='sine=f=440:d=0.3:sample_rate=44100[a];sine=f=660:d=0.3:sample_rate=44100[b];anoisesrc=d=0.3:a=0.05:r=44100:seed=7[n];[a][b]amerge=inputs=2[s];[s][n]amix=inputs=2:normalize=0,volume=0.8'
ff() { ffmpeg -hide_banner -loglevel error -y -bitexact "$@"; }
ff -filter_complex "$SRC" -ac 2 -ar 44100 -c:a libmp3lame -b:a 128k cbr.mp3
ff -filter_complex "$SRC" -ac 2 -ar 44100 -c:a libmp3lame -q:a 2 vbr.mp3
ff -filter_complex "$SRC" -ac 1 -ar 32000 -c:a libmp3lame -b:a 64k mono.mp3
ff -filter_complex "$SRC" -ac 2 -ar 22050 -c:a libmp3lame -b:a 64k mpeg2.mp3
ff -filter_complex "$SRC" -ac 1 -ar 11025 -c:a libmp3lame -b:a 16k mpeg25.mp3
ff -filter_complex "$SRC" -ac 2 -ar 44100 -c:a libmp3lame -b:a 128k -write_xing 0 noxing.mp3
ff -filter_complex "$SRC" -ac 2 -ar 48000 -c:a mp2 -b:a 192k layer2.mp2
ff -filter_complex "$SRC" -ac 1 -ar 44100 -c:a libmp3lame -b:a 96k -id3v2_version 3 -write_id3v1 1 \
    -metadata title="Ziran fixture" -metadata artist="Ziran audio" -metadata comment="ID3v2 and ID3v1 tags" id3.mp3
for f in *.mp3 *.mp2; do ff -i "$f" -map_metadata -1 -c:a pcm_s16le "${f%.*}.wav"; done
ff -f lavfi -i "sine=f=330:d=8:sample_rate=22050,volume=0.5" -f lavfi -i "anoisesrc=d=8:a=0.08:r=22050:seed=3" \
    -filter_complex amix=inputs=2:normalize=0 -ac 1 -ar 22050 -c:a libmp3lame -b:a 32k long.mp3
```

| File | Stream | Header | Frames |
| --- | --- | --- | --- |
| `cbr.mp3` | MPEG-1 Layer III, 44.1 kHz stereo, 128 kbps CBR | ID3v2.4, Info + LAME | 13230 |
| `vbr.mp3` | MPEG-1 Layer III, 44.1 kHz stereo, VBR `-q:a 2` | ID3v2.4, Xing + LAME | 13230 |
| `mono.mp3` | MPEG-1 Layer III, 32 kHz mono, 64 kbps | ID3v2.4, Info + LAME | 9600 |
| `mpeg2.mp3` | MPEG-2 Layer III, 22.05 kHz stereo, 64 kbps | ID3v2.4, Info + LAME | 6615 |
| `mpeg25.mp3` | MPEG-2.5 Layer III, 11.025 kHz mono, 16 kbps | ID3v2.4, Info + LAME (32 kbps tag frame) | 3308 |
| `noxing.mp3` | MPEG-1 Layer III, 44.1 kHz stereo, 128 kbps | ID3v2.4 only | 14976 |
| `layer2.mp2` | MPEG-1 Layer II, 48 kHz stereo, 192 kbps | none | 14976 |
| `id3.mp3` | MPEG-1 Layer III, 44.1 kHz mono, 96 kbps | ID3v2.3, Info + LAME, ID3v1 | 13230 |
| `long.mp3` | MPEG-2 Layer III, 22.05 kHz mono, 32 kbps, 8 s | ID3v2.4, Info + LAME | 176400 |
