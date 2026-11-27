#!/usr/bin/env python3
"""Genera un catalogo de prueba de 12 WAV PCM 16 bits para la tarjeta SD.

Incluye las tres frecuencias requeridas (8, 16 y 44,1 kHz), mono y estereo, con
metadatos LIST/INFO y dos pistas sin metadatos para probar los valores por defecto.
Uso: python3 tools/gen_test_wavs.py <directorio_salida> [--segundos 20]
"""
import argparse
import pathlib
import struct

import numpy as np

NOTES = {"C": 261.63, "D": 293.66, "E": 329.63, "F": 349.23, "G": 392.00, "A": 440.00, "B": 493.88}

# (archivo, fs, canales, titulo, artista, album, secuencia de notas)
TRACKS = [
    ("01_escala_44k.wav", 44100, 2, "Escala de Do", "Grupo CE-1113", "Pruebas 44k", "CDEFGAB"),
    ("02_arpegio_44k.wav", 44100, 2, "Arpegio mayor", "Grupo CE-1113", "Pruebas 44k", "CEGCEGB"),
    ("03_tono_16k.wav", 16000, 2, "Melodia 16 kHz", "Grupo CE-1113", "Pruebas 16k", "GFEDCDE"),
    ("04_tono_8k.wav", 8000, 1, "Melodia 8 kHz mono", "Grupo CE-1113", "Pruebas 8k", "EEFGGFE"),
    ("05_barrido_44k.wav", 44100, 2, "Notas largas", "Grupo CE-1113", "Pruebas 44k", "CGAF"),
    ("06_mono_16k.wav", 16000, 1, "Mono 16 kHz", "Grupo CE-1113", "Pruebas 16k", "ABAGFE"),
    ("07_sin_metadatos_44k.wav", 44100, 2, None, None, None, "DFAD"),
    ("08_graves_8k.wav", 8000, 2, "Graves 8 kHz", "Grupo CE-1113", "Pruebas 8k", "CCGG"),
    ("09_agudos_44k.wav", 44100, 2, "Agudos", "Grupo CE-1113", "Pruebas 44k", "BAGB"),
    ("10_sin_metadatos_16k.wav", 16000, 2, None, None, None, "EDCE"),
    ("11_repeticion_44k.wav", 44100, 2, "Repeticion", "Grupo CE-1113", "Pruebas 44k", "CECE"),
    ("12_final_8k.wav", 8000, 1, "Final 8 kHz", "Grupo CE-1113", "Pruebas 8k", "GEC"),
]


def synth(fs, seconds, seq, octave):
    n = int(fs * seconds)
    t = np.arange(n) / fs
    idx = np.minimum((t * len(seq) * 2 / seconds).astype(int) % len(seq), len(seq) - 1)
    f = np.array([NOTES[c] * octave for c in seq])[idx]
    phase = 2 * np.pi * np.cumsum(f) / fs
    env = 0.6 + 0.4 * np.cos(2 * np.pi * (t * len(seq) * 2 / seconds % 1))
    return 0.25 * env * (np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase))


def info_chunk(title, artist, album):
    body = b"INFO"
    for cid, txt in ((b"INAM", title), (b"IART", artist), (b"IPRD", album)):
        if txt:
            data = txt.encode("utf-8") + b"\0"
            body += cid + struct.pack("<I", len(data)) + data + (b"\0" if len(data) % 2 else b"")
    return b"LIST" + struct.pack("<I", len(body)) + body


def write_wav(path, fs, ch, x, title, artist, album):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    if ch == 2:
        pcm = np.stack([pcm, np.roll(pcm, fs // 100)], axis=1).reshape(-1)
    data = pcm.tobytes()
    fmt = struct.pack("<HHIIHH", 1, ch, fs, fs * ch * 2, ch * 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if title:
        chunks += info_chunk(title, artist, album)
    chunks += b"data" + struct.pack("<I", len(data)) + data
    path.write_bytes(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("salida")
    ap.add_argument("--segundos", type=float, default=20.0)
    args = ap.parse_args()
    out = pathlib.Path(args.salida)
    out.mkdir(parents=True, exist_ok=True)
    for i, (name, fs, ch, title, artist, album, seq) in enumerate(TRACKS):
        x = synth(fs, args.segundos, seq, 1 + (i % 3))
        write_wav(out / name, fs, ch, x, title, artist, album)
        print(f"{name:28s} {fs:6d} Hz {ch} canal(es) {title or '(sin metadatos)'}")


if __name__ == "__main__":
    main()
