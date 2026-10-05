// Board-level bench: taitol_board alone, driven like the Z80 drives it (write strobes of ~14 clocks), to check the YM2203
// path in isolation: reset, enable clock, the I/O mux reads, and that a programmed tone comes out.
`default_nettype none
module tb_board_top (
    input  logic clk,
    output logic signed [15:0] snd,
    output logic snd_sample,
    output logic [7:0] rd_data
);
    logic rst = 1'b1;
    logic ext_rd = 1'b0, ext_wr = 1'b0;
    logic [15:0] ext_a = 16'h0;
    logic [7:0]  ext_wdata = 8'h0;
    logic [7:0]  ext_rdata;
    logic [7:0] dswa = 8'hA5, dswb = 8'h5A, in0 = 8'h3C, in1 = 8'hC3;

    // the same clock enable as the machine's: 6.66528 MHz / 2 = 3.33264 MHz
    logic cen_cpu, cen_ym1, cen_z80b, cen_ym2, cen_ym2610;
    taitol_cen u_cen (.clk(clk), .cen_cpu(cen_cpu), .cen_ym1(cen_ym1), .cen_z80b(cen_z80b), .cen_ym2(cen_ym2), .cen_ym2610(cen_ym2610));

    taitol_board u_board (
        .clk(clk), .rst(rst), .cen_ym(cen_ym1), .board(4'd0),
        .ext_rd(ext_rd), .ext_wr(ext_wr), .ext_a(ext_a), .ext_wdata(ext_wdata), .ext_rdata(ext_rdata),
        .dswa(dswa), .dswb(dswb), .in0(in0), .in1(in1),
        .snd(snd), .snd_sample(snd_sample), .dbg_ym_wr()
    );
    assign rd_data = ext_rdata;

    export "DPI-C" function tb_rst;
    function void tb_rst(input int r); rst = r[0]; endfunction
    export "DPI-C" function tb_bus;
    function void tb_bus(input int rd, input int wr, input int a, input int d);
        ext_rd = rd[0]; ext_wr = wr[0]; ext_a = a[15:0]; ext_wdata = d[7:0];
    endfunction
endmodule
`default_nettype wire
