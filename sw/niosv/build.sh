#!/usr/bin/env bash
# Compila una aplicacion del Nios V/m contra el sistema generado y, con "descargar", la carga
# por JTAG y abre la terminal de la JTAG UART.
# Uso: sw/niosv/build.sh <aplicacion> [descargar]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP=${1:-bringup}
SOPC=$(find "$ROOT/fpga/quartus" -maxdepth 2 -name reproductor_soc.sopcinfo | head -n1)
[[ -n "$SOPC" ]] || { echo "No existe reproductor_soc.sopcinfo; ejecutar fpga/scripts/build_fpga.sh sistema" >&2; exit 1; }
B="$ROOT/sw/niosv/build/$APP"
rm -rf "$B"
mkdir -p "$B/src"
cp "$ROOT/sw/niosv/$APP"/*.[ch] "$ROOT/sw/src/audio_proc_regs.h" "$B/src/"
niosv-bsp --create --type=hal --sopcinfo="$SOPC" "$B/bsp/settings.bsp"
niosv-app --app-dir="$B/app" --bsp-dir="$B/bsp" --srcs="$B/src"
cmake -G "Unix Makefiles" -S "$B/app" -B "$B/app/build"
make -C "$B/app/build"
ELF=$(find "$B/app/build" -maxdepth 1 -name "*.elf" | head -n1)
echo "ELF: $ELF"
if [[ "${2:-}" == "descargar" ]]; then
    niosv-download -g "$ELF"
    juart-terminal
fi
