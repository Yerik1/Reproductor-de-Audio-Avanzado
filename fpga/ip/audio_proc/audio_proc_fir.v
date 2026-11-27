// Motor FIR secuencial estereo de 128 posiciones con 4 bancos de coeficientes Q1.15.
// Un multiplicador por canal; ~135 ciclos de reloj por muestra estereo.
//   sel = 0      : bypass (sin filtrado), solo volumen
//   sel = 1..3   : y[n] = sat16(round(sum_k h_sel[k] * x[n-k] / 2^15))
// Volumen: z = sat16(round(y * volume / 2^15)), volume = 0x8000 equivale a 1.0
`timescale 1ns/1ps
module audio_proc_fir #(
    parameter TAP_AW = 7
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 clear,
    input  wire                 start,
    input  wire signed [15:0]   in_l,
    input  wire signed [15:0]   in_r,
    input  wire [1:0]           sel,
    input  wire [15:0]          volume,
    input  wire                 coef_we,
    input  wire [TAP_AW+1:0]    coef_waddr,
    input  wire [15:0]          coef_wdata,
    output wire                 busy,
    output reg                  done,
    output reg  signed [15:0]   out_l,
    output reg  signed [15:0]   out_r
);
    localparam NT = 1 << TAP_AW;

    localparam [2:0] S_CLEAR = 3'd0,
                     S_IDLE  = 3'd1,
                     S_MAC   = 3'd2,
                     S_DRAIN = 3'd3,
                     S_SCALE = 3'd4,
                     S_VOL   = 3'd5,
                     S_OUT   = 3'd6;

    reg [2:0]        state;
    reg [TAP_AW-1:0] wp;
    reg [TAP_AW-1:0] k;
    reg [TAP_AW-1:0] clr_idx;
    reg [1:0]        bank;

    reg signed [15:0] hist_l   [0:NT-1];
    reg signed [15:0] hist_r   [0:NT-1];
    reg signed [15:0] coef_mem [0:4*NT-1];

    initial begin
`include "audio_proc_coefs.vh"
    end

    assign busy = (state != S_IDLE);

    // Puerto de escritura del historial: borrado o muestra nueva
    wire                hist_we    = (state == S_CLEAR) || ((state == S_IDLE) && start);
    wire [TAP_AW-1:0]   hist_waddr = (state == S_CLEAR) ? clr_idx : wp + 1'b1;
    wire signed [15:0]  hist_wl    = (state == S_CLEAR) ? 16'sd0 : in_l;
    wire signed [15:0]  hist_wr    = (state == S_CLEAR) ? 16'sd0 : in_r;

    always @(posedge clk) begin
        if (hist_we) begin
            hist_l[hist_waddr] <= hist_wl;
            hist_r[hist_waddr] <= hist_wr;
        end
    end

    always @(posedge clk) begin
        if (coef_we)
            coef_mem[coef_waddr] <= coef_wdata;
    end

    // Lectura registrada de historial y coeficientes
    wire [TAP_AW-1:0] rd_h = wp - k;
    wire [TAP_AW+1:0] rd_c = {bank, k};
    reg signed [15:0] hl_q, hr_q, c_q;

    always @(posedge clk) begin
        hl_q <= hist_l[rd_h];
        hr_q <= hist_r[rd_h];
        c_q  <= coef_mem[rd_c];
    end

    // Pipeline: lectura (v1) -> producto (v2) -> acumulacion
    reg               v1, v2;
    reg signed [31:0] p_l, p_r;
    reg signed [39:0] acc_l, acc_r;

    always @(posedge clk) begin
        if (reset) begin
            v1 <= 1'b0;
            v2 <= 1'b0;
        end else begin
            v1 <= (state == S_MAC);
            v2 <= v1;
        end
        p_l <= hl_q * c_q;
        p_r <= hr_q * c_q;
    end

    function signed [15:0] sat16;
        input signed [40:0] v;
        begin
            if (v > 41'sd32767)
                sat16 = 16'sd32767;
            else if (v < -41'sd32768)
                sat16 = -16'sd32768;
            else
                sat16 = v[15:0];
        end
    endfunction

    reg signed [15:0] y_l, y_r;
    reg signed [32:0] pv_l, pv_r;
    wire signed [32:0] vol_s = {17'd0, volume};

    always @(posedge clk) begin
        done <= 1'b0;
        if (reset) begin
            state   <= S_CLEAR;
            clr_idx <= {TAP_AW{1'b0}};
            wp      <= {TAP_AW{1'b0}};
            k       <= {TAP_AW{1'b0}};
            bank    <= 2'd0;
        end else if (clear) begin
            state   <= S_CLEAR;
            clr_idx <= {TAP_AW{1'b0}};
            wp      <= {TAP_AW{1'b0}};
        end else begin
            if (v2) begin
                acc_l <= acc_l + p_l;
                acc_r <= acc_r + p_r;
            end
            case (state)
                S_CLEAR: begin
                    clr_idx <= clr_idx + 1'b1;
                    if (clr_idx == NT-1)
                        state <= S_IDLE;
                end
                S_IDLE: begin
                    if (start) begin
                        wp    <= wp + 1'b1;
                        bank  <= sel;
                        k     <= {TAP_AW{1'b0}};
                        acc_l <= 40'sd0;
                        acc_r <= 40'sd0;
                        if (sel == 2'd0) begin
                            y_l   <= in_l;
                            y_r   <= in_r;
                            state <= S_VOL;
                        end else begin
                            state <= S_MAC;
                        end
                    end
                end
                S_MAC: begin
                    k <= k + 1'b1;
                    if (k == NT-1)
                        state <= S_DRAIN;
                end
                S_DRAIN: begin
                    if (!v1 && !v2)
                        state <= S_SCALE;
                end
                S_SCALE: begin
                    y_l   <= sat16((acc_l + 40'sd16384) >>> 15);
                    y_r   <= sat16((acc_r + 40'sd16384) >>> 15);
                    state <= S_VOL;
                end
                S_VOL: begin
                    pv_l  <= y_l * vol_s;
                    pv_r  <= y_r * vol_s;
                    state <= S_OUT;
                end
                S_OUT: begin
                    out_l <= sat16((pv_l + 33'sd16384) >>> 15);
                    out_r <= sat16((pv_r + 33'sd16384) >>> 15);
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
