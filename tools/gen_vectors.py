#!/usr/bin/env python3
"""Modelo de referencia bit-exacto de audio_proc y vectores para el testbench.

Cada caso k genera fpga/sim/audio_proc/vectors/stim_k.hex y exp_k.hex con N palabras
de 32 bits: [31:16] canal izquierdo, [15:0] canal derecho (PCM con signo).
"""
import pathlib

import numpy as np

from filters import FS, NT, coef_banks

N = 1024
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "fpga/sim/audio_proc/vectors"

# id -> (nombre, seleccion de filtro, volumen, estimulo)
CASES = {
    0: ("bypass", 0, 0x8000, "tonos"),
    1: ("lpf", 1, 0x8000, "tonos"),
    2: ("hpf", 2, 0x8000, "tonos"),
    3: ("bpf", 3, 0x8000, "tonos"),
    4: ("lpf_vol50", 1, 0x4000, "tonos"),
    5: ("sat_bypass_vol2", 0, 0xFFFF, "extremo"),
    6: ("sat_lpf", 1, 0x8000, "extremo"),
    7: ("hpf_por_switches", 2, 0x8000, "tonos"),
    8: ("coef_programados", 3, 0x8000, "tonos"),
}


def sat16(v):
    return np.clip(v, -32768, 32767).astype(np.int64)


def fir_q15(x, h):
    acc = np.convolve(x.astype(np.int64), h.astype(np.int64))[: len(x)]
    return sat16((acc + (1 << 14)) >> 15)


def volume(y, v):
    return sat16((y.astype(np.int64) * v + (1 << 14)) >> 15)


def model(x, sel, vol, banks):
    y = x.astype(np.int64) if sel == 0 else fir_q15(x, banks[sel])
    return volume(y, vol)


def stimulus(kind):
    n = np.arange(N)
    if kind == "tonos":
        t = n / FS
        l = 0.35 * np.sin(2 * np.pi * 200 * t) + 0.35 * np.sin(2 * np.pi * 6000 * t)
        r = 0.30 * np.sin(2 * np.pi * 1000 * t) + 0.30 * np.sin(2 * np.pi * 12000 * t)
        return sat16(np.round(l * 32767)), sat16(np.round(r * 32767))
    l = np.where((n // 24) % 2 == 0, 32767, -32768)
    r = np.zeros(N, dtype=np.int64)
    r[0], r[200] = 32767, -32768
    r[400:700], r[700:900] = 32767, -32768
    return sat16(l), r


def coef_programmed():
    h = np.zeros(NT, dtype=np.int64)
    h[0], h[40], h[100] = 16384, 8192, -8192
    return h


def pack(l, r):
    return [((int(a) & 0xFFFF) << 16) | (int(b) & 0xFFFF) for a, b in zip(l, r)]


def write_hex(path, words, digits=8):
    path.write_text("".join(f"{w:0{digits}X}\n" for w in words))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    banks = coef_banks()
    prog = banks.copy()
    prog[3] = coef_programmed()
    write_hex(OUT / "coef_prog.hex", [int(c) & 0xFFFF for c in prog[3]], 4)
    for cid, (name, sel, vol, kind) in CASES.items():
        l, r = stimulus(kind)
        bk = prog if name == "coef_programados" else banks
        yl, yr = model(l, sel, vol, bk), model(r, sel, vol, bk)
        write_hex(OUT / f"stim_{cid}.hex", pack(l, r))
        write_hex(OUT / f"exp_{cid}.hex", pack(yl, yr))
        nsat = int(np.sum(np.abs(np.concatenate([yl, yr])) >= 32767))
        print(f"caso {cid}: {name:18s} filtro={sel} vol=0x{vol:04X} estimulo={kind:8s} muestras saturadas={nsat}")


if __name__ == "__main__":
    main()
