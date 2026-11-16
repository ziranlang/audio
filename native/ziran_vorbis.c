/* The one translation unit for stb_vorbis (nothings/stb, public domain or
 * MIT; see LICENSE in the pinned `stb` source dependency), built for
 * whole-stream memory input only: no stdio, no pushdata API, no integer
 * conversion and no comment parsing, which audio/ogg_vorbis does itself.
 * audio/vorbis validates the Ogg container (CRC, one serial, page order,
 * headers and granules) before stb_vorbis sees the bytes, because
 * stb_vorbis checks neither CRCs nor serial numbers.
 *
 * The read call is the one piece written against stb_vorbis internals:
 * stb_vorbis_get_samples_float_interleaved stops at the first frame that
 * yields no samples, which a long first block followed by short blocks
 * produces mid-stream, so it would end early. ziran_vorbis_read keeps
 * decoding until stb_vorbis reports the end of the stream or an error. */
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#define STB_VORBIS_NO_INTEGER_CONVERSION
#define STB_VORBIS_NO_COMMENTS
#include "stb_vorbis.c"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>

/* Opens stb_vorbis over borrowed, validated Ogg Vorbis bytes and reports its
 * rate and channel count for the caller to compare with its own inspection.
 * Returns NULL when stb_vorbis rejects the stream or allocation fails. */
void *ziran_vorbis_open(const void *data, size_t size, int32_t *rate, int32_t *channels) {
    stb_vorbis *f;
    int error = 0;
    if (data == NULL || size == 0 || size > INT_MAX || rate == NULL || channels == NULL) return NULL;
    f = stb_vorbis_open_memory((const unsigned char *)data, (int)size, &error, NULL);
    if (f == NULL) return NULL;
    *rate = (int32_t)f->sample_rate;
    *channels = (int32_t)f->channels;
    return f;
}

void ziran_vorbis_close(void *handle) {
    if (handle != NULL) stb_vorbis_close((stb_vorbis *)handle);
}

/* Decodes the next packet into the channel buffers. Zero-sample frames are
 * frames; only the end of the stream or a decode error returns 0. */
static int ziran_vorbis_frame(stb_vorbis *f) {
    int len, left, right;
    if (!vorbis_decode_packet(f, &len, &left, &right)) {
        f->channel_buffer_start = f->channel_buffer_end = 0;
        return 0;
    }
    len = vorbis_finish_frame(f, len, left, right);
    f->channel_buffer_start = left;
    f->channel_buffer_end = left + len;
    return 1;
}

/* Fills OUTPUT with up to FRAMES interleaved float frames and returns how
 * many it wrote; fewer only at the end of the stream or on a decode error.
 * Every decoded packet consumes input, so the loop ends. */
int64_t ziran_vorbis_read(void *handle, float *output, int64_t frames) {
    stb_vorbis *f = (stb_vorbis *)handle;
    int64_t done = 0;
    int channels, i, j;
    if (f == NULL || output == NULL || frames <= 0) return 0;
    channels = f->channels;
    while (done < frames) {
        int64_t available = f->channel_buffer_end - f->channel_buffer_start;
        int count = available > frames - done ? (int)(frames - done) : (int)available;
        for (j = 0; j < count; ++j)
            for (i = 0; i < channels; ++i)
                *output++ = f->channel_buffers[i][f->channel_buffer_start + j];
        f->channel_buffer_start += count;
        done += count;
        if (done == frames || !ziran_vorbis_frame(f)) break;
    }
    f->current_playback_loc += done;
    return done;
}

/* Sample-exact seek: the next read starts at FRAME (0 rewinds). Returns 1 on
 * success. */
int32_t ziran_vorbis_seek(void *handle, int64_t frame) {
    stb_vorbis *f = (stb_vorbis *)handle;
    if (f == NULL || frame < 0) return 0;
    if (frame == 0) return stb_vorbis_seek_start(f) ? 1 : 0;
    return stb_vorbis_seek64(f, frame) ? 1 : 0;
}
