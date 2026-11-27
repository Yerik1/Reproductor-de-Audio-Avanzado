# Componente de Platform Designer para audio_proc
package require -exact qsys 16.1

set_module_property NAME audio_proc
set_module_property DISPLAY_NAME "audio_proc (FIFO + FIR + volumen + 7 segmentos + escritor al Audio Core)"
set_module_property DESCRIPTION "Procesador de audio personalizado del reproductor CE-1113"
set_module_property VERSION 1.0
set_module_property GROUP "CE-1113"
set_module_property AUTHOR "Grupo Proyecto II CE-1113"
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false

# ---------------------------------------------------------------- archivos
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL audio_proc
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file audio_proc.v          VERILOG         PATH audio_proc.v TOP_LEVEL_FILE
add_fileset_file audio_proc_fifo.v     VERILOG         PATH audio_proc_fifo.v
add_fileset_file audio_proc_fir.v      VERILOG         PATH audio_proc_fir.v
add_fileset_file audio_proc_coefs.vh   VERILOG_INCLUDE PATH audio_proc_coefs.vh

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL audio_proc
add_fileset_file audio_proc.v          VERILOG         PATH audio_proc.v
add_fileset_file audio_proc_fifo.v     VERILOG         PATH audio_proc_fifo.v
add_fileset_file audio_proc_fir.v      VERILOG         PATH audio_proc_fir.v
add_fileset_file audio_proc_coefs.vh   VERILOG_INCLUDE PATH audio_proc_coefs.vh

# ---------------------------------------------------------------- parametros
add_parameter FIFO_AW INTEGER 12
set_parameter_property FIFO_AW DISPLAY_NAME "Bits de direccion de la FIFO (profundidad = 2^N)"
set_parameter_property FIFO_AW ALLOWED_RANGES 6:14
set_parameter_property FIFO_AW HDL_PARAMETER true

add_parameter FS_HZ INTEGER 48000
set_parameter_property FS_HZ DISPLAY_NAME "Frecuencia de muestreo del codec (Hz)"
set_parameter_property FS_HZ HDL_PARAMETER true

# ---------------------------------------------------------------- reloj y reset
add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset reset Input 1

# ---------------------------------------------------------------- Avalon-MM esclavo
add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 burstOnBurstBoundariesOnly false
set_interface_property s0 burstcountUnits WORDS
set_interface_property s0 explicitAddressSpan 0
set_interface_property s0 holdTime 0
set_interface_property s0 linewrapBursts false
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 maximumPendingWriteTransactions 0
set_interface_property s0 readLatency 1
set_interface_property s0 readWaitTime 0
set_interface_property s0 setupTime 0
set_interface_property s0 timingUnits Cycles
set_interface_property s0 writeWaitTime 0
add_interface_port s0 avs_address   address   Input  4
add_interface_port s0 avs_read      read      Input  1
add_interface_port s0 avs_write     write     Input  1
add_interface_port s0 avs_writedata writedata Input  32
add_interface_port s0 avs_readdata  readdata  Output 32

# ---------------------------------------------------------------- Avalon-MM maestro hacia el Audio Core
add_interface m0 avalon start
set_interface_property m0 addressUnits SYMBOLS
set_interface_property m0 associatedClock clock
set_interface_property m0 associatedReset reset
set_interface_property m0 bitsPerSymbol 8
set_interface_property m0 burstOnBurstBoundariesOnly false
set_interface_property m0 doStreamReads false
set_interface_property m0 doStreamWrites false
set_interface_property m0 linewrapBursts false
set_interface_property m0 readLatency 0
add_interface_port m0 avm_address     address     Output 4
add_interface_port m0 avm_read        read        Output 1
add_interface_port m0 avm_write       write       Output 1
add_interface_port m0 avm_writedata   writedata   Output 32
add_interface_port m0 avm_readdata    readdata    Input  32
add_interface_port m0 avm_waitrequest waitrequest Input  1

# ---------------------------------------------------------------- conduits a pines de la placa
add_interface sw conduit end
add_interface_port sw coe_sw export Input 2

add_interface hex conduit end
foreach d {0 1 2 3 4 5} {
    add_interface_port hex coe_hex${d} hex${d} Output 7
}
