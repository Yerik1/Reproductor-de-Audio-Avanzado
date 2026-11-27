#!/usr/bin/env python3
"""Diseno y cuantizacion de los filtros FIR del modulo audio_proc.

Genera:
  - fpga/ip/audio_proc/audio_proc_coefs.vh : contenido inicial de la RAM de coeficientes
  - docs/img/filtros_respuesta.png         : respuesta en frecuencia de los filtros cuantizados
"""
import argparse
import pathlib

import numpy as np
from scipy import signal

FS = 48000          # frecuencia fija de la ruta de audio en FPGA (codec WM8731)
TAP_AW = 7
NT = 1 << TAP_AW    # posiciones por banco en la RAM de coeficientes
NTAPS = NT - 1      # orden impar: fase lineal tipo I, valido tambien para pasa-altos
QBITS = 15          # formato Q1.15

# banco -> (codigo, descripcion, parametros de firwin)
FILTERS = {
    1: ("LPF", "Pasa-bajos 1 kHz", dict(cutoff=1000.0, pass_zero=True)),
    2: ("HPF", "Pasa-altos 2 kHz", dict(cutoff=2000.0, pass_zero=False)),
    3: ("BPF", "Pasa-banda 300-3400 Hz", dict(cutoff=[300.0, 3400.0], pass_zero=False)),
}

ROOT = pathlib.Path(__file__).resolve().parents[1]


def design(bank):
    kw = FILTERS[bank][2]
    return signal.firwin(NTAPS, kw["cutoff"], pass_zero=kw["pass_zero"], fs=FS, window="hamming")


def quantize(h):
    q = np.clip(np.round(h * (1 << QBITS)), -32768, 32767).astype(np.int64)
    out = np.zeros(NT, dtype=np.int64)
    out[: len(q)] = q
    return out


def coef_banks():
    """Matriz 4 x NT; el banco 0 corresponde a bypass y no usa coeficientes."""
    banks = np.zeros((4, NT), dtype=np.int64)
    for b in FILTERS:
        banks[b] = quantize(design(b))
    return banks


def write_vh(banks, path):
    lines = ["// Generado por tools/filters.py", "// coef_mem[banco*128 + k], Q1.15"]
    for b in range(4):
        name = FILTERS[b][1] if b in FILTERS else "Bypass (sin uso)"
        lines.append(f"// Banco {b}: {name}")
        for k in range(NT):
            lines.append(f"coef_mem[{b * NT + k}] = 16'h{int(banks[b, k]) & 0xFFFF:04X};")
    path.write_text("\n".join(lines) + "\n")


def plot(banks, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(8, 4.2))
    for b, (code, desc, _) in FILTERS.items():
        w, H = signal.freqz(banks[b] / (1 << QBITS), worN=8192, fs=FS)
        ax.semilogx(w[1:], 20 * np.log10(np.maximum(np.abs(H[1:]), 1e-6)), label=f"{b}: {desc}")
    ax.set_xlim(20, FS / 2)
    ax.set_ylim(-80, 5)
    ax.set_xlabel("Frecuencia (Hz)")
    ax.set_ylabel("Magnitud (dB)")
    ax.set_title(f"Filtros FIR cuantizados Q1.15, {NTAPS} taps, fs = {FS} Hz")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(path, dpi=120)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--no-plot", action="store_true")
    args = ap.parse_args()

    banks = coef_banks()
    vh = ROOT / "fpga/ip/audio_proc/audio_proc_coefs.vh"
    vh.parent.mkdir(parents=True, exist_ok=True)
    write_vh(banks, vh)
    print(f"{vh.relative_to(ROOT)}")
    for b, (code, desc, _) in FILTERS.items():
        h = banks[b] / (1 << QBITS)
        _, H = signal.freqz(h, worN=8192, fs=FS)
        print(f"  banco {b} {code:3s} {desc:24s} sum|h|={np.abs(h).sum():.3f}  "
              f"ganancia max={20 * np.log10(np.abs(H).max()):+.2f} dB")
    if not args.no_plot:
        png = ROOT / "docs/img/filtros_respuesta.png"
        png.parent.mkdir(parents=True, exist_ok=True)
        plot(banks, png)
        print(f"{png.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
