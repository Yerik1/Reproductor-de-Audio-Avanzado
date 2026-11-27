#!/usr/bin/env bash
# Convierte canciones (mp3, flac, m4a, ogg, wav) a WAV PCM 16 bits estereo conservando
# titulo, artista y album como LIST/INFO. Los archivos se numeran en orden alfabetico.
# Uso: tools/prepare_music.sh <dir_entrada> <dir_salida> [frecuencia_Hz]
set -euo pipefail
IN=${1:?dir_entrada}
OUT=${2:?dir_salida}
RATE=${3:-44100}
mkdir -p "$OUT"
n=$(find "$OUT" -maxdepth 1 -iname '*.wav' | wc -l)
find "$IN" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' \
    -o -iname '*.ogg' -o -iname '*.wav' \) -print0 | sort -z |
while IFS= read -r -d '' f; do
    n=$((n + 1))
    base=$(basename "${f%.*}")
    dst=$(printf '%s/%02d_%s_%dk.wav' "$OUT" "$n" "$base" $((RATE / 1000)))
    ffmpeg -nostdin -loglevel error -y -i "$f" -vn -map_metadata 0 \
        -ac 2 -ar "$RATE" -c:a pcm_s16le "$dst"
    echo "$dst"
done
