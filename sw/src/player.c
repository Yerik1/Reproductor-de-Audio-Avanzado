#include "player.h"

#include <string.h>

#include "audio_proc_regs.h"

#define CTRL_IDLE  (AP_CTRL_HEX_EN)
#define CTRL_RUN   (AP_CTRL_HEX_EN | AP_CTRL_RUN)
#define CTRL_RESET (AP_CTRL_HEX_EN | AP_CTRL_FLUSH | AP_CTRL_TIME_CLR)

static void close_file(player_t *p)
{
    if (p->f) {
        fclose(p->f);
        p->f = NULL;
    }
    p->remaining = 0;
    p->buf_len   = 0;
    p->buf_pos   = 0;
    p->draining  = 0;
}

static void halt(player_t *p)
{
    close_file(p);
    p->out->ctrl(p->out->ctx, CTRL_RESET);
    p->state = MBX_ST_STOPPED;
}

static int open_track(player_t *p)
{
    const wav_info_t *w = &p->cat->tracks[p->track].info;

    close_file(p);
    p->f = fopen(p->cat->tracks[p->track].path, "rb");
    if (!p->f || fseek(p->f, (long)w->data_offset, SEEK_SET) != 0) {
        fprintf(stderr, "player: no se pudo abrir %s\n", p->cat->tracks[p->track].path);
        close_file(p);
        return -1;
    }
    p->remaining = w->frames * w->block_align;
    rs_init(&p->rs, w->sample_rate, AP_FS_HZ, w->channels);
    return 0;
}

static void refill(player_t *p)
{
    const wav_info_t *w = &p->cat->tracks[p->track].info;
    uint32_t want = PLAYER_CHUNK_FRAMES * w->block_align;
    uint32_t got, frames;
    size_t used;

    if (want > p->remaining)
        want = p->remaining;
    got    = want ? (uint32_t)fread(p->in, 1, want, p->f) : 0;
    frames = got / w->block_align;
    p->remaining = (got < want) ? 0 : p->remaining - got;
    p->buf_pos   = 0;
    p->buf_len   = frames ? (uint32_t)rs_process(&p->rs, p->in, frames, &used, p->buf, PLAYER_BUF_WORDS) : 0;
}

static void feed(player_t *p)
{
    uint32_t space = p->out->fifo_space(p->out->ctx);

    while (space > 0) {
        uint32_t n;

        if (p->buf_pos == p->buf_len) {
            if (p->remaining == 0) {
                p->draining = 1;
                return;
            }
            refill(p);
            continue;
        }
        n = p->buf_len - p->buf_pos;
        if (n > space)
            n = space;
        p->out->write(p->out->ctx, p->buf + p->buf_pos, n);
        p->buf_pos += n;
        space -= n;
    }
}

static void start(player_t *p)
{
    p->out->ctrl(p->out->ctx, CTRL_RESET);
    p->out->track(p->out->ctx, p->track + 1);
    if (open_track(p) != 0) {
        halt(p);
        return;
    }
    feed(p);
    p->out->ctrl(p->out->ctx, CTRL_RUN);
    p->state = MBX_ST_PLAYING;
}

void player_init(player_t *p, const catalog_t *cat, const audio_out_t *out)
{
    memset(p, 0, sizeof(*p));
    p->cat   = cat;
    p->out   = out;
    p->state = MBX_ST_STOPPED;
    p->out->ctrl(p->out->ctx, CTRL_RESET);
    p->out->track(p->out->ctx, cat->count > 0 ? 1 : 0);
}

void player_command(player_t *p, uint32_t cmd)
{
    uint32_t n = (uint32_t)p->cat->count;
    int was_playing;

    if (n == 0)
        return;
    switch (cmd) {
    case MBX_CMD_PLAY_PAUSE:
        if (p->state == MBX_ST_PLAYING) {
            p->out->ctrl(p->out->ctx, CTRL_IDLE);
            p->state = MBX_ST_PAUSED;
        } else if (p->state == MBX_ST_PAUSED) {
            p->out->ctrl(p->out->ctx, CTRL_RUN);
            p->state = MBX_ST_PLAYING;
        } else {
            start(p);
        }
        break;
    case MBX_CMD_STOP:
        halt(p);
        break;
    case MBX_CMD_NEXT:
    case MBX_CMD_PREV:
        was_playing = (p->state == MBX_ST_PLAYING);
        halt(p);
        p->track = (cmd == MBX_CMD_NEXT) ? (p->track + 1) % n : (p->track + n - 1) % n;
        p->out->track(p->out->ctx, p->track + 1);
        if (was_playing)
            start(p);
        break;
    default:
        return;
    }
    p->changes++;
}

void player_poll(player_t *p)
{
    if (p->state != MBX_ST_PLAYING)
        return;
    if (!p->draining)
        feed(p);
    if (p->draining && p->out->fifo_idle(p->out->ctx)) {
        if (p->track + 1 < (uint32_t)p->cat->count) {
            p->track++;
            start(p);
        } else {
            halt(p);
            p->track = 0;
            p->out->track(p->out->ctx, 1);
        }
        p->changes++;
    }
}

void player_status(const player_t *p, mbx_status_t *s)
{
    memset(s, 0, sizeof(*s));
    s->state = p->state;
    s->track = p->track;
    s->total = (uint32_t)p->cat->count;
    if (p->cat->count > 0) {
        const wav_info_t *w = &p->cat->tracks[p->track].info;

        s->duration_ms = w->duration_ms;
        s->sample_rate = w->sample_rate;
        s->channels    = w->channels;
        memcpy(s->title, w->title, MBX_TEXT);
        memcpy(s->artist, w->artist, MBX_TEXT);
        memcpy(s->album, w->album, MBX_TEXT);
        s->title[MBX_TEXT - 1] = s->artist[MBX_TEXT - 1] = s->album[MBX_TEXT - 1] = '\0';
    }
}

void player_close(player_t *p)
{
    halt(p);
}
