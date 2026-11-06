"""Independent file/codec interoperability and malformed Ogg rejection."""
import array
import hashlib
import math
import os
from pathlib import Path
import struct
import subprocess
import wave

root = Path(__file__).resolve().parents[1]
work = root / 'build/tests/fixtures'
work.mkdir(parents=True, exist_ok=True)
cli = root / 'build/bin/audio'

def run(*args, good=True):
    result = subprocess.run(list(map(str, args)), cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert (result.returncode == 0) == good, (args, result.returncode, result.stdout[-1000:], result.stderr[-1000:])
    return result

def wav(path, rate, channels, frames):
    with wave.open(str(path), 'wb') as output:
        output.setparams((channels, 2, rate, 0, 'NONE', 'not compressed'))
        samples = array.array('h', (int(12000 * math.sin(2 * math.pi * (440 + c * 513) * n / rate)) for n in range(frames) for c in range(channels)))
        if os.sys.byteorder != 'little': samples.byteswap()
        output.writeframes(samples.tobytes())

def frames(path):
    with wave.open(str(path), 'rb') as file: return file.getnframes(), file.getframerate(), file.getnchannels()

def crc(data):
    value = 0
    for i, byte in enumerate(data):
        value ^= (0 if 22 <= i < 26 else byte) << 24
        for _ in range(8): value = ((value << 1) ^ (0x04c11db7 if value & 0x80000000 else 0)) & 0xffffffff
    return value

def pages(data):
    at = 0
    while at < len(data):
        size = 27 + data[at + 26]
        size += sum(data[at + 27:at + size])
        yield at, at + size
        at += size

def damage(data, label, page, offset, replacement, checksum=True):
    copy = bytearray(data)
    start, end = list(pages(copy))[page]
    copy[start + offset:start + offset + len(replacement)] = replacement
    if checksum: struct.pack_into('<I', copy, start + 22, crc(copy[start:end]))
    path = work / (label + '.opus')
    path.write_bytes(copy)
    run(cli, 'inspect', path, good=False)
    sentinel = work / 'keep.wav'; sentinel.write_bytes(b'keep original output')
    run(cli, 'decode', path, sentinel, good=False)
    assert sentinel.read_bytes() == b'keep original output'

run(cli, '--help')
for channels in (1, 2):
    source = work / f'source-{channels}.wav'
    wav(source, 44100, channels, 44101)
    encoded = work / f'encoded-{channels}.opus'
    run(cli, 'encode', source, encoded, '--bitrate', '48000', '--vbr', 'constrained', '--bandwidth', 'wide')
    run(cli, 'inspect', encoded)
    decoded = work / f'decoded-{channels}.wav'
    run(cli, 'decode', encoded, decoded)
    expected = round(44101 * 48000 / 44100)
    assert abs(frames(decoded)[0] - expected) <= 1
    reference = work / f'reference-{channels}.wav'
    run('ffmpeg', '-v', 'error', '-y', '-i', encoded, '-acodec', 'pcm_s16le', reference)
    assert frames(reference) == frames(decoded)
    with wave.open(str(decoded), 'rb') as a, wave.open(str(reference), 'rb') as b:
        actual = array.array('h', a.readframes(a.getnframes())); oracle = array.array('h', b.readframes(b.getnframes()))
        # FFmpeg's independent native Opus decoder and libopus differ by a
        # few PCM16 LSBs due to floating-point kernels; duration must be exact.
        differences = [abs(x - y) for x, y in zip(actual, oracle)]
        assert max(differences) <= 8, max(differences)
        assert sum(x*x for x in differences) / len(differences) <= 4
    external = work / f'external-{channels}.opus'
    run('ffmpeg', '-v', 'error', '-y', '-i', source, '-c:a', 'libopus', '-b:a', '48000', '-vbr', 'on', external)
    run(cli, 'inspect', external)
    run(cli, 'decode', external, decoded)
    assert abs(frames(decoded)[0] - expected) <= 1
    run(cli, 'transcode', external, encoded, '--vbr', 'on', '--application', 'voice')
    run(cli, 'resample', source, decoded, '--rate', '16000')
    assert frames(decoded) == (16000, 16000, channels)
    for ms in (5, 10, 20, 40, 60):
        run(cli, 'encode', source, encoded, '--frame-ms', ms)
        run('ffmpeg', '-v', 'error', '-y', '-i', encoded, '-acodec', 'pcm_s16le', reference)
        assert abs(frames(reference)[0] - expected) <= 1

# A very short stream exercises pre-skip across packets and final trim.
short = work / 'short.wav'; wav(short, 48000, 1, 1)
short_opus = work / 'short.opus'
run(cli, 'encode', short, short_opus, '--frame-ms', '5')
run(cli, 'decode', short_opus, work / 'short-decoded.wav')
assert frames(work / 'short-decoded.wav')[0] == 1

# Page overhead must stay small at voice bitrates; packets aggregate to200ms.
voice = work / 'voice.wav'; wav(voice, 48000, 1, 48000 * 3)
encoded = work / 'voice.opus'
run(cli, 'encode', voice, encoded, '--bitrate', '16000', '--application', 'voice', '--bandwidth', 'wide')
data = encoded.read_bytes()
assert len(list(pages(data))) <= 18
print(f'measured synthetic3s voice: PCM {voice.stat().st_size} bytes, Ogg Opus {len(data)} bytes; {len(list(pages(data)))} pages')
damage(data, 'bad-crc', -1, 22, b'\0\0\0\0', False)
damage(data, 'bad-sequence', 1, 18, struct.pack('<I', 17))
damage(data, 'bad-continuation', 1, 5, b'\x01')
damage(data, 'bad-eos', -1, 5, b'\0')
# A one-sample stream cannot skip65535 samples.
short_data = short_opus.read_bytes()
damage(short_data, 'bad-preskip', 0, 28 + 10, b'\xff\xff')
# Force pre-skip beyond the final granule, independently of duration.
last_granule = struct.unpack_from('<Q', data, list(pages(data))[-1][0] + 6)[0]
damage(data, 'bad-granule', -1, 6, struct.pack('<Q', last_granule + 100000))
for label, payload in [('truncated', data[:-1]), ('trailing', data+b'x'), ('chained', data+data)]:
    path = work / (label+'.opus'); path.write_bytes(payload); run(cli, 'inspect', path, good=False)
# Headers and empty stream cannot trigger an unbounded decoded allocation.
for bad in ('--bitrate', '--frame-ms', '--complexity'):
    output = work / 'untouched'; output.write_bytes(b'previous')
    run(cli, 'encode', voice, output, bad, '999999999', good=False)
    assert output.read_bytes() == b'previous'
for bad in ('--bandwidth', '--vbr', '--application', '--unknown'):
    run(cli, 'encode', voice, work / 'unused', bad, 'nonsense', good=False)
original = voice.read_bytes()
run(cli, 'encode', voice, voice.parent / '.' / voice.name, good=False)
link = work / 'same-file.wav'
link.unlink(missing_ok=True); link.symlink_to(voice.name)
run(cli, 'encode', voice, link, good=False)
assert voice.read_bytes() == original
staged = work / 'blocked.opus.audio-part'; staged.write_bytes(b'owner file')
run(cli, 'encode', voice, work / 'blocked.opus', good=False)
assert staged.read_bytes() == b'owner file'
staged.unlink()
print('independent Opus interoperability, trim, options, atomic output and malformed streams passed')
# Voice/SILK exercises a different decoder path from the CELT sine fixtures.
# FFmpeg's default decoder may use a different SILK resampler; force libopus
# for a strict PCM oracle, while still checking the independent decoder duration.
chirp=work/'chirp.wav'
with wave.open(str(chirp),'wb') as output:
    output.setparams((1,2,44100,0,'NONE','not compressed'))
    output.writeframes(b''.join(struct.pack('<h',int(15000*math.sin(2*math.pi*(330*n/44100+350*(n/44100)**2)))) for n in range(44101)))
run(cli,'encode',chirp,work/'chirp.opus','--bitrate','24000','--application','voice','--bandwidth','wide','--vbr','on')
run(cli,'decode',work/'chirp.opus',work/'chirp-own.wav')
run('ffmpeg','-v','error','-y','-c:a','libopus','-i',work/'chirp.opus','-acodec','pcm_s16le',work/'chirp-oracle.wav')
assert frames(work/'chirp-own.wav') == frames(work/'chirp-oracle.wav')
with wave.open(str(work/'chirp-own.wav')) as a,wave.open(str(work/'chirp-oracle.wav')) as b:
    x=array.array('h',a.readframes(a.getnframes())); y=array.array('h',b.readframes(b.getnframes()))
    assert max(abs(i-j)for i,j in zip(x,y)) <= 1
run('ffmpeg','-v','error','-y','-i',work/'chirp.opus','-acodec','pcm_s16le',work/'chirp-independent.wav')
assert frames(work/'chirp-independent.wav') == frames(work/'chirp-own.wav')
print('voice/chirp strict libopus PCM oracle and independent decoder duration passed')
# Inspect actual packet bandwidth with the primary native Opus API; the user
# cap and constrained VBR remain independent controls.
import ctypes
opus=ctypes.CDLL('libopus.so.0')
opus.opus_packet_get_bandwidth.argtypes=[ctypes.c_void_p]
opus.opus_packet_get_bandwidth.restype=ctypes.c_int

def packets(data):
    pending=bytearray()
    for start,end in pages(data):
        count=data[start+26]; body=start+27+count
        for size in data[start+27:body]:
            pending.extend(data[body:body+size]); body+=size
            if size<255:
                yield bytes(pending); pending.clear()

for name,cap in [('narrow',1101),('wide',1103),('superwide',1104),('full',1105),('auto',1105)]:
    encoded=work/(name+'.opus')
    run(cli,'encode',chirp,encoded,'--bandwidth',name,'--bitrate','64000')
    audio_packets=list(packets(encoded.read_bytes()))[2:]
    assert audio_packets
    for packet in audio_packets:
        bandwidth=opus.opus_packet_get_bandwidth(ctypes.create_string_buffer(packet))
        assert 1101<=bandwidth<=cap,(name,bandwidth)
for mode in ('off','on','constrained'):
    encoded=work/('vbr-'+mode+'.opus')
    run(cli,'encode',chirp,encoded,'--bitrate','64000','--vbr',mode)
    sizes={len(packet)for packet in list(packets(encoded.read_bytes()))[2:]}
    assert sizes
    if mode=='off': assert sizes=={160},sizes
    else: assert len(sizes)>1,sizes
print('actual packet bandwidth caps and CBR/VBR/constrained VBR controls passed')
