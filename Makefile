ZIRAN ?= ziran
CMAKE ?= cmake
.PHONY: all test sanitize-test android-test windows-test
# MP3 and Vorbis use the native recipes owned by the core modules.
ZIRAN_ROOT ?= $(shell $(ZIRAN) pkg path ziran --offline)
decoder_archives = mkdir -p $(1) && $(CMAKE) -S native -B $(1) -DZIRAN_STDLIB="$(ZIRAN_ROOT)/std" -DAUDIO_CORE_VORBIS=ON $(2) >$(1)/configure.log && $(CMAKE) --build $(1) --target ziran_mp3 vorbisfile >$(1)/build.log
LINUX_NATIVE := build/native/linux
SANITIZE := -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all

all:
	env -u DISPLAY -u WAYLAND_DISPLAY sh -c '$(call decoder_archives,$(LINUX_NATIVE),-DCMAKE_BUILD_TYPE=Release) && LDLIBS="-L$(LINUX_NATIVE) -lziran_mp3 -lvorbisfile -lvorbis -logg -lopus -lsamplerate -lm" $(ZIRAN) build --target=c --exe --root src --module-path src --entry audio:main -o build/bin src/audio.zi'

test:
	env -u DISPLAY -u WAYLAND_DISPLAY ZIRAN='$(ZIRAN)' sh -c '$(call decoder_archives,$(LINUX_NATIVE),-DCMAKE_BUILD_TYPE=Release) && sh tests/audio.sh'

# The native contracts (Opus, sinc and core MP3/Vorbis integration) with
# dr_mp3 and the generated C under AddressSanitizer and
# UndefinedBehaviorSanitizer; both decoders keep their assertions (Debug).
sanitize-test:
	env -u DISPLAY -u WAYLAND_DISPLAY sh -c '$(call decoder_archives,build/native/sanitize,-DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="$(SANITIZE)") && CFLAGS="$(SANITIZE)" LDFLAGS="-fsanitize=address,undefined" LDLIBS="-Lbuild/native/sanitize -lziran_mp3 -lvorbisfile -lvorbis -logg -lopus -lsamplerate -lm" $(ZIRAN) build --target=c --exe --root tests --module-path src --entry contracts:main -o build/tests/sanitize tests/contracts.zi && ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=print_stacktrace=1 build/tests/sanitize/contracts'

# Needs `make test` fixtures; ANDROID_SERIAL=SERIAL also runs them on a device.
android-test:
	env ZIRAN='$(ZIRAN)' sh tests/android.sh

# Needs `make test` fixtures; WINDOWS_CC names the x86_64 MinGW compiler.
windows-test:
	env ZIRAN='$(ZIRAN)' sh tests/windows.sh
