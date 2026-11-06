#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ZIRAN=${ZIRAN:-ziran}
export LDLIBS='-lopus -lsamplerate -lm'
mkdir -p build/tests
python3 - <<'PYDOC'
from pathlib import Path
text=Path('README.md').read_text()
Path('build/tests/readme.zi').write_text(text.split('```zi\n',1)[1].split('```',1)[0])
PYDOC
"$ZIRAN" check --root build/tests --module-path audio=src build/tests/readme.zi
"$ZIRAN" ir --root tests --module-path src -o build/tests/ir tests/contracts.zi
for form in source saved; do
    root=tests; file=tests/contracts.zi
    if test "$form" = saved; then root=build/tests/ir; file=build/tests/ir/contracts.zir; fi
    "$ZIRAN" build --target=c --exe --root "$root" --module-path src --entry contracts:main -o build/tests/native "$file"
    build/tests/native/contracts
 done
"$ZIRAN" ir --root src --module-path src -o build/tests/cli-ir src/audio.zi
for form in source saved; do
    root=src; file=src/audio.zi
    if test "$form" = saved; then root=build/tests/cli-ir; file=build/tests/cli-ir/audio.zir; fi
    "$ZIRAN" build --target=c --exe --root "$root" --module-path src --entry audio:main -o build/bin "$file"
    python3 tests/interoperability.py
done
"$ZIRAN" ir --root tests --module-path src -o build/tests/portable-ir tests/portable.zi
for form in source saved; do
    root=tests; file=tests/portable.zi
    if test "$form" = saved; then root=build/tests/portable-ir; file=build/tests/portable-ir/portable.zir; fi
    "$ZIRAN" bundle --root "$root" --module-path src --entry portable:main -o build/tests/portable.zx "$file"
    "$ZIRAN" run build/tests/portable.zx
    "$ZIRAN" build --target=go --pkg main --exe --root "$root" --module-path src --entry portable:main -o build/tests/go "$file"
    GO111MODULE=off go build -o build/tests/go/program ./build/tests/go
    build/tests/go/program
 done
# Target rejection, rather than silently fabricated codec/resampler output.
for entry in Codec Sinc; do
    if "$ZIRAN" bundle --root tests --module-path src --entry "native_only:$entry" -o build/tests/native.zx tests/native_only.zi >build/tests/rejection.log 2>&1; then
        echo "native $entry unexpectedly bundled without its capability" >&2; exit 1
    fi
    rg 'foreign|capability|native|unsupported' build/tests/rejection.log >/dev/null
done
ZIRAN="$ZIRAN" python3 tests/package.py
printf '%s\n' 'audio source/saved native, portable VM/Go and independent interoperability local tests passed'
