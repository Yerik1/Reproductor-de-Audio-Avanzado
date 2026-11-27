#include "catalog.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define CATALOG_SCAN_MAX 256

static int has_wav_ext(const char *name)
{
    size_t l = strlen(name);

    return l > 4 && strcasecmp(name + l - 4, ".wav") == 0;
}

static int cmp_names(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static void fill_defaults(wav_info_t *info, const char *fname)
{
    if (info->title[0] == '\0') {
        size_t n = strlen(fname) - 4;

        if (n > WAV_TEXT_MAX - 1)
            n = WAV_TEXT_MAX - 1;
        memcpy(info->title, fname, n);
        info->title[n] = '\0';
    }
    if (info->artist[0] == '\0')
        strcpy(info->artist, CATALOG_NO_ARTIST);
    if (info->album[0] == '\0')
        strcpy(info->album, CATALOG_NO_ALBUM);
}

int catalog_load(catalog_t *c, const char *dir)
{
    char *names[CATALOG_SCAN_MAX];
    struct dirent *e;
    DIR *d;
    int n = 0, i;

    c->count = 0;
    c->rejected = 0;
    d = opendir(dir);
    if (!d)
        return -1;
    while ((e = readdir(d)) != NULL && n < CATALOG_SCAN_MAX) {
        if (e->d_name[0] != '.' && has_wav_ext(e->d_name)) {
            names[n] = strdup(e->d_name);
            if (names[n])
                n++;
        }
    }
    closedir(d);
    qsort(names, (size_t)n, sizeof(names[0]), cmp_names);

    for (i = 0; i < n; i++) {
        track_t *t = &c->tracks[c->count];
        int rc = WAV_ERR_IO;

        if (c->count < CATALOG_MAX &&
            snprintf(t->path, sizeof(t->path), "%s/%s", dir, names[i]) < (int)sizeof(t->path))
            rc = wav_probe(t->path, &t->info);
        if (rc == WAV_OK) {
            fill_defaults(&t->info, names[i]);
            c->count++;
        } else {
            c->rejected++;
            fprintf(stderr, "catalogo: %s descartado (%s)\n", names[i], wav_strerror(rc));
        }
        free(names[i]);
    }
    return c->count;
}
