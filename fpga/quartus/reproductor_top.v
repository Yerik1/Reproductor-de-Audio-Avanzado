// Top-level del reproductor en la DE1-SoC: instancia el sistema de Platform Designer y
// conecta pulsadores, switches, displays, codec WM8731 y ADC.
module reproductor_top (
    input  wire       CLOCK_50,
    input  wire       CLOCK3_50,
    input  wire [3:0] KEY,
    input  wire [9:0] SW,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    input  wire       AUD_ADCDAT,
    inout  wire       AUD_ADCLRCK,
    inout  wire       AUD_BCLK,
    output wire       AUD_DACDAT,
    inout  wire       AUD_DACLRCK,
    output wire       AUD_XCK,
    output wire       FPGA_I2C_SCLK,
    inout  wire       FPGA_I2C_SDAT,
    inout  wire       ADC_CS_N,
    output wire       ADC_DIN,
    input  wire       ADC_DOUT,
    output wire       ADC_SCLK
);
    // Reset de encendido: mantiene el sistema en reset 2^15 ciclos tras la configuracion
    reg [15:0] por = 16'd0;
    always @(posedge CLOCK_50)
        if (!por[15])
            por <= por + 1'b1;

    reproductor_soc u_soc (
        .clk_clk                   (CLOCK_50),
        .reset_reset_n             (por[15]),
        .key_export                (~KEY),
        .audio_proc_sw_export      (SW[1:0]),
        .audio_proc_hex_hex0       (HEX0),
        .audio_proc_hex_hex1       (HEX1),
        .audio_proc_hex_hex2       (HEX2),
        .audio_proc_hex_hex3       (HEX3),
        .audio_proc_hex_hex4       (HEX4),
        .audio_proc_hex_hex5       (HEX5),
        .audio_pll_ref_clk_clk     (CLOCK3_50),
        .audio_pll_ref_reset_reset (1'b0),
        .audio_pll_clk_clk         (AUD_XCK),
        .audio_ADCDAT              (AUD_ADCDAT),
        .audio_ADCLRCK             (AUD_ADCLRCK),
        .audio_BCLK                (AUD_BCLK),
        .audio_DACDAT              (AUD_DACDAT),
        .audio_DACLRCK             (AUD_DACLRCK),
        .av_config_SDAT            (FPGA_I2C_SDAT),
        .av_config_SCLK            (FPGA_I2C_SCLK),
        .adc_sclk                  (ADC_SCLK),
        .adc_cs_n                  (ADC_CS_N),
        .adc_dout                  (ADC_DOUT),
        .adc_din                   (ADC_DIN)
    );
endmodule
