# Sistema Platform Designer del reproductor: etapa 1 (Nios V/m + audio_proc + audio + ADC).
# Parametros de los IP de University Program tomados de los scripts de FPGAcademy para la
# DE1-SoC (Design_Examples/Computer_Systems/common/scripts).
# Uso (desde fpga/quartus): qsys-script --script=../scripts/build_system.tcl --search-path="../ip/**/*,$"
package require -exact qsys 15.0

create_system reproductor_soc
set_project_property DEVICE_FAMILY "Cyclone V"
set_project_property DEVICE "5CSEMA5F31C6"

proc connect_agent {manager agent base} {
    add_connection $manager $agent
    set_connection_parameter_value $manager/$agent baseAddress $base
}

proc connect_irq {receiver sender number} {
    add_connection $receiver $sender
    set_connection_parameter_value $receiver/$sender irqNumber $number
}

proc clock_and_reset {instance clk_if reset_if} {
    add_connection clk_50.clk       $instance.$clk_if
    add_connection clk_50.clk_reset $instance.$reset_if
}

# ---------------------------------------------------------------- reloj de sistema 50 MHz
add_instance clk_50 clock_source
set_instance_parameter_value clk_50 clockFrequency        50000000.0
set_instance_parameter_value clk_50 clockFrequencyKnown   true
set_instance_parameter_value clk_50 resetSynchronousEdges DEASSERT
set_interface_property clk   EXPORT_OF clk_50.clk_in
set_interface_property reset EXPORT_OF clk_50.clk_in_reset

# ---------------------------------------------------------------- Nios V/m
add_instance cpu intel_niosv_m
set_instance_parameter_value cpu enableDebug      true
set_instance_parameter_value cpu enableDebugReset true
set_instance_parameter_value cpu enableECCLite    false
set_instance_parameter_value cpu useResetReq      false
set_instance_parameter_value cpu resetSlave       "Absolute"
set_instance_parameter_value cpu resetOffset      0
clock_and_reset cpu clk reset
add_connection clk_50.clk_reset   cpu.ndm_reset_in
add_connection cpu.dbg_reset_out  cpu.ndm_reset_in
connect_agent cpu.data_manager        cpu.timer_sw_agent 0xFF202100
connect_agent cpu.instruction_manager cpu.dm_agent       0x0A000000
connect_agent cpu.data_manager        cpu.dm_agent       0x0A000000

# ---------------------------------------------------------------- memoria del Nios V (256 KB)
add_instance ram altera_avalon_onchip_memory2
set_instance_parameter_value ram memorySize           262144
set_instance_parameter_value ram dualPort             true
set_instance_parameter_value ram singleClockOperation true
set_instance_parameter_value ram initMemContent       false
clock_and_reset ram clk1 reset1
connect_agent cpu.data_manager        ram.s1 0x00000000
connect_agent cpu.instruction_manager ram.s2 0x00000000

# ---------------------------------------------------------------- consola de depuracion
add_instance jtag_uart altera_avalon_jtag_uart
clock_and_reset jtag_uart clk reset
connect_agent cpu.data_manager jtag_uart.avalon_jtag_slave 0xFF201000
connect_irq   cpu.platform_irq_rx jtag_uart.irq 8

# ---------------------------------------------------------------- botones KEY3..KEY0 con IRQ
add_instance key_pio altera_avalon_pio
set_instance_parameter_value key_pio width                 4
set_instance_parameter_value key_pio direction             Input
set_instance_parameter_value key_pio captureEdge           true
set_instance_parameter_value key_pio edgeType              RISING
set_instance_parameter_value key_pio bitClearingEdgeCapReg true
set_instance_parameter_value key_pio generateIRQ           true
set_instance_parameter_value key_pio irqType               EDGE
clock_and_reset key_pio clk reset
set_interface_property key EXPORT_OF key_pio.external_connection
connect_agent cpu.data_manager key_pio.s1 0xFF200050
connect_irq   cpu.platform_irq_rx key_pio.irq 2

# ---------------------------------------------------------------- audio: PLL, Audio Core y configuracion
add_instance audio_pll altera_up_avalon_audio_pll
set_instance_parameter_value audio_pll gui_refclk     50.0
set_instance_parameter_value audio_pll audio_clk_freq 12.288
set_interface_property audio_pll_ref_clk   EXPORT_OF audio_pll.ref_clk
set_interface_property audio_pll_ref_reset EXPORT_OF audio_pll.ref_reset
set_interface_property audio_pll_clk       EXPORT_OF audio_pll.audio_clk

add_instance audio altera_up_avalon_audio
set_instance_parameter_value audio avalon_bus_type "Memory Mapped"
set_instance_parameter_value audio audio_in        true
set_instance_parameter_value audio audio_out       true
set_instance_parameter_value audio dw              32
clock_and_reset audio clk reset
set_interface_property audio EXPORT_OF audio.external_interface
connect_agent cpu.data_manager audio.avalon_audio_slave 0xFF203040

add_instance av_config altera_up_avalon_audio_and_video_config
set_instance_parameter_value av_config board          "DE1-SoC"
set_instance_parameter_value av_config eai            true
set_instance_parameter_value av_config line_in_bypass false
set_instance_parameter_value av_config bit_length     32
set_instance_parameter_value av_config sampling_rate  "48 kHz"
clock_and_reset av_config clk reset
set_interface_property av_config EXPORT_OF av_config.external_interface
connect_agent cpu.data_manager av_config.avalon_av_config_slave 0xFF203000

# ---------------------------------------------------------------- modulo propio audio_proc
add_instance audio_proc_0 audio_proc
set_instance_parameter_value audio_proc_0 FIFO_AW 12
set_instance_parameter_value audio_proc_0 FS_HZ   48000
clock_and_reset audio_proc_0 clock reset
connect_agent cpu.data_manager audio_proc_0.s0 0xFF200000
connect_agent audio_proc_0.m0  audio.avalon_audio_slave 0x0
set_interface_property audio_proc_sw  EXPORT_OF audio_proc_0.sw
set_interface_property audio_proc_hex EXPORT_OF audio_proc_0.hex

# ---------------------------------------------------------------- ADC del potenciometro
add_instance adc altera_up_avalon_adc
set_instance_parameter_value adc board     "DE1-SoC"
set_instance_parameter_value adc sclk_freq 12.5
set_instance_parameter_value adc numch_    8
if {[lsearch [get_instance_parameters adc] board_rev] >= 0} {
    set_instance_parameter_value adc board_rev "Autodetect"
}
clock_and_reset adc clk reset
set_interface_property adc EXPORT_OF adc.external_interface
connect_agent cpu.data_manager adc.adc_slave 0xFF204000

save_system reproductor_soc.qsys
