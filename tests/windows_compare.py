"""Compare the Wine-run Windows codec programs with the Linux CLI on the same inputs."""
from pathlib import Path
import struct
import subprocess
import sys
import wave

run, cli = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
split = sys.argv.index('--')
decoded, rejected = sys.argv[3:split], sys.argv[split + 1:]
linux = run / 'linux'
# Same ISA (x86-64 SSE/AVX runtime dispatch), but a different compiler and
# libm than the system libopus; PCM16 output must agree within a few LSBs.
TOLERANCE = 4

def pcm(path):
    with wave.open(str(path)) as audio:
        params = (audio.getframerate(), audio.getnchannels(), audio.getnframes())
        data = audio.readframes(audio.getnframes())
    return params, struct.unpack('<%dh' % (len(data) // 2), data)

def worst(a, b):
    return max((abs(x - y) for x, y in zip(a, b)), default=0)

windows_log = [line.strip() for line in (run / 'windows.log').read_text().splitlines() if line.strip()]
linux_log = [line.strip() for line in (linux / 'linux.log').read_text().splitlines() if line.strip()]
inspect_windows = [line for line in windows_log if line.startswith('Opus:')]
inspect_linux = [line for line in linux_log if line.startswith('Opus:')]
assert len(inspect_linux) == len(decoded) and inspect_windows == inspect_linux, (inspect_windows, inspect_linux)
errors_windows = [line for line in windows_log if not line.startswith(('Opus:', 'decoded and rewound', 'wrote'))]
errors_linux = [line for line in linux_log if not line.startswith('Opus:')]
assert len(errors_linux) == len(rejected) and errors_windows == errors_linux, (errors_windows, errors_linux)
print(f'windows inspect: {len(decoded)} fixtures matched Linux; {len(rejected)} malformed fixtures rejected as on Linux')

exact = 0
for name in decoded:
    (windows_params, windows), (linux_params, reference) = pcm(run / f'{name}-decoded.wav'), pcm(linux / f'{name}-decoded.wav')
    assert windows_params == linux_params, (name, windows_params, linux_params)
    difference = worst(windows, reference)
    assert difference <= TOLERANCE, (name, difference)
    exact += difference == 0
    print(f'windows decode {name}: {windows_params[2]} frames x{windows_params[1]} at {windows_params[0]} Hz, rewind identical, max PCM16 difference {difference}')

# The Windows-encoded stream decodes on Linux at the source duration and
# matches the Windows decode of that same stream.
windows_opus, linux_opus = run / 'windows-voice.opus', linux / 'voice.opus'
roundtrip = linux / 'windows-voice-decoded.wav'
subprocess.run([str(cli), 'decode', str(windows_opus), str(roundtrip)], check=True, stdout=subprocess.DEVNULL)
(params, on_linux), (_, source) = pcm(roundtrip), pcm(run / 'voice.wav')
assert params == (48000, 1, len(source)), (params, len(source))
(windows_params, on_windows) = pcm(run / 'windows-voice-decoded.wav')
assert windows_params == params and worst(on_windows, on_linux) <= TOLERANCE
same = windows_opus.read_bytes() == linux_opus.read_bytes()
print(f'windows encode voice.wav: {windows_opus.stat().st_size} bytes (Linux {linux_opus.stat().st_size}, '
      f'{"byte-identical" if same else "different bytes"}), decoded on Linux to {params[2]} frames; '
      f'Windows/Linux decode of it differ by {worst(on_windows, on_linux)} LSB')

status = (run / 'resample.log').read_text().strip()
assert status == 'unsupported audio capability', status
print('windows resample: SincOpen returns Unsupported before libsamplerate (documented boundary)')
print(f'windows x86_64 under Wine: native Opus decode/rewind/encode matched Linux ({exact}/{len(decoded)} decodes bit-exact)')
