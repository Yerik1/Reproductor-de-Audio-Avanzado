#!/usr/bin/env bash
# Simulacion de audio_proc con Icarus Verilog. Uso: ./run_iverilog.sh [--vcd]
set -euo pipefail
cd "$(dirname "$0")"
IP=../../ip/audio_proc
mkdir -p out
iverilog -g2005 -Wall -I "$IP" -o tb_audio_proc.vvp \
    "$IP/audio_proc_fifo.v" "$IP/audio_proc_fir.v" "$IP/audio_proc.v" tb_audio_proc.v
PLUS=""
[[ "${1:-}" == "--vcd" ]] && PLUS="+vcd"
{
    echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Simulador: $(iverilog -V 2>&1 | head -n1)"
    vvp -n tb_audio_proc.vvp $PLUS
} | tee resultados_tb.log
grep -q "RESULTADO: PASS" resultados_tb.log
