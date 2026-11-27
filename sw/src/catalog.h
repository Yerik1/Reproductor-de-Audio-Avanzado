#ifndef CATALOG_H
#define CATALOG_H

#include "wav.h"

#define CATALOG_MAX          64
#define CATALOG_PATH_MAX     256
#define CATALOG_NO_ARTIST    "Artista desconocido"
#define CATALOG_NO_ALBUM     "Album desconocido"

typedef struct {
    char       path[CATALOG_PATH_MAX];
    wav_info_t info;
} track_t;

typedef struct {
    track_t tracks[CATALOG_MAX];
    int     count;
    int     rejected;
} catalog_t;

/* Carga los .wav validos de dir en orden lexicografico del nombre de archivo.
 * Omite archivos ocultos; los WAV invalidos se cuentan en rejected.
 * Sin titulo se usa el nombre del archivo sin extension. Retorna count o -1. */
int catalog_load(catalog_t *c, const char *dir);

#endif
