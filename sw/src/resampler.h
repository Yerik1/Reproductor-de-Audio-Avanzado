#ifndef RESAMPLER_H
#define RESAMPLER_H

#include <stddef.h>
#include <stdint.h>

/* Conversion de frecuencia por interpolacion lineal (posicion en Q32.32) hacia la
 * frecuencia fija del codec. Entrada PCM 16 bits mono o estereo intercalado; salida
 * estereo empaquetada en el formato del registro DATA de audio_proc. */

#define RS_ONE ((uint64_t)1 << 32)

typedef struct {
    uint64_t step;
    uint64_t pos;
    int16_t  s0l, s0r, s1l, s1r;
    uint16_t channels;
} resampler_t;

static inline uint32_t rs_pack(int16_t l, int16_t r)
{
    return ((uint32_t)(uint16_t)l << 16) | (uint16_t)r;
}

void rs_init(resampler_t *r, uint32_t rate_in, uint32_t rate_out, uint16_t channels);

/* Consume hasta in_frames cuadros y produce hasta out_max palabras. El estado se
 * conserva entre llamadas para procesar el archivo por bloques. */
size_t rs_process(resampler_t *r, const int16_t *in, size_t in_frames, size_t *in_used,
                  uint32_t *out, size_t out_max);

#endif
