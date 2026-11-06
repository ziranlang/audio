ZIRAN ?= ziran
.PHONY: all test android-test windows-test
all:
	build-queue -- env -u DISPLAY -u WAYLAND_DISPLAY LDLIBS='-lopus -lsamplerate -lm' $(ZIRAN) build --target=c --exe --root src --module-path src --entry audio:main -o build/bin src/audio.zi

test:
	build-queue -- env -u DISPLAY -u WAYLAND_DISPLAY ZIRAN='$(ZIRAN)' sh tests/audio.sh

# Needs `make test` fixtures; ANDROID_SERIAL=SERIAL also runs them on a device.
android-test:
	build-queue -- env ZIRAN='$(ZIRAN)' sh tests/android.sh

# Needs `make test` fixtures; WINDOWS_CC names the x86_64 MinGW compiler.
windows-test:
	build-queue -- env ZIRAN='$(ZIRAN)' sh tests/windows.sh
