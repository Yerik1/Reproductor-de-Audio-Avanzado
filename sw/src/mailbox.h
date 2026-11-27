#ifndef MAILBOX_H
#define MAILBOX_H

/* Buzon en memoria compartida entre el HPS (plano de datos) y el Nios V (plano de control).
 * Solo campos de 32 bits y texto: misma disposicion en ARM y RISC-V (little endian).
 *   Comandos  : cola circular, productor Nios V (cmd_head), consumidor HPS (cmd_tail).
 *   Estado    : escrito solo por el HPS con contador de secuencia (impar mientras escribe). */

#include <stdint.h>

#define MBX_MAGIC          0x4D425831u   /* "MBX1" */
#define MBX_CMD_SLOTS      16u
#define MBX_TEXT           64u
#define MBX_FLAG_FIXED_VOL (1u << 0)

enum {
    MBX_CMD_NONE       = 0,
    MBX_CMD_PLAY_PAUSE = 1,
    MBX_CMD_STOP       = 2,
    MBX_CMD_PREV       = 3,
    MBX_CMD_NEXT       = 4
};

enum {
    MBX_ST_STOPPED = 0,
    MBX_ST_PLAYING = 1,
    MBX_ST_PAUSED  = 2
};

typedef struct {
    uint32_t state;
    uint32_t track;          /* 0 .. total-1 */
    uint32_t total;
    uint32_t duration_ms;
    uint32_t sample_rate;
    uint32_t channels;
    char     title[MBX_TEXT];
    char     artist[MBX_TEXT];
    char     album[MBX_TEXT];
} mbx_status_t;

_Static_assert(sizeof(mbx_status_t) % 4 == 0, "mbx_status_t debe ocupar palabras completas");

typedef struct {
    uint32_t magic;
    uint32_t heartbeat;
    uint32_t flags;
    uint32_t cmd_head;
    uint32_t cmd_tail;
    uint32_t cmd[MBX_CMD_SLOTS];
    uint32_t seq;
    uint32_t status_words[sizeof(mbx_status_t) / 4];
} mailbox_t;

/* HPS */
void mbx_hps_init(volatile mailbox_t *m, uint32_t flags);
int  mbx_pop_cmd(volatile mailbox_t *m, uint32_t *cmd);
void mbx_publish(volatile mailbox_t *m, const mbx_status_t *s);

/* Nios V */
int  mbx_ready(const volatile mailbox_t *m);
int  mbx_push_cmd(volatile mailbox_t *m, uint32_t cmd);
int  mbx_read_status(const volatile mailbox_t *m, mbx_status_t *s, uint32_t *seq);

const char *mbx_state_name(uint32_t state);

#endif
