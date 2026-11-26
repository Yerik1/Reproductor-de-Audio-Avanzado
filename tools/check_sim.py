#!/usr/bin/env python3
"""Evidencia grafica de la simulacion de audio_proc.

Lee las salidas capturadas por el testbench (fpga/sim/audio_proc/out/out_k.hex), las
compara contra el modelo (vectors/exp_k.hex) y genera docs/img/verificacion_filtros.png
con el espectro de entrada y salida de bypass y de los tres filtros.
"""
import pathlib
import sys

import numpy as np

from filters import FS
from gen_vectors import CASES

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIM = ROOT / "fpga/sim/audio_proc"


def load(path):
    w = np.array([int(x, 16) for x in path.read_text().split()], dtype=np.int64)
    to_s = lambda v: np.where(v >= 32768, v - 65536, v)
    return to_s(w >> 16), to_s(w & 0xFFFF)


def spectrum(x):
    win = np.hanning(len(x))
    X = np.abs(np.fft.rfft(x * win)) / (np.sum(win) / 2) / 32768
    return np.fft.rfftfreq(len(x), 1 / FS), 20 * np.log10(np.maximum(X, 1e-7))


def main():
    ok = True
    for cid, (name, *_rest) in CASES.items():
        out = SIM / f"out/out_{cid}.hex"
        if not out.exists():
            print(f"caso {cid}: falta {out.relative_to(ROOT)}; ejecutar primero la simulacion")
            return 1
        gl, gr = load(out)
        el, er = load(SIM / f"vectors/exp_{cid}.hex")
        same = int(np.sum((gl == el) & (gr == er)))
        ok &= same == len(el)
        print(f"caso {cid}: {name:18s} {same}/{len(el)} muestras bit-exactas")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(10, 6), sharex=True, sharey=True)
    il, ir = load(SIM / "vectors/stim_0.hex")
    for ax, cid in zip(axes.flat, (0, 1, 2, 3)):
        ol, orr = load(SIM / f"out/out_{cid}.hex")
        for sig, lbl, st in ((il, "entrada L", ":"), (ir, "entrada R", ":"),
                             (ol, "salida L", "-"), (orr, "salida R", "-")):
            f, m = spectrum(sig[128:])
            ax.semilogx(f[1:], m[1:], st, label=lbl, linewidth=1)
        ax.set_title(f"Caso {cid}: {CASES[cid][0]}")
        ax.grid(True, which="both", alpha=0.3)
        ax.set_xlim(50, FS / 2)
        ax.set_ylim(-100, 0)
    for ax in axes[1]:
        ax.set_xlabel("Frecuencia (Hz)")
    for ax in axes[:, 0]:
        ax.set_ylabel("dBFS")
    axes[0, 0].legend(fontsize=8, loc="lower left")
    fig.suptitle("audio_proc en simulacion RTL: L = 200 Hz + 6 kHz, R = 1 kHz + 12 kHz")
    fig.tight_layout()
    png = ROOT / "docs/img/verificacion_filtros.png"
    fig.savefig(png, dpi=110)
    print(png.relative_to(ROOT))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
