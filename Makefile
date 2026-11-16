ZIRAN ?= ziran
CMAKE ?= cmake
.PHONY: all test sanitize-test android-test windows-test
# libziran_mp3.a (dr_mp3 from the pinned dr_libs source) and
# libziran_vorbis.a (stb_vorbis from the pinned stb source) into DIR:
# $(call decoder_archives,DIR,CMAKE-ARGUMENTS)
decoder_archives = mkdir -p $(1) && $(CMAKE) -S native -B $(1) -DDR_LIBS_DIR="$$($(ZIRAN) pkg path dr_libs --offline)" -DSTB_DIR="$$($(ZIRAN) pkg path stb --offline)" $(2) >$(1)/configure.log && $(CMAKE) --build $(1) --target ziran_mp3 ziran_vorbis >$(1)/build.log
LINUX_NATIVE := build/native/linux
SANITIZE := -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all

all:
	build-queue -- env -u DISPLAY -u WAYLAND_DISPLAY sh -c '$(call decoder_archives,$(LINUX_NATIVE),-DCMAKE_BUILD_TYPE=Release) && LDLIBS="-L$(LINUX_NATIVE) -lziran_mp3 -lziran_vorbis -lopus -lsamplerate -lm" $(ZIRAN) build --target=c --exe --root src --module-path src --entry audio:main -o build/bin src/audio.zi'

test:
	build-queue -- env -u DISPLAY -u WAYLAND_DISPLAY ZIRAN='$(ZIRAN)' sh -c '$(call decoder_archives,$(LINUX_NATIVE),-DCMAKE_BUILD_TYPE=Release) && sh tests/audio.sh'

# The native contracts (Opus, sinc and every MP3 and Vorbis contract) with
# dr_mp3, stb_vorbis and the generated C under AddressSanitizer and
# UndefinedBehaviorSanitizer; both decoders keep their assertions (Debug).
sanitize-test:
	build-queue -- env -u DISPLAY -u WAYLAND_DISPLAY sh -c '$(call decoder_archives,build/native/sanitize,-DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="$(SANITIZE)") && CFLAGS="$(SANITIZE)" LDFLAGS="-fsanitize=address,undefined" LDLIBS="-Lbuild/native/sanitize -lziran_mp3 -lziran_vorbis -lopus -lsamplerate -lm" $(ZIRAN) build --target=c --exe --root tests --module-path src --entry contracts:main -o build/tests/sanitize tests/contracts.zi && ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=print_stacktrace=1 build/tests/sanitize/contracts'

# Needs `make test` fixtures; ANDROID_SERIAL=SERIAL also runs them on a device.
android-test:
	build-queue -- env ZIRAN='$(ZIRAN)' sh tests/android.sh

# Needs `make test` fixtures; WINDOWS_CC names the x86_64 MinGW compiler.
windows-test:
	build-queue -- env ZIRAN='$(ZIRAN)' sh tests/windows.sh
