#ifndef WAV_H
#define WAV_H

#include <stdint.h>
#include <stdio.h>

#define WAV_TEXT_MAX  64
#define WAV_MIN_RATE  8000u
#define WAV_MAX_RATE  48000u

typedef struct {
    uint16_t channels;
    uint32_t sample_rate;
    uint16_t bits_per_sample;
    uint16_t block_align;
    uint32_t data_offset;   /* byte del archivo donde inicia el PCM */
    uint32_t data_size;     /* bytes de PCM */
    uint32_t frames;        /* cuadros (una muestra por canal) */
    uint32_t duration_ms;
    char     title[WAV_TEXT_MAX];
    char     artist[WAV_TEXT_MAX];
    char     album[WAV_TEXT_MAX];
} wav_info_t;

enum {
    WAV_OK              =  0,
    WAV_ERR_IO          = -1,
    WAV_ERR_NOT_WAVE    = -2,
    WAV_ERR_FORMAT      = -3,
    WAV_ERR_UNSUPPORTED = -4,
    WAV_ERR_NO_DATA     = -5
};

/* Recorre los chunks RIFF: valida fmt (PCM 16 bits, 1 o 2 canales, 8-48 kHz),
 * ubica data y extrae LIST/INFO (INAM, IART, IPRD). Campos ausentes quedan vacios. */
int wav_parse(FILE *f, wav_info_t *info);
int wav_probe(const char *path, wav_info_t *info);
const char *wav_strerror(int code);

#endif
