"""Real manifest consumer, with canonical overrides and declarative native links."""
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
ziran = os.environ.get('ZIRAN', 'ziran')
env = dict(os.environ)
for key in ('LDLIBS', 'LDFLAGS', 'DISPLAY', 'WAYLAND_DISPLAY'):
    env.pop(key, None)

def run(*args, cwd=root):
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)

# Exercise the package's actual entry and native link metadata. Publish the
# completed project output at the same stable CLI path used by the other tests.
run(ziran, 'lock', '--offline')
run(ziran, 'build', '--offline')
(root/'build/bin').mkdir(parents=True, exist_ok=True)
(root/'build/audio').replace(root/'build/bin/audio')
run(root/'build/bin/audio', '--help')
toolchain = Path(subprocess.check_output([ziran, 'pkg', 'path', 'ziran'], cwd=root, env=env, text=True).strip())
consumer = root/'build/tests/consumer'
(consumer/'src').mkdir(parents=True, exist_ok=True)
(consumer/'ziran.toml').write_text('''[package]
name = "audio_consumer"
module_roots = ["src"]
entry = "src/main.zi"
links = ["opus", "samplerate", "m"]
[toolchain]
git = "https://github.com/ziranlang/ziran.git"
ref = "master"
[dependencies.audio]
git = "https://github.com/ziranlang/audio.git"
ref = "master"
''')
(consumer/'ziran.local.toml').write_text('[overrides]\nziran = '+json.dumps(str(toolchain))+'\naudio = '+json.dumps(str(root))+'\n')
shutil.copyfile(root/'tests/consumer.zi', consumer/'src/main.zi')
run(ziran, 'lock', '--offline', cwd=consumer)
run(ziran, 'build', '--offline', cwd=consumer)
run(consumer/'build/audio_consumer', cwd=consumer)
print('normal package entry, exports, local overrides and declarative native links passed', flush=True)
# A decode-only application must need no sample-rate library even when using
# normal project resolution and native link generation.
manifest=(consumer/'ziran.toml').read_text().replace('"opus", "samplerate", "m"','"opus", "m"')
(consumer/'ziran.toml').write_text(manifest)
shutil.copyfile(root/'tests/decoder_consumer.zi', consumer/'src/main.zi')
run(ziran, 'lock', '--offline', cwd=consumer)
run(ziran, 'build', '--offline', cwd=consumer)
run(consumer/'build/audio_consumer', consumer/'fixture.opus', cwd=consumer)
needed=subprocess.check_output(['readelf','-d',str(consumer/'build/audio_consumer')],text=True)
assert 'libsamplerate' not in needed
