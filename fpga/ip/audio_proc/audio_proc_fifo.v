// FIFO sincronica de muestras estereo. Lectura registrada: rd_data es valido
// el ciclo siguiente a un rd_en aceptado.
`timescale 1ns/1ps
module audio_proc_fifo #(
    parameter W  = 32,
    parameter AW = 12
) (
    input  wire          clk,
    input  wire          reset,
    input  wire          flush,
    input  wire          wr_en,
    input  wire [W-1:0]  wr_data,
    input  wire          rd_en,
    output reg  [W-1:0]  rd_data,
    output wire [AW:0]   count,
    output wire          empty,
    output wire          full
);
    reg [W-1:0] mem [0:(1<<AW)-1];
    reg [AW:0]  wptr;
    reg [AW:0]  rptr;

    assign count = wptr - rptr;
    assign empty = (wptr == rptr);
    assign full  = (wptr[AW] != rptr[AW]) && (wptr[AW-1:0] == rptr[AW-1:0]);

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    always @(posedge clk) begin
        if (do_wr)
            mem[wptr[AW-1:0]] <= wr_data;
        if (do_rd)
            rd_data <= mem[rptr[AW-1:0]];
    end

    always @(posedge clk) begin
        if (reset || flush) begin
            wptr <= {(AW+1){1'b0}};
            rptr <= {(AW+1){1'b0}};
        end else begin
            if (do_wr) wptr <= wptr + 1'b1;
            if (do_rd) rptr <= rptr + 1'b1;
        end
    end
endmodule
