"""Compare the Android device CLI results with the Linux CLI on the same inputs."""
from pathlib import Path
import subprocess
import struct
import sys
import wave

host, abi, serial = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
linux = host / 'linux'
# Float codec/sinc arithmetic may round differently across ISAs (NEON/SSE,
# fused multiply-add); PCM16 output must still agree within a few LSBs.
TOLERANCE = 4

def pcm(path):
    with wave.open(str(path)) as audio:
        params = (audio.getframerate(), audio.getnchannels(), audio.getnframes())
        data = audio.readframes(audio.getnframes())
    return params, struct.unpack('<%dh' % (len(data) // 2), data)

def inspect_lines(log):
    return [line for line in log.read_text().splitlines() if line.strip()]

device_inspect = inspect_lines(host / 'device.log')
linux_inspect = inspect_lines(host / 'linux.log')
assert device_inspect == linux_inspect, (device_inspect, linux_inspect)

for name in ('short.wav', 'voice-decoded.wav', 'chirp-decoded.wav', 'voice-16k.wav', 'chirp-44k.wav'):
    (device_params, device), (linux_params, reference) = pcm(host / name), pcm(linux / name)
    assert device_params == linux_params, (name, device_params, linux_params)
    worst = max((abs(a - b) for a, b in zip(device, reference)), default=0)
    assert worst <= TOLERANCE, (name, worst)
    print(f'android {abi} {name}: {device_params[2]} frames at {device_params[0]} Hz, max PCM16 difference {worst}')

# The device-encoded stream must decode on Linux with the source duration.
decoded = host / 'device-encoded-decoded.wav'
subprocess.run([str(Path('build/bin/audio').resolve()), 'decode', str(host / 'voice-encoded.opus'), str(decoded)], check=True)
(rate, channels, frames), _ = pcm(decoded)
(_, _, source_frames), _ = pcm(linux / 'voice.wav')
assert (rate, channels, frames) == (48000, 1, source_frames), (rate, channels, frames, source_frames)
print(f'android {abi} encode: {(host / "voice-encoded.opus").stat().st_size} bytes, decoded on Linux to {frames} frames')
print(f'android {abi} device {serial}: native Opus decode/encode and best sinc resampling matched Linux')
