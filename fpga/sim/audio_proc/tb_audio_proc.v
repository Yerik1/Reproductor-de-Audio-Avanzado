// Testbench autoverificable de audio_proc (verificacion aislada, FPGA-04).
// Ejercita el modulo solo a traves de sus registros Avalon-MM, como lo haria el
// software, modela el Audio Core (registros FIFOSPACE/LEFTDATA/RIGHTDATA con FIFOs de
// 128 muestras y waitrequest aleatorio) y compara las muestras escritas en el contra el
// modelo de referencia bit-exacto de tools/gen_vectors.py.
`timescale 1ns/1ps
module tb_audio_proc;
    localparam FIFO_AW = 6;
    localparam DEPTH   = 1 << FIFO_AW;
    localparam FS_HZ   = 8;
    localparam N       = 1024;
    localparam PRELOAD = 32;

    localparam [3:0] R_ID = 0, R_CTRL = 1, R_STATUS = 2, R_SPACE = 3, R_DATA = 4, R_VOL = 5,
                     R_PLAYED = 6, R_TIME = 7, R_TRACK = 8, R_UNDER = 9, R_CADDR = 10,
                     R_CDATA = 11, R_OVER = 12, R_DEPTH = 13;
    localparam [31:0] C_RUN = 32'h1, C_FLUSH = 32'h2, C_TCLR = 32'h4, C_SELSRC = 32'h8,
                      C_HEXEN = 32'h100;
    localparam [6:0]  SEG_OFF = 7'h7F;

    reg clk = 1'b0;
    reg reset = 1'b1;
    always #10 clk = ~clk;

    reg  [3:0]  address = 4'd0;
    reg         read = 1'b0, write = 1'b0;
    reg  [31:0] writedata = 32'd0;
    wire [31:0] readdata;
    wire [3:0]  m_address;
    wire        m_read, m_write;
    wire [31:0] m_writedata;
    reg  [31:0] m_readdata = 32'd0;
    wire        m_waitrequest;
    reg  [1:0]  sw = 2'd0;
    wire [6:0]  hex0, hex1, hex2, hex3, hex4, hex5;

    audio_proc #(.FIFO_AW(FIFO_AW), .FS_HZ(FS_HZ)) dut (
        .clk(clk), .reset(reset),
        .avs_address(address), .avs_read(read), .avs_write(write),
        .avs_writedata(writedata), .avs_readdata(readdata),
        .avm_address(m_address), .avm_read(m_read), .avm_write(m_write),
        .avm_writedata(m_writedata), .avm_readdata(m_readdata), .avm_waitrequest(m_waitrequest),
        .coe_sw(sw),
        .coe_hex0(hex0), .coe_hex1(hex1), .coe_hex2(hex2),
        .coe_hex3(hex3), .coe_hex4(hex4), .coe_hex5(hex5)
    );

    integer checks = 0, errors = 0, proto_err = 0;

    // ------------------------------------------------------------ bus Avalon-MM
    task bus_write(input [3:0] a, input [31:0] d);
        begin
            @(posedge clk);
            address <= a; writedata <= d; write <= 1'b1;
            @(posedge clk);
            write <= 1'b0;
        end
    endtask

    task bus_read(input [3:0] a, output [31:0] d);
        begin
            @(posedge clk);
            address <= a; read <= 1'b1;
            @(posedge clk);
            read <= 1'b0;
            @(posedge clk);
            d = readdata;
        end
    endtask

    task check(input [31:0] got, input [31:0] exp, input [8*48-1:0] what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FALLA] %0s: obtenido=0x%08h esperado=0x%08h", what, got, exp);
            end
        end
    endtask

    function [6:0] seg;
        input [3:0] d;
        begin
            case (d)
                0: seg = 7'h40; 1: seg = 7'h79; 2: seg = 7'h24; 3: seg = 7'h30; 4: seg = 7'h19;
                5: seg = 7'h12; 6: seg = 7'h02; 7: seg = 7'h78; 8: seg = 7'h00; 9: seg = 7'h10;
                default: seg = 7'h7F;
            endcase
        end
    endfunction

    // ------------------------------------------------------------ modelo del Audio Core
    // FIFOs de salida de 128 muestras por canal; el codec consume un par cada DRAIN ciclos.
    // waitrequest pseudoaleatorio; se verifica que el maestro mantenga sus senales durante
    // waitrequest, que escriba izquierda antes que derecha y que no desborde las FIFOs.
    localparam AC_DEPTH = 128;
    localparam DRAIN    = 300;
    reg  [15:0] lfsr = 16'hACE1;
    reg  [15:0] cap_l [0:N-1];
    reg  [15:0] cap_r [0:N-1];
    integer     cnt_l = 0, cnt_r = 0;
    integer     ac_l = 0, ac_r = 0, drain_cnt = 0, ac_full = 0;
    reg         cap_clr = 1'b0;
    reg         p_req = 1'b0;
    reg  [3:0]  p_addr;
    reg  [31:0] p_wdata;
    reg         p_rd, p_wr;

    assign m_waitrequest = (m_read || m_write) && lfsr[2] && lfsr[7];

    wire [7:0] ws_l = AC_DEPTH - ac_l;
    wire [7:0] ws_r = AC_DEPTH - ac_r;

    always @(*) begin
        m_readdata = 32'd0;
        if (m_address == 4'h4)
            m_readdata = {ws_l, ws_r, 16'd0};
    end

    always @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        if (!reset && p_req && (m_read !== p_rd || m_write !== p_wr || m_address !== p_addr ||
                      (p_wr && m_writedata !== p_wdata)))
            proto_err <= proto_err + 1;
        p_req <= (m_read || m_write) && m_waitrequest;
        p_rd <= m_read; p_wr <= m_write; p_addr <= m_address; p_wdata <= m_writedata;

        if (cap_clr) begin
            cnt_l <= 0;
            cnt_r <= 0;
        end else if (m_write && !m_waitrequest) begin
            if (m_writedata[15:0] !== 16'h0000) proto_err <= proto_err + 1;
            if (m_address == 4'h8) begin
                if (cnt_l != cnt_r || ac_l >= AC_DEPTH) proto_err <= proto_err + 1;
                if (cnt_l < N) cap_l[cnt_l] <= m_writedata[31:16];
                cnt_l <= cnt_l + 1;
            end else if (m_address == 4'hC) begin
                if (cnt_r != cnt_l - 1 || ac_r >= AC_DEPTH) proto_err <= proto_err + 1;
                if (cnt_r < N) cap_r[cnt_r] <= m_writedata[31:16];
                cnt_r <= cnt_r + 1;
            end else begin
                proto_err <= proto_err + 1;
            end
        end

        drain_cnt <= (drain_cnt == DRAIN - 1) ? 0 : drain_cnt + 1;
        if (ac_l == AC_DEPTH && ac_r == AC_DEPTH) ac_full <= ac_full + 1;
        if (reset) begin
            ac_l <= 0;
            ac_r <= 0;
        end else begin
            ac_l <= ac_l + ((m_write && !m_waitrequest && m_address == 4'h8) ? 1 : 0)
                         - ((drain_cnt == DRAIN - 1 && ac_l > 0 && ac_r > 0) ? 1 : 0);
            ac_r <= ac_r + ((m_write && !m_waitrequest && m_address == 4'hC) ? 1 : 0)
                         - ((drain_cnt == DRAIN - 1 && ac_l > 0 && ac_r > 0) ? 1 : 0);
        end
    end

    // ------------------------------------------------------------ caso de filtrado
    reg  [31:0] stim [0:N-1];
    reg  [31:0] expv [0:N-1];
    reg  [15:0] cprog [0:127];
    reg  [8*64-1:0] fname;
    reg  [31:0] rd;
    integer     i, mism, fout;

    task run_case(input integer id, input [31:0] ctrl_bits, input [15:0] vol, input [1:0] swv);
        integer sent, n, tout, secs;
        reg [15:0] bcd;
        begin
            $sformat(fname, "vectors/stim_%0d.hex", id);
            $readmemh(fname, stim);
            $sformat(fname, "vectors/exp_%0d.hex", id);
            $readmemh(fname, expv);
            sw = swv;
            bus_write(R_CTRL, C_FLUSH | C_TCLR | C_HEXEN | ctrl_bits);
            bus_write(R_VOL, {16'd0, vol});
            @(posedge clk) cap_clr <= 1'b1;
            @(posedge clk) cap_clr <= 1'b0;

            sent = 0;
            while (sent < PRELOAD) begin
                bus_write(R_DATA, stim[sent]);
                sent = sent + 1;
            end
            repeat (300) @(posedge clk);
            check(cnt_l, 0, "pausa: sin salida con RUN=0");
            bus_read(R_SPACE, rd);
            check(rd, DEPTH - PRELOAD, "pausa: FIFO_SPACE conservado");

            bus_write(R_CTRL, C_HEXEN | ctrl_bits | C_RUN);
            while (sent < N) begin
                bus_read(R_SPACE, rd);
                n = rd;
                while (n > 0 && sent < N) begin
                    bus_write(R_DATA, stim[sent]);
                    sent = sent + 1;
                    n = n - 1;
                end
            end
            tout = 0;
            while ((cnt_l < N || cnt_r < N) && tout < 2000000) begin
                @(posedge clk);
                tout = tout + 1;
            end
            repeat (10) @(posedge clk);

            mism = 0;
            for (i = 0; i < N; i = i + 1) begin
                if ({cap_l[i], cap_r[i]} !== expv[i]) begin
                    if (mism < 5)
                        $display("  [FALLA] caso %0d muestra %0d: obtenido=%04h%04h esperado=%08h",
                                 id, i, cap_l[i], cap_r[i], expv[i]);
                    mism = mism + 1;
                end
            end
            checks = checks + 1;
            if (mism != 0 || cnt_l != N || cnt_r != N) errors = errors + 1;

            secs = N / FS_HZ;
            bcd[15:12] = (secs / 60) / 10;
            bcd[11:8]  = (secs / 60) % 10;
            bcd[7:4]   = (secs % 60) / 10;
            bcd[3:0]   = (secs % 60) % 10;
            bus_read(R_PLAYED, rd); check(rd, N, "PLAYED");
            bus_read(R_TIME, rd);   check(rd, {16'd0, bcd}, "TIME (BCD MMSS)");
            check({hex3, hex2, hex1, hex0}, {seg(bcd[15:12]), seg(bcd[11:8]), seg(bcd[7:4]), seg(bcd[3:0])}, "HEX3..HEX0");
            bus_read(R_UNDER, rd);  check(rd, 1, "UNDERRUN al vaciarse");
            bus_read(R_STATUS, rd); check(rd[1:0], (ctrl_bits & C_SELSRC) ? ctrl_bits[5:4] : swv, "STATUS filtro activo");

            $display("caso %0d: %0d/%0d muestras coinciden, salida %0d/%0d, tiempo %02h:%02h",
                     id, N - mism, N, cnt_l, cnt_r, bcd[15:8], bcd[7:0]);
            $sformat(fname, "out/out_%0d.hex", id);
            fout = $fopen(fname, "w");
            for (i = 0; i < N; i = i + 1)
                $fdisplay(fout, "%04h%04h", cap_l[i], cap_r[i]);
            $fclose(fout);
        end
    endtask

    // ------------------------------------------------------------ secuencia principal
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_audio_proc.vcd");
            $dumpvars(0, tb_audio_proc);
        end
        $display("=== tb_audio_proc: FIFO_DEPTH=%0d FS_HZ=%0d N=%0d ===", DEPTH, FS_HZ, N);
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        repeat (200) @(posedge clk);

        $display("-- registros");
        bus_read(R_ID, rd);     check(rd, 32'h41554450, "ID");
        bus_read(R_DEPTH, rd);  check(rd, DEPTH, "FIFO_DEPTH");
        bus_read(R_CTRL, rd);   check(rd, C_HEXEN, "CTRL tras reset");
        bus_read(R_VOL, rd);    check(rd, 32'h8000, "VOLUME tras reset");
        bus_read(R_SPACE, rd);  check(rd, DEPTH, "FIFO_SPACE tras reset");

        $display("-- FIFO llena y OVERFLOW");
        bus_write(R_CTRL, C_FLUSH | C_TCLR | C_HEXEN);
        for (i = 0; i < DEPTH + 6; i = i + 1) bus_write(R_DATA, i);
        bus_read(R_SPACE, rd);  check(rd, 0, "FIFO_SPACE con FIFO llena");
        bus_read(R_STATUS, rd); check(rd[3:2], 2'b10, "STATUS llena/vacia");
        bus_read(R_OVER, rd);   check(rd, 6, "OVERFLOW");
        bus_write(R_CTRL, C_FLUSH | C_HEXEN);
        bus_read(R_SPACE, rd);  check(rd, DEPTH, "FIFO_SPACE tras FLUSH");
        bus_read(R_STATUS, rd); check(rd[3:2], 2'b01, "STATUS vacia tras FLUSH");

        $display("-- pista en HEX5..HEX4 y HEX_EN");
        bus_write(R_TRACK, 7);  repeat (2) @(posedge clk);
        check({hex5, hex4}, {seg(0), seg(7)}, "TRACK=7");
        bus_write(R_TRACK, 42); repeat (2) @(posedge clk);
        check({hex5, hex4}, {seg(4), seg(2)}, "TRACK=42");
        bus_write(R_TRACK, 0);  repeat (2) @(posedge clk);
        check({hex5, hex4}, {SEG_OFF, SEG_OFF}, "TRACK=0 apagado");
        bus_write(R_TRACK, 3);
        bus_write(R_CTRL, 32'd0); repeat (2) @(posedge clk);
        check({hex5, hex4, hex3, hex2, hex1, hex0}, {6{SEG_OFF}}, "HEX_EN=0 apaga displays");

        $display("-- seleccion de filtro por switches");
        sw = 2'd3; bus_write(R_CTRL, C_HEXEN); repeat (3) @(posedge clk);
        bus_read(R_STATUS, rd); check({rd[9:8], rd[1:0]}, 4'b1111, "STATUS con SW=3");
        bus_write(R_CTRL, C_HEXEN | C_SELSRC | (1 << 4));
        bus_read(R_STATUS, rd); check(rd[1:0], 1, "STATUS con SEL_SRC=1, FILTER=1");

        $display("-- casos de filtrado");
        run_case(0, C_SELSRC | (0 << 4), 16'h8000, 2'd0);
        run_case(1, C_SELSRC | (1 << 4), 16'h8000, 2'd0);
        run_case(2, C_SELSRC | (2 << 4), 16'h8000, 2'd0);
        run_case(3, C_SELSRC | (3 << 4), 16'h8000, 2'd0);
        run_case(4, C_SELSRC | (1 << 4), 16'h4000, 2'd0);
        run_case(5, C_SELSRC | (0 << 4), 16'hFFFF, 2'd0);
        run_case(6, C_SELSRC | (1 << 4), 16'h8000, 2'd0);
        run_case(7, 32'd0,               16'h8000, 2'd2);

        $display("-- programacion de coeficientes (banco 3)");
        $readmemh("vectors/coef_prog.hex", cprog);
        bus_write(R_CADDR, 3 * 128);
        for (i = 0; i < 128; i = i + 1) bus_write(R_CDATA, {16'd0, cprog[i]});
        bus_read(R_CADDR, rd); check(rd, 0, "COEF_ADDR autoincremento");
        run_case(8, C_SELSRC | (3 << 4), 16'h8000, 2'd0);

        $display("-- ciclos con las FIFOs del Audio Core llenas (contrapresion ejercitada): %0d", ac_full);
        checks = checks + 1;
        if (ac_full == 0) errors = errors + 1;
        $display("=== RESUMEN: %0d verificaciones, %0d fallas, %0d errores de protocolo Avalon-MM del maestro ===",
                 checks, errors, proto_err);
        if (errors == 0 && proto_err == 0) $display("RESULTADO: PASS");
        else                               $display("RESULTADO: FAIL");
        $finish;
    end

    initial begin
        #500_000_000;
        $display("RESULTADO: FAIL (timeout global)");
        $finish;
    end
endmodule
