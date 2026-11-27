#include "resampler.h"

void rs_init(resampler_t *r, uint32_t rate_in, uint32_t rate_out, uint16_t channels)
{
    r->step     = ((uint64_t)rate_in << 32) / rate_out;
    r->pos      = 2 * RS_ONE;
    r->s0l      = r->s0r = r->s1l = r->s1r = 0;
    r->channels = channels;
}

static int16_t lerp(int16_t a, int16_t b, uint32_t w)
{
    return (int16_t)(a + (int32_t)(((int64_t)(b - a) * w) >> 16));
}

size_t rs_process(resampler_t *r, const int16_t *in, size_t in_frames, size_t *in_used,
                  uint32_t *out, size_t out_max)
{
    size_t i = 0, o = 0;

    while (o < out_max) {
        uint32_t w;

        while (r->pos >= RS_ONE && i < in_frames) {
            r->s0l = r->s1l;
            r->s0r = r->s1r;
            if (r->channels == 2) {
                r->s1l = in[2 * i];
                r->s1r = in[2 * i + 1];
            } else {
                r->s1l = r->s1r = in[i];
            }
            i++;
            r->pos -= RS_ONE;
        }
        if (r->pos >= RS_ONE)
            break;
        w = (uint32_t)(r->pos >> 16);
        out[o++] = rs_pack(lerp(r->s0l, r->s1l, w), lerp(r->s0r, r->s1r, w));
        r->pos += r->step;
    }
    *in_used = i;
    return o;
}
