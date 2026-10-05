// The second Z80 of the 2-CPU boards (Kuri Kinton = board 5, Evil Stone = board 6): the sound CPU. MAME: kurikint_2_map /
// evilston_2_map and the "audiocpu" of kurikint() / evilston().
//
//   0000-7FFF (Kuri Kinton) / 0000-BFFF (Evil Stone)   ROM      (BRAM, loaded from the image's audiocpu region)
//   C000-DFFF                                          RAM, 8 KB
//   E000-E7FF                                          MB8421 dual-port RAM, left port (the main CPU has the right port at A000-A7FF)
//   E800-E801                                          YM2203 (the board's jt03: the bus is handed up)
//
// Clock 12 MHz / 3 = 4 MHz (cen). The interrupt is MAME's irq0_line_hold at the start of vblank: held until acknowledged;
// the acknowledge cycle supplies FF (RST 38 / IM 1).
`default_nettype none
module taitol_sub (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen,                  // 4 MHz
    input  logic        big_rom,              // Evil Stone: ROM up to BFFF
    input  logic        vbl_pulse,            // start of vblank

    // the ROM as the loader streams it
    input  logic        rom_we,
    input  logic [15:0] rom_waddr,
    input  logic [7:0]  rom_wdata,

    // dual-port RAM, left port
    output logic [10:0] dp_addr,
    output logic        dp_we,
    output logic [7:0]  dp_wdata,
    input  logic [7:0]  dp_q,

    // YM2203
    output logic        ym_sel,               // the CPU addresses E800-E801
    output logic        ym_rd,
    output logic        ym_wr,
    output logic        ym_a0,
    output logic [7:0]  ym_wdata,
    input  logic [7:0]  ym_q
);
    logic        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    logic [15:0] A;
    logic  [7:0] di, dout;
    logic        irq_pend = 1'b0;

    tv80s_cen u_z80 (
        .reset_n(~rst), .clk(clk), .cen(cen), .wait_n(1'b1), .int_n(~irq_pend), .nmi_n(1'b1), .busrq_n(1'b1),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(A), .di(di), .dout(dout), .im()
    );
    wire mem_rd = ~mreq_n & ~rd_n;
    wire mem_wr = ~mreq_n & ~wr_n;
    wire inta   = ~iorq_n & ~m1_n;

    // ---------------------------------------------------------------- interrupt
    logic inta_d;
    always_ff @(posedge clk) begin
        inta_d <= inta;
        if (rst) irq_pend <= 1'b0;
        else begin
            if (vbl_pulse) irq_pend <= 1'b1;
            if (inta && !inta_d) irq_pend <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- memories
    wire a_rom = big_rom ? (A[15:14] != 2'b11) : (A[15] == 1'b0);
    wire a_ram = (A[15:13] == 3'b110);
    wire a_dp  = (A[15:11] == 5'b11100);
    wire a_ym  = (A[15:1] == 15'h7400);

    logic [7:0] rom_q, ram_q;
    taitol_ram8 #(.AW(16)) u_rom (.clk(clk), .we(rom_we), .addr(rom_we ? rom_waddr : A), .d(rom_wdata), .q(rom_q));
    taitol_ram8 #(.AW(13)) u_ram (.clk(clk), .we(mem_wr & a_ram), .addr(A[12:0]), .d(dout), .q(ram_q));

    assign dp_addr  = A[10:0];
    assign dp_we    = mem_wr & a_dp;
    assign dp_wdata = dout;
    assign ym_sel   = a_ym;
    assign ym_rd    = mem_rd & a_ym;
    assign ym_wr    = mem_wr & a_ym;
    assign ym_a0    = A[0];
    assign ym_wdata = dout;

    always_comb begin
        di = 8'h00;
        if (inta)          di = 8'hFF;
        else if (a_rom)    di = rom_q;
        else if (a_ram)    di = ram_q;
        else if (a_dp)     di = dp_q;
        else if (a_ym)     di = ym_q;
    end
endmodule
`default_nettype wire
