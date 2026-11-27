# Simulacion de audio_proc en Questa/ModelSim.
# Uso (desde fpga/sim/audio_proc): vsim -c -do run_questa.do
file mkdir out
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -work work +incdir+../../ip/audio_proc \
    ../../ip/audio_proc/audio_proc_fifo.v \
    ../../ip/audio_proc/audio_proc_fir.v \
    ../../ip/audio_proc/audio_proc.v \
    tb_audio_proc.v
vsim -c -l resultados_tb_questa.log work.tb_audio_proc
run -all
quit -f
