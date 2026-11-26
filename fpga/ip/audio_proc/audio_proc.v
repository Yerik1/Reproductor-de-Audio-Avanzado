// audio_proc: modulo de hardware personalizado del reproductor.
// Esclavo Avalon-MM (registros de control, estado y datos) que recibe muestras PCM
// estereo, las almacena en una FIFO, aplica el banco FIR y el volumen, y las escribe
// en el Audio Core (modo memory-mapped) por un maestro Avalon-MM propio.
// Cuenta las muestras reproducidas y muestra el tiempo MM:SS en HEX3..HEX0 y el
// numero de pista en HEX5..HEX4 (segmentos activos en bajo).
//
// Mapa de registros (offset en bytes):
//   0x00 ID          RO  0x41554450 ("AUDP")
//   0x04 CTRL        RW  [0] RUN, [1] FLUSH (W1), [2] TIME_CLR (W1), [3] SEL_SRC,
//                        [5:4] FILTER, [8] HEX_EN
//   0x08 STATUS      RO  [1:0] filtro activo, [2] FIFO vacia, [3] FIFO llena, [4] RUN,
//                        [5] motor ocupado, [9:8] switches sincronizados
//   0x0C FIFO_SPACE  RO  posiciones libres en la FIFO
//   0x10 DATA        WO  [31:16] izquierda, [15:0] derecha (PCM 16 bits con signo)
//   0x14 VOLUME      RW  [15:0] ganancia Q1.15 sin signo (0x8000 = 1.0)
//   0x18 PLAYED      RO  muestras estereo escritas en el Audio Core desde TIME_CLR
//   0x1C TIME        RO  [15:0] BCD MMSS
//   0x20 TRACK       RW  [6:0] numero de pista mostrado en HEX5..HEX4 (0 = apagado)
//   0x24 UNDERRUN    RO  eventos de FIFO vacia con RUN = 1
//   0x28 COEF_ADDR   RW  [8:0] {banco[1:0], tap[6:0]}
//   0x2C COEF_DATA   WO  [15:0] coeficiente Q1.15; COEF_ADDR se incrementa
//   0x30 OVERFLOW    RO  escrituras descartadas por FIFO llena
//   0x34 FIFO_DEPTH  RO  capacidad de la FIFO en muestras estereo
`timescale 1ns/1ps
module audio_proc #(
    parameter FIFO_AW = 12,
    parameter FS_HZ   = 48000
) (
    input  wire        clk,
    input  wire        reset,
    // Avalon-MM esclavo, latencia de lectura 1
    input  wire [3:0]  avs_address,
    input  wire        avs_read,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    output reg  [31:0] avs_readdata,
    // Avalon-MM maestro hacia el Audio Core: 0x4 FIFOSPACE, 0x8 LEFTDATA, 0xC RIGHTDATA
    output reg  [3:0]  avm_address,
    output reg         avm_read,
    output reg         avm_write,
    output reg  [31:0] avm_writedata,
    input  wire [31:0] avm_readdata,
    input  wire        avm_waitrequest,
    // Conduits
    input  wire [1:0]  coe_sw,
    output reg  [6:0]  coe_hex0,
    output reg  [6:0]  coe_hex1,
    output reg  [6:0]  coe_hex2,
    output reg  [6:0]  coe_hex3,
    output reg  [6:0]  coe_hex4,
    output reg  [6:0]  coe_hex5
);
    localparam [31:0] ID_VALUE = 32'h41554450;
    localparam [31:0] DEPTH    = 32'd1 << FIFO_AW;

    localparam [3:0] A_ID = 4'h0, A_CTRL = 4'h1, A_STATUS = 4'h2, A_SPACE = 4'h3,
                     A_DATA = 4'h4, A_VOL = 4'h5, A_PLAYED = 4'h6, A_TIME = 4'h7,
                     A_TRACK = 4'h8, A_UNDER = 4'h9, A_CADDR = 4'hA, A_CDATA = 4'hB,
                     A_OVER = 4'hC, A_DEPTH = 4'hD;

    // ---------------------------------------------------------------- registros
    reg        ctrl_run;
    reg        ctrl_sel_src;
    reg [1:0]  ctrl_filter;
    reg        ctrl_hex_en;
    reg [15:0] volume;
    reg [6:0]  track;
    reg [8:0]  coef_addr;

    wire wr_ctrl  = avs_write && (avs_address == A_CTRL);
    wire flush    = wr_ctrl && avs_writedata[1];
    wire time_clr = wr_ctrl && avs_writedata[2];
    wire wr_data  = avs_write && (avs_address == A_DATA);
    wire coef_we  = avs_write && (avs_address == A_CDATA);

    always @(posedge clk) begin
        if (reset) begin
            ctrl_run     <= 1'b0;
            ctrl_sel_src <= 1'b0;
            ctrl_filter  <= 2'd0;
            ctrl_hex_en  <= 1'b1;
            volume       <= 16'h8000;
            track        <= 7'd0;
            coef_addr    <= 9'd0;
        end else if (avs_write) begin
            case (avs_address)
                A_CTRL: begin
                    ctrl_run     <= avs_writedata[0];
                    ctrl_sel_src <= avs_writedata[3];
                    ctrl_filter  <= avs_writedata[5:4];
                    ctrl_hex_en  <= avs_writedata[8];
                end
                A_VOL:   volume    <= avs_writedata[15:0];
                A_TRACK: track     <= avs_writedata[6:0];
                A_CADDR: coef_addr <= avs_writedata[8:0];
                A_CDATA: coef_addr <= coef_addr + 1'b1;
                default: ;
            endcase
        end
    end

    // Switches de la placa: sincronizacion a clk
    reg [1:0] sw_meta, sw_sync;
    always @(posedge clk) begin
        sw_meta <= coe_sw;
        sw_sync <= sw_meta;
    end
    wire [1:0] active_filter = ctrl_sel_src ? ctrl_filter : sw_sync;

    // ---------------------------------------------------------------- FIFO
    wire [31:0]       fifo_q;
    wire [FIFO_AW:0]  fifo_count;
    wire              fifo_empty, fifo_full;
    wire              pop;

    audio_proc_fifo #(.W(32), .AW(FIFO_AW)) u_fifo (
        .clk(clk), .reset(reset), .flush(flush),
        .wr_en(wr_data), .wr_data(avs_writedata),
        .rd_en(pop), .rd_data(fifo_q),
        .count(fifo_count), .empty(fifo_empty), .full(fifo_full)
    );

    // ---------------------------------------------------------------- motor DSP
    localparam [1:0] E_IDLE = 2'd0, E_LOAD = 2'd1, E_WAIT = 2'd2;
    reg  [1:0]  eng;
    wire        fir_busy, fir_done;
    wire [15:0] fir_l, fir_r;

    reg  [15:0] l_data, r_data;
    reg         out_valid;
    reg         w_busy;
    wire        take = out_valid && !w_busy;

    assign pop = (eng == E_IDLE) && ctrl_run && !fifo_empty && !out_valid && !fir_busy && !flush;

    audio_proc_fir #(.TAP_AW(7)) u_fir (
        .clk(clk), .reset(reset), .clear(flush),
        .start(eng == E_LOAD),
        .in_l(fifo_q[31:16]), .in_r(fifo_q[15:0]),
        .sel(active_filter), .volume(volume),
        .coef_we(coef_we), .coef_waddr(coef_addr), .coef_wdata(avs_writedata[15:0]),
        .busy(fir_busy), .done(fir_done), .out_l(fir_l), .out_r(fir_r)
    );

    always @(posedge clk) begin
        if (reset || flush) begin
            eng       <= E_IDLE;
            out_valid <= 1'b0;
        end else begin
            if (take)
                out_valid <= 1'b0;
            case (eng)
                E_IDLE: if (pop) eng <= E_LOAD;
                E_LOAD: eng <= E_WAIT;
                E_WAIT: if (fir_done) begin
                    l_data    <= fir_l;
                    r_data    <= fir_r;
                    out_valid <= 1'b1;
                    eng       <= E_IDLE;
                end
                default: eng <= E_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------- escritor al Audio Core
    // Lee FIFOSPACE, toma como credito el minimo de espacio libre de ambos canales y escribe
    // izquierda y derecha por cada muestra. Un par iniciado siempre se completa (FLUSH no lo
    // interrumpe) para no desalinear los canales del Audio Core.
    localparam [2:0] W_IDLE = 3'd0, W_RD = 3'd1, W_WL = 3'd2, W_WR = 3'd3, W_BACKOFF = 3'd4;
    localparam [3:0] AC_FIFOSPACE = 4'h4, AC_LEFT = 4'h8, AC_RIGHT = 4'hC;

    reg [2:0]  wst;
    reg [15:0] w_l, w_r;
    reg [7:0]  credits;
    reg [7:0]  backoff;
    reg        sample_done;
    wire [7:0] wslc = avm_readdata[31:24];
    wire [7:0] wsrc = avm_readdata[23:16];

    always @(posedge clk) begin
        sample_done <= 1'b0;
        if (reset) begin
            wst         <= W_IDLE;
            w_busy      <= 1'b0;
            credits     <= 8'd0;
            backoff     <= 8'd0;
            avm_read    <= 1'b0;
            avm_write   <= 1'b0;
            avm_address <= 4'h0;
        end else begin
            if (take) begin
                w_l    <= l_data;
                w_r    <= r_data;
                w_busy <= 1'b1;
            end
            case (wst)
                W_IDLE: begin
                    if (w_busy) begin
                        if (credits != 8'd0) begin
                            avm_address   <= AC_LEFT;
                            avm_writedata <= {w_l, 16'h0000};
                            avm_write     <= 1'b1;
                            wst           <= W_WL;
                        end else begin
                            avm_address <= AC_FIFOSPACE;
                            avm_read    <= 1'b1;
                            wst         <= W_RD;
                        end
                    end
                end
                W_RD: begin
                    if (!avm_waitrequest) begin
                        avm_read <= 1'b0;
                        credits  <= (wslc < wsrc) ? wslc : wsrc;
                        backoff  <= 8'd255;
                        wst      <= ((wslc < wsrc ? wslc : wsrc) == 8'd0) ? W_BACKOFF : W_IDLE;
                    end
                end
                W_BACKOFF: begin
                    backoff <= backoff - 1'b1;
                    if (backoff == 8'd0)
                        wst <= W_IDLE;
                end
                W_WL: begin
                    if (!avm_waitrequest) begin
                        avm_address   <= AC_RIGHT;
                        avm_writedata <= {w_r, 16'h0000};
                        wst           <= W_WR;
                    end
                end
                W_WR: begin
                    if (!avm_waitrequest) begin
                        avm_write   <= 1'b0;
                        credits     <= credits - 1'b1;
                        w_busy      <= 1'b0;
                        sample_done <= 1'b1;
                        wst         <= W_IDLE;
                    end
                end
                default: wst <= W_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------- tiempo y estadisticas
    reg [31:0] played, underrun, overflow;
    reg [23:0] fs_div;
    reg [3:0]  sec0, sec1, min0, min1;
    reg        starve_d;

    wire starve = ctrl_run && fifo_empty && (eng == E_IDLE) && !out_valid && !w_busy;

    always @(posedge clk) begin
        if (reset || time_clr) begin
            played   <= 32'd0;
            underrun <= 32'd0;
            overflow <= 32'd0;
            fs_div   <= 24'd0;
            sec0 <= 4'd0; sec1 <= 4'd0; min0 <= 4'd0; min1 <= 4'd0;
            starve_d <= 1'b0;
        end else begin
            starve_d <= starve;
            if (starve && !starve_d)
                underrun <= underrun + 1'b1;
            if (wr_data && fifo_full)
                overflow <= overflow + 1'b1;
            if (sample_done) begin
                played <= played + 1'b1;
                if (fs_div == FS_HZ - 1) begin
                    fs_div <= 24'd0;
                    if (sec0 == 4'd9) begin
                        sec0 <= 4'd0;
                        if (sec1 == 4'd5) begin
                            sec1 <= 4'd0;
                            if (min0 == 4'd9) begin
                                min0 <= 4'd0;
                                min1 <= (min1 == 4'd9) ? 4'd0 : min1 + 1'b1;
                            end else begin
                                min0 <= min0 + 1'b1;
                            end
                        end else begin
                            sec1 <= sec1 + 1'b1;
                        end
                    end else begin
                        sec0 <= sec0 + 1'b1;
                    end
                end else begin
                    fs_div <= fs_div + 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------- 7 segmentos
    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'd0: seg7 = 7'b1000000;
                4'd1: seg7 = 7'b1111001;
                4'd2: seg7 = 7'b0100100;
                4'd3: seg7 = 7'b0110000;
                4'd4: seg7 = 7'b0011001;
                4'd5: seg7 = 7'b0010010;
                4'd6: seg7 = 7'b0000010;
                4'd7: seg7 = 7'b1111000;
                4'd8: seg7 = 7'b0000000;
                4'd9: seg7 = 7'b0010000;
                default: seg7 = 7'b1111111;
            endcase
        end
    endfunction

    localparam [6:0] SEG_OFF = 7'b1111111;
    wire [6:0] trk      = (track > 7'd99) ? 7'd99 : track;
    wire [3:0] trk_tens = trk / 7'd10;
    wire [3:0] trk_ones = trk % 7'd10;
    wire       trk_on   = ctrl_hex_en && (trk != 7'd0);

    always @(posedge clk) begin
        coe_hex0 <= ctrl_hex_en ? seg7(sec0) : SEG_OFF;
        coe_hex1 <= ctrl_hex_en ? seg7(sec1) : SEG_OFF;
        coe_hex2 <= ctrl_hex_en ? seg7(min0) : SEG_OFF;
        coe_hex3 <= ctrl_hex_en ? seg7(min1) : SEG_OFF;
        coe_hex4 <= trk_on ? seg7(trk_ones) : SEG_OFF;
        coe_hex5 <= trk_on ? seg7(trk_tens) : SEG_OFF;
    end

    // ---------------------------------------------------------------- lectura
    always @(posedge clk) begin
        case (avs_address)
            A_ID:     avs_readdata <= ID_VALUE;
            A_CTRL:   avs_readdata <= {23'd0, ctrl_hex_en, 2'd0, ctrl_filter, ctrl_sel_src, 2'd0, ctrl_run};
            A_STATUS: avs_readdata <= {22'd0, sw_sync, 2'd0, fir_busy, ctrl_run, fifo_full, fifo_empty, active_filter};
            A_SPACE:  avs_readdata <= DEPTH - {{(31-FIFO_AW){1'b0}}, fifo_count};
            A_VOL:    avs_readdata <= {16'd0, volume};
            A_PLAYED: avs_readdata <= played;
            A_TIME:   avs_readdata <= {16'd0, min1, min0, sec1, sec0};
            A_TRACK:  avs_readdata <= {25'd0, track};
            A_UNDER:  avs_readdata <= underrun;
            A_CADDR:  avs_readdata <= {23'd0, coef_addr};
            A_OVER:   avs_readdata <= overflow;
            A_DEPTH:  avs_readdata <= DEPTH;
            default:  avs_readdata <= 32'd0;
        endcase
    end
endmodule
