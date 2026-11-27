#include "mailbox.h"

#include <string.h>

#define STATUS_WORDS (sizeof(mbx_status_t) / 4)

void mbx_hps_init(volatile mailbox_t *m, uint32_t flags)
{
    uint32_t i;

    m->magic     = 0;
    m->flags     = flags;
    m->cmd_tail  = m->cmd_head;
    m->heartbeat = 0;
    m->seq       = 0;
    for (i = 0; i < STATUS_WORDS; i++)
        m->status_words[i] = 0;
    m->magic = MBX_MAGIC;
}

int mbx_pop_cmd(volatile mailbox_t *m, uint32_t *cmd)
{
    uint32_t tail = m->cmd_tail;

    if (tail == m->cmd_head)
        return 0;
    *cmd = m->cmd[tail % MBX_CMD_SLOTS];
    m->cmd_tail = tail + 1;
    return 1;
}

void mbx_publish(volatile mailbox_t *m, const mbx_status_t *s)
{
    uint32_t w[STATUS_WORDS];
    uint32_t i;

    memcpy(w, s, sizeof(w));
    m->seq = m->seq + 1;
    for (i = 0; i < STATUS_WORDS; i++)
        m->status_words[i] = w[i];
    m->seq = m->seq + 1;
}

int mbx_ready(const volatile mailbox_t *m)
{
    return m->magic == MBX_MAGIC;
}

int mbx_push_cmd(volatile mailbox_t *m, uint32_t cmd)
{
    uint32_t head = m->cmd_head;

    if (head - m->cmd_tail >= MBX_CMD_SLOTS)
        return 0;
    m->cmd[head % MBX_CMD_SLOTS] = cmd;
    m->cmd_head = head + 1;
    return 1;
}

int mbx_read_status(const volatile mailbox_t *m, mbx_status_t *s, uint32_t *seq)
{
    uint32_t w[STATUS_WORDS];
    uint32_t s1, s2, i;

    s1 = m->seq;
    if (s1 & 1u)
        return 0;
    for (i = 0; i < STATUS_WORDS; i++)
        w[i] = m->status_words[i];
    s2 = m->seq;
    if (s1 != s2)
        return 0;
    memcpy(s, w, sizeof(w));
    s->title[MBX_TEXT - 1] = s->artist[MBX_TEXT - 1] = s->album[MBX_TEXT - 1] = '\0';
    *seq = s1;
    return 1;
}

const char *mbx_state_name(uint32_t state)
{
    switch (state) {
    case MBX_ST_PLAYING: return "Reproduciendo";
    case MBX_ST_PAUSED:  return "Pausado";
    default:             return "Detenido";
    }
}
