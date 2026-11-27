#ifndef PLAYER_H
#define PLAYER_H

/* Maquina de estados del reproductor (PLAY-01) y alimentacion de audio_proc.
 *   Detenido  --PLAY_PAUSE--> Reproduciendo --PLAY_PAUSE--> Pausado --PLAY_PAUSE--> Reproduciendo
 *   STOP desde cualquier estado: Detenido en la misma pista, tiempo 00:00.
 *   NEXT/PREV circulares: si reproducia, la nueva pista suena; si no, queda Detenido en ella.
 *   Fin de pista: se espera a que la FIFO se vacie y se pasa a la siguiente; al terminar la
 *   ultima, Detenido en la primera. */

#include <stdint.h>
#include <stdio.h>

#include "catalog.h"
#include "mailbox.h"
#include "resampler.h"

#define PLAYER_CHUNK_FRAMES 1024u
#define PLAYER_BUF_WORDS    (PLAYER_CHUNK_FRAMES * 6u + 16u)

typedef struct {
    void     *ctx;
    uint32_t (*fifo_space)(void *ctx);
    int      (*fifo_idle)(void *ctx);
    void     (*write)(void *ctx, const uint32_t *words, uint32_t n);
    void     (*ctrl)(void *ctx, uint32_t value);
    void     (*track)(void *ctx, uint32_t number);
} audio_out_t;

typedef struct {
    const catalog_t   *cat;
    const audio_out_t *out;
    uint32_t           state;
    uint32_t           track;
    uint32_t           changes;
    FILE              *f;
    uint32_t           remaining;
    int                draining;
    resampler_t        rs;
    uint32_t           buf_len;
    uint32_t           buf_pos;
    int16_t            in[PLAYER_CHUNK_FRAMES * 2u];
    uint32_t           buf[PLAYER_BUF_WORDS];
} player_t;

void player_init(player_t *p, const catalog_t *cat, const audio_out_t *out);
void player_command(player_t *p, uint32_t cmd);
void player_poll(player_t *p);
void player_status(const player_t *p, mbx_status_t *s);
void player_close(player_t *p);

#endif
