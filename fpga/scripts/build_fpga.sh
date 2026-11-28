#!/usr/bin/env bash
# Genera el sistema de Platform Designer, compila el proyecto de Quartus y programa la FPGA.
# Uso: fpga/scripts/build_fpga.sh [sistema|compilar|programar|todo]
set -euo pipefail
QDIR="$(cd "$(dirname "$0")/../quartus" && pwd)"
SEARCH='../ip/**/*,$'
cd "$QDIR"
mkdir -p logs

sistema() {
    qsys-script --script=../scripts/build_system.tcl --search-path="$SEARCH" 2>&1 | tee logs/qsys-script.log
    qsys-generate reproductor_soc.qsys --synthesis=VERILOG --search-path="$SEARCH" \
        --output-directory=reproductor_soc 2>&1 | tee logs/qsys-generate.log
}

compilar() {
    quartus_sh --flow compile reproductor > logs/quartus.log 2>&1 || { grep -E "^Error" logs/quartus.log | head -20; exit 1; }
    grep -E "Critical Warning" logs/quartus.log | head -10 || true
    grep -E "Fitter Status|Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks" \
        output_files/reproductor.fit.summary || true
    grep -m1 -A0 "Worst-case Slack" output_files/reproductor.sta.rpt | tr -s ' ' || true
}

programar() {
    quartus_pgm -m jtag -o "p;output_files/reproductor.sof@2"
}

case "${1:-todo}" in
    sistema)   sistema ;;
    compilar)  compilar ;;
    programar) programar ;;
    todo)      sistema; compilar; programar ;;
    *) echo "uso: $0 [sistema|compilar|programar|todo]" >&2; exit 2 ;;
esac
