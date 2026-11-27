#include "wav.h"

#include <string.h>

#define WAV_FMT_PCM         0x0001u
#define WAV_FMT_EXTENSIBLE  0xFFFEu
#define WAV_LIST_MAX        4096u

static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t rd32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void copy_text(char *dst, const uint8_t *src, uint32_t len)
{
    uint32_t n = len < WAV_TEXT_MAX - 1 ? len : WAV_TEXT_MAX - 1;
    size_t l;

    memcpy(dst, src, n);
    dst[n] = '\0';
    l = strlen(dst);
    while (l > 0 && (dst[l - 1] == ' ' || dst[l - 1] == '\r' || dst[l - 1] == '\n'))
        dst[--l] = '\0';
}

static void parse_info(const uint8_t *b, uint32_t n, wav_info_t *info)
{
    uint32_t p = 4;

    if (n < 4 || memcmp(b, "INFO", 4) != 0)
        return;
    while (p + 8 <= n) {
        const uint8_t *id = b + p;
        uint32_t len = rd32(b + p + 4);

        p += 8;
        if (len > n - p)
            len = n - p;
        if (memcmp(id, "INAM", 4) == 0)
            copy_text(info->title, b + p, len);
        else if (memcmp(id, "IART", 4) == 0)
            copy_text(info->artist, b + p, len);
        else if (memcmp(id, "IPRD", 4) == 0)
            copy_text(info->album, b + p, len);
        p += len + (len & 1u);
    }
}

int wav_parse(FILE *f, wav_info_t *info)
{
    uint8_t hdr[12];
    uint8_t chunk[8];
    uint16_t fmt_tag = 0;
    int have_fmt = 0, have_data = 0;
    long fsize_l;
    int64_t fsize, pos;

    memset(info, 0, sizeof(*info));
    if (fseek(f, 0, SEEK_END) != 0 || (fsize_l = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0)
        return WAV_ERR_IO;
    fsize = fsize_l;
    if (fread(hdr, 1, sizeof(hdr), f) != sizeof(hdr) ||
        memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0)
        return WAV_ERR_NOT_WAVE;

    for (pos = 12; pos + 8 <= fsize;) {
        int64_t body = pos + 8;
        uint32_t len;

        if (fseek(f, (long)pos, SEEK_SET) != 0 || fread(chunk, 1, 8, f) != 8)
            break;
        len = rd32(chunk + 4);

        if (memcmp(chunk, "fmt ", 4) == 0) {
            uint8_t fm[40];
            size_t n = len < sizeof(fm) ? len : sizeof(fm);

            if (len < 16 || fread(fm, 1, n, f) != n)
                return WAV_ERR_FORMAT;
            fmt_tag               = rd16(fm);
            info->channels        = rd16(fm + 2);
            info->sample_rate     = rd32(fm + 4);
            info->block_align     = rd16(fm + 12);
            info->bits_per_sample = rd16(fm + 14);
            if (fmt_tag == WAV_FMT_EXTENSIBLE)
                fmt_tag = n >= 26 ? rd16(fm + 24) : 0;
            have_fmt = 1;
        } else if (memcmp(chunk, "data", 4) == 0) {
            int64_t avail = fsize - body;

            info->data_offset = (uint32_t)body;
            info->data_size   = (len == 0 || (int64_t)len > avail) ? (uint32_t)avail : len;
            len = info->data_size;
            have_data = 1;
        } else if (memcmp(chunk, "LIST", 4) == 0) {
            uint8_t buf[WAV_LIST_MAX];
            size_t n = len < sizeof(buf) ? len : sizeof(buf);

            if (fread(buf, 1, n, f) == n)
                parse_info(buf, (uint32_t)n, info);
        }
        pos = body + (int64_t)len + (len & 1u);
    }

    if (!have_fmt)
        return WAV_ERR_FORMAT;
    if (fmt_tag != WAV_FMT_PCM || info->bits_per_sample != 16 ||
        (info->channels != 1 && info->channels != 2) ||
        info->block_align != info->channels * 2u ||
        info->sample_rate < WAV_MIN_RATE || info->sample_rate > WAV_MAX_RATE)
        return WAV_ERR_UNSUPPORTED;
    if (!have_data || info->data_size < info->block_align)
        return WAV_ERR_NO_DATA;

    info->frames      = info->data_size / info->block_align;
    info->duration_ms = (uint32_t)((uint64_t)info->frames * 1000u / info->sample_rate);
    return WAV_OK;
}

int wav_probe(const char *path, wav_info_t *info)
{
    FILE *f = fopen(path, "rb");
    int rc;

    if (!f) {
        memset(info, 0, sizeof(*info));
        return WAV_ERR_IO;
    }
    rc = wav_parse(f, info);
    fclose(f);
    return rc;
}

const char *wav_strerror(int code)
{
    switch (code) {
    case WAV_OK:              return "ok";
    case WAV_ERR_IO:          return "error de lectura";
    case WAV_ERR_NOT_WAVE:    return "no es RIFF/WAVE";
    case WAV_ERR_FORMAT:      return "chunk fmt ausente o corrupto";
    case WAV_ERR_UNSUPPORTED: return "formato no soportado (requiere PCM 16 bits, 1-2 canales, 8-48 kHz)";
    case WAV_ERR_NO_DATA:     return "sin muestras de audio";
    default:                  return "error desconocido";
    }
}
