/* Pruebas unitarias en PC de wav, catalog y resampler. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "catalog.h"
#include "resampler.h"
#include "wav.h"

static int g_checks, g_fails;

#define CHECK(cond)                                                          \
    do {                                                                     \
        g_checks++;                                                          \
        if (!(cond)) {                                                       \
            g_fails++;                                                       \
            fprintf(stderr, "  FALLA %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                    \
    } while (0)

/* ------------------------------------------------------------ generador de WAV */
typedef struct {
    uint16_t    tag;
    uint16_t    ch;
    uint32_t    rate;
    uint16_t    bits;
    uint32_t    frames;
    const char *title, *artist, *album;
    int         list_after_data;
    int         extensible;
    int         data_size_zero;
} wspec_t;

static void put16(FILE *f, uint16_t v) { fputc(v & 0xFF, f); fputc(v >> 8, f); }
static void put32(FILE *f, uint32_t v) { put16(f, (uint16_t)v); put16(f, (uint16_t)(v >> 16)); }

static uint32_t info_size(const char *s)
{
    uint32_t n;

    if (!s)
        return 0;
    n = (uint32_t)strlen(s) + 1;
    return 8 + n + (n & 1u);
}

static void put_info(FILE *f, const char *id, const char *s)
{
    uint32_t n;

    if (!s)
        return;
    n = (uint32_t)strlen(s) + 1;
    fwrite(id, 1, 4, f);
    put32(f, n);
    fwrite(s, 1, n, f);
    if (n & 1u)
        fputc(0, f);
}

static void put_list(FILE *f, const wspec_t *w)
{
    if (!w->title && !w->artist && !w->album)
        return;
    fwrite("LIST", 1, 4, f);
    put32(f, 4 + info_size(w->title) + info_size(w->artist) + info_size(w->album));
    fwrite("INFO", 1, 4, f);
    put_info(f, "INAM", w->title);
    put_info(f, "IART", w->artist);
    put_info(f, "IPRD", w->album);
}

static void make_wav(const char *path, const wspec_t *w)
{
    FILE *f = fopen(path, "wb");
    uint16_t ba = (uint16_t)(w->ch * w->bits / 8);
    uint32_t dsz = w->frames * ba, i;

    fwrite("RIFF", 1, 4, f);
    put32(f, 0);
    fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f);
    put32(f, w->extensible ? 40 : 16);
    put16(f, w->extensible ? 0xFFFE : w->tag);
    put16(f, w->ch);
    put32(f, w->rate);
    put32(f, w->rate * ba);
    put16(f, ba);
    put16(f, w->bits);
    if (w->extensible) {
        static const uint8_t tail[14] = {0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00,
                                         0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71};
        put16(f, 22);
        put16(f, w->bits);
        put32(f, 0);
        put16(f, w->tag);
        fwrite(tail, 1, sizeof(tail), f);
    }
    if (!w->list_after_data)
        put_list(f, w);
    fwrite("data", 1, 4, f);
    put32(f, w->data_size_zero ? 0 : dsz);
    for (i = 0; i < dsz; i++)
        fputc((int)(i * 37u) & 0xFF, f);
    if (dsz & 1u)
        fputc(0, f);
    if (w->list_after_data)
        put_list(f, w);
    fclose(f);
}

static char g_dir[64];

static const char *tmp_path(const char *name)
{
    static char p[256];

    snprintf(p, sizeof(p), "%s/%s", g_dir, name);
    return p;
}

/* ------------------------------------------------------------ wav */
static void test_wav(void)
{
    wav_info_t in;
    wspec_t w;
    FILE *f;

    printf("[wav]\n");
    w = (wspec_t){1, 1, 8000, 16, 8000, "Cancion A", "Artista A", "Album A", 0, 0, 0};
    make_wav(tmp_path("a.wav"), &w);
    CHECK(wav_probe(tmp_path("a.wav"), &in) == WAV_OK);
    CHECK(in.channels == 1 && in.sample_rate == 8000 && in.frames == 8000);
    CHECK(in.duration_ms == 1000);
    CHECK(strcmp(in.title, "Cancion A") == 0 && strcmp(in.artist, "Artista A") == 0);
    CHECK(strcmp(in.album, "Album A") == 0);

    w = (wspec_t){1, 2, 44100, 16, 88200, "Tema", "Banda impar", "Disco", 1, 0, 0};
    make_wav(tmp_path("b.wav"), &w);
    CHECK(wav_probe(tmp_path("b.wav"), &in) == WAV_OK);
    CHECK(in.channels == 2 && in.sample_rate == 44100 && in.duration_ms == 2000);
    CHECK(in.data_size == 88200u * 4u && in.data_offset == 44);
    CHECK(strcmp(in.title, "Tema") == 0 && strcmp(in.artist, "Banda impar") == 0);

    w = (wspec_t){1, 2, 16000, 16, 16000, NULL, NULL, NULL, 0, 1, 0};
    make_wav(tmp_path("c.wav"), &w);
    CHECK(wav_probe(tmp_path("c.wav"), &in) == WAV_OK);
    CHECK(in.sample_rate == 16000 && in.duration_ms == 1000 && in.title[0] == '\0');

    w = (wspec_t){1, 1, 16000, 16, 1600, NULL, NULL, NULL, 0, 0, 1};
    make_wav(tmp_path("d.wav"), &w);
    CHECK(wav_probe(tmp_path("d.wav"), &in) == WAV_OK && in.frames == 1600);

    w = (wspec_t){1, 1, 8000, 8, 800, NULL, NULL, NULL, 0, 0, 0};
    make_wav(tmp_path("e8.wav"), &w);
    CHECK(wav_probe(tmp_path("e8.wav"), &in) == WAV_ERR_UNSUPPORTED);
    w = (wspec_t){1, 2, 44100, 24, 800, NULL, NULL, NULL, 0, 0, 0};
    make_wav(tmp_path("e24.wav"), &w);
    CHECK(wav_probe(tmp_path("e24.wav"), &in) == WAV_ERR_UNSUPPORTED);
    w = (wspec_t){1, 2, 96000, 16, 800, NULL, NULL, NULL, 0, 0, 0};
    make_wav(tmp_path("e96.wav"), &w);
    CHECK(wav_probe(tmp_path("e96.wav"), &in) == WAV_ERR_UNSUPPORTED);
    w = (wspec_t){3, 2, 44100, 16, 800, NULL, NULL, NULL, 0, 1, 0};
    make_wav(tmp_path("efloat.wav"), &w);
    CHECK(wav_probe(tmp_path("efloat.wav"), &in) == WAV_ERR_UNSUPPORTED);

    f = fopen(tmp_path("txt.wav"), "wb");
    fputs("esto no es un archivo de audio", f);
    fclose(f);
    CHECK(wav_probe(tmp_path("txt.wav"), &in) == WAV_ERR_NOT_WAVE);
    f = fopen(tmp_path("trunc.wav"), "wb");
    fputs("RIFF", f);
    fclose(f);
    CHECK(wav_probe(tmp_path("trunc.wav"), &in) == WAV_ERR_NOT_WAVE);
    CHECK(wav_probe(tmp_path("no_existe.wav"), &in) == WAV_ERR_IO);
}

/* ------------------------------------------------------------ catalog */
static void test_catalog(void)
{
    static catalog_t c;
    char sub[128], p[256];
    wspec_t ok_meta = {1, 2, 44100, 16, 441, "Titulo uno", "Artista", "Album", 0, 0, 0};
    wspec_t ok_bare = {1, 1, 8000, 16, 80, NULL, NULL, NULL, 0, 0, 0};
    wspec_t bad = {1, 1, 8000, 8, 80, NULL, NULL, NULL, 0, 0, 0};
    FILE *f;
    int i;

    printf("[catalog]\n");
    snprintf(sub, sizeof(sub), "%s/sd", g_dir);
    CHECK(mkdir(sub, 0755) == 0);
    snprintf(p, sizeof(p), "%s/03_c.wav", sub); make_wav(p, &ok_bare);
    snprintf(p, sizeof(p), "%s/01_a.WAV", sub); make_wav(p, &ok_meta);
    snprintf(p, sizeof(p), "%s/02_b.wav", sub); make_wav(p, &ok_bare);
    snprintf(p, sizeof(p), "%s/._01_a.wav", sub); make_wav(p, &bad);
    snprintf(p, sizeof(p), "%s/04_malo.wav", sub); make_wav(p, &bad);
    snprintf(p, sizeof(p), "%s/notas.txt", sub);
    f = fopen(p, "w"); fputs("x", f); fclose(f);

    CHECK(catalog_load(&c, sub) == 3);
    CHECK(c.rejected == 1);
    CHECK(strstr(c.tracks[0].path, "01_a.WAV") != NULL);
    CHECK(strstr(c.tracks[1].path, "02_b.wav") != NULL);
    CHECK(strcmp(c.tracks[0].info.title, "Titulo uno") == 0);
    CHECK(strcmp(c.tracks[2].info.title, "03_c") == 0);
    CHECK(strcmp(c.tracks[2].info.artist, CATALOG_NO_ARTIST) == 0);
    CHECK(strcmp(c.tracks[2].info.album, CATALOG_NO_ALBUM) == 0);

    for (i = 5; i <= 14; i++) {
        snprintf(p, sizeof(p), "%s/%02d_extra.wav", sub, i);
        make_wav(p, &ok_meta);
    }
    CHECK(catalog_load(&c, sub) == 13);
    CHECK(catalog_load(&c, "/ruta/inexistente") == -1);
}

/* ------------------------------------------------------------ resampler */
#define RS_N 4000

static void test_resampler(void)
{
    static int16_t in[2 * RS_N];
    static uint32_t a[8 * RS_N], b[8 * RS_N];
    resampler_t r;
    size_t used, na, nb, i, pos;
    int ok;

    printf("[resampler]\n");
    for (i = 0; i < RS_N; i++) {
        in[2 * i]     = (int16_t)(i * 7 - 9000);
        in[2 * i + 1] = (int16_t)(-(int)i * 5);
    }

    rs_init(&r, 48000, 48000, 2);
    na = rs_process(&r, in, RS_N, &used, a, 8 * RS_N);
    CHECK(used == RS_N && na == RS_N - 1);
    for (ok = 1, i = 0; i < na; i++)
        ok &= a[i] == rs_pack(in[2 * i], in[2 * i + 1]);
    CHECK(ok);

    rs_init(&r, 8000, 48000, 2);
    na = rs_process(&r, in, RS_N, &used, a, 8 * RS_N);
    CHECK(na >= 6 * (RS_N - 2) && na <= 6 * RS_N);
    for (ok = 1, i = 0; i + 1 < na; i++) {
        int16_t l0 = (int16_t)(a[i] >> 16), l1 = (int16_t)(a[i + 1] >> 16);
        ok &= l1 >= l0;
    }
    CHECK(ok);
    CHECK(abs((int16_t)(a[6] >> 16) - in[2]) <= 1);

    rs_init(&r, 44100, 48000, 2);
    na = rs_process(&r, in, RS_N, &used, a, 8 * RS_N);
    CHECK(na >= (size_t)((RS_N - 2) * 48000.0 / 44100.0) && na <= (size_t)(RS_N * 48000.0 / 44100.0) + 1);

    rs_init(&r, 44100, 48000, 2);
    for (nb = 0, pos = 0; pos < RS_N;) {
        size_t chunk = 1 + (pos * 13) % 97;
        size_t lim = 1 + (pos * 7) % 50;

        if (chunk > RS_N - pos)
            chunk = RS_N - pos;
        nb += rs_process(&r, in + 2 * pos, chunk, &used, b + nb, lim);
        pos += used;
    }
    nb += rs_process(&r, in, 0, &used, b + nb, 8 * RS_N - nb);
    CHECK(nb == na);
    CHECK(memcmp(a, b, na * sizeof(a[0])) == 0);

    for (i = 0; i < RS_N; i++)
        in[i] = (int16_t)(i * 3);
    rs_init(&r, 16000, 48000, 1);
    na = rs_process(&r, in, RS_N, &used, a, 8 * RS_N);
    for (ok = 1, i = 0; i < na; i++)
        ok &= (a[i] >> 16) == (a[i] & 0xFFFFu);
    CHECK(ok && na >= 3 * (RS_N - 2));
}

int main(void)
{
    char cmd[128];

    strcpy(g_dir, "/tmp/ce1113_testXXXXXX");
    if (!mkdtemp(g_dir)) {
        perror("mkdtemp");
        return 2;
    }
    test_wav();
    test_catalog();
    test_resampler();
    snprintf(cmd, sizeof(cmd), "rm -rf %s", g_dir);
    if (system(cmd) != 0)
        fprintf(stderr, "no se pudo borrar %s\n", g_dir);
    printf("%d verificaciones, %d fallas\nRESULTADO: %s\n", g_checks, g_fails, g_fails ? "FAIL" : "PASS");
    return g_fails ? 1 : 0;
}
