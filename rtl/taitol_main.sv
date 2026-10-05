// The TC0090LVC's CPU half: a Z80 (tv80) with the chip's own registers and memory map, and the external bus
// for the board (MAME: tc0090lvc_device::cpu_map + taitol_state::common_banks_map).
//
//   0000-5FFF  program ROM, fixed
//   6000-7FFF  program ROM, 8 KB window: ((rom_bank << 13) | offset) & (ROM size - 1)
//   8000-BFFF  the board (ext_*): work RAM, sound, I/O, shared RAM ...
//   C000-FDFF  4 windows of 4 KB onto the chip's VRAM space: address = (ram_bank[slot] << 12) | offset
//   FE00-FEFF  video registers (0-3: tile bank slots, 4: [5] screen enable [4] flip [3] BG0 priority)
//   FF00-FF02  interrupt vectors, levels 0-2        FF03  interrupt enable (bit n: level n)
//   FF04-FF07  ram_bank[0..3]                       FF08  rom_bank        (FFx0-FFx8 mirrored every 16 bytes)
//
// Interrupts: IM 2. Three levels, fired at raster lines 120 (level 0), 0 (level 1) and 240 (level 2, vblank) when the
// level's enable bit is set (MAME does the same from a scanline timer; the real sources of 0 and 1 are unknown). The
// vector byte is irq_vector[level of the last interrupt]; the acknowledge cycle drops the request, and clearing the
// enable bit of the pending level drops it too. As in MAME, nothing fires while the Z80 is not in IM 2 (Play Girls enables
// interrupts before it selects the mode).
`default_nettype none
module taitol_main (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen,                  // 6.66528 MHz

    // program ROM (through the cache)
    output logic        rom_rd,
    output logic [19:0] rom_addr,
    input  logic        rom_hit,
    input  logic [7:0]  rom_q,
    input  logic [19:0] rom_mask,
    input  logic        rom_bitrev,                // the program ROM holds bit-reversed bytes (plottinga: MAME's init_plottinga)

    // the board's window, 8000-BFFF
    output logic        ext_rd,
    output logic        ext_wr,
    output logic [15:0] ext_a,
    output logic [7:0]  ext_wdata,
    input  logic [7:0]  ext_rdata,

    // the chip's VRAM space
    output logic [19:0] v_addr,
    output logic        v_we,
    output logic [7:0]  v_wdata,
    input  logic [7:0]  v_rdata,

    // video registers
    output logic [7:0]  vreg4,
    output logic [31:0] tbank,

    // raster events
    input  logic        ls_pulse,
    input  logic [8:0]  ln_new,

    // debug
    output logic        dbg_irq,
    output logic        dbg_m1
);
    // ---------------------------------------------------------------- Z80
    logic        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    logic [15:0] A;
    logic  [7:0] di, dout;
    logic        irq_pend;
    logic        wait_n;
    logic  [1:0] z80_im;

    tv80s_cen u_z80 (
        .reset_n(~rst), .clk(clk), .cen(cen), .wait_n(wait_n), .int_n(~irq_pend), .nmi_n(1'b1), .busrq_n(1'b1),
        .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(A), .di(di), .dout(dout), .im(z80_im)
    );
    wire mem_rd = ~mreq_n & ~rd_n;
    wire mem_wr = ~mreq_n & ~wr_n;
    wire inta   = ~iorq_n & ~m1_n;
    assign dbg_m1 = ~m1_n & ~mreq_n;

    // ---------------------------------------------------------------- address decode
    wire a_rom_fix  = (A[15:13] == 3'b000) || (A[15:13] == 3'b001) || (A[15:13] == 3'b010);   // 0000-5FFF
    wire a_rom_bank = (A[15:13] == 3'b011);                                                    // 6000-7FFF
    wire a_ext      = (A[15:14] == 2'b10);                                                     // 8000-BFFF
    wire a_win      = (A[15:14] == 2'b11) && !(A[13:9] == 5'b11111);                           // C000-FDFF
    wire a_vreg     = (A[15:8] == 8'hFE);
    wire a_chip     = (A[15:8] == 8'hFF);

    // ---------------------------------------------------------------- chip registers
    logic [7:0] irq_vec [3];
    logic [7:0] irq_en;
    logic [7:0] ram_bank [4];
    logic [7:0] rom_bank;
    logic [7:0] vr [8];                         // video registers 0..7 (0-4 used)
    wire        wr_chip = mem_wr & a_chip;
    wire        wr_vreg = mem_wr & a_vreg;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 3; i++) irq_vec[i] <= 8'h00;
            irq_en <= 8'h00;
            for (int i = 0; i < 4; i++) ram_bank[i] <= 8'h80;
            rom_bank <= 8'h00;
            for (int i = 0; i < 8; i++) vr[i] <= 8'h00;
        end else begin
            if (wr_chip) begin
                case (A[3:0])
                    4'h0, 4'h1, 4'h2: irq_vec[A[1:0]] <= dout;
                    4'h3: irq_en <= dout;
                    4'h4, 4'h5, 4'h6, 4'h7: ram_bank[A[1:0]] <= dout;
                    4'h8: rom_bank <= dout;
                    default: ;
                endcase
            end
            if (wr_vreg && A[7:3] == 5'd0) vr[A[2:0]] <= dout;
        end
    end
    assign vreg4 = vr[4];
    assign tbank = {vr[3], vr[2], vr[1], vr[0]};

    // the rest of the video register file (8..FF) is plain RAM
    logic [7:0] vrx_q;
    taitol_ram8 #(.AW(8)) u_vrx (.clk(clk), .we(wr_vreg), .addr(A[7:0]), .d(dout), .q(vrx_q));

    // ---------------------------------------------------------------- interrupts
    logic [1:0] last_lvl;
    logic       inta_d;
    wire  [7:0] en_new = dout;
    always_ff @(posedge clk) begin
        inta_d <= inta;
        if (rst) begin
            irq_pend <= 1'b0; last_lvl <= 2'd0;
        end else begin
            if (ls_pulse && z80_im == 2'd2) begin       // MAME's "kludge to make plgirls boot": no interrupt while the Z80 is not in IM 2
                if      (ln_new == 9'd120 && irq_en[0]) begin last_lvl <= 2'd0; irq_pend <= 1'b1; end
                else if (ln_new == 9'd0   && irq_en[1]) begin last_lvl <= 2'd1; irq_pend <= 1'b1; end
                else if (ln_new == 9'd240 && irq_en[2]) begin last_lvl <= 2'd2; irq_pend <= 1'b1; end
            end
            if (inta && !inta_d) irq_pend <= 1'b0;
            if (wr_chip && A[3:0] == 4'h3 && ((en_new >> last_lvl) & 8'd1) == 8'd0) irq_pend <= 1'b0;
        end
    end
    assign dbg_irq = irq_pend;

    // ---------------------------------------------------------------- program ROM
    assign rom_rd   = mem_rd && (a_rom_fix || a_rom_bank);
    assign rom_addr = (a_rom_bank ? {rom_bank[6:0], A[12:0]} : {4'b0000, A}) & rom_mask;
    assign wait_n   = ~(rom_rd & ~rom_hit);

    // ---------------------------------------------------------------- the board and the VRAM window
    assign ext_rd    = mem_rd & a_ext;
    assign ext_wr    = mem_wr & a_ext;
    assign ext_a     = A;
    assign ext_wdata = dout;
    assign v_addr    = {ram_bank[A[13:12]], A[11:0]};
    assign v_we      = mem_wr & a_win;
    assign v_wdata   = dout;

    // ---------------------------------------------------------------- data bus
    logic [7:0] chip_q;
    always_comb begin
        chip_q = 8'h00;
        case (A[3:0])
            4'h0, 4'h1, 4'h2: chip_q = irq_vec[A[1:0]];
            4'h3: chip_q = irq_en;
            4'h4, 4'h5, 4'h6, 4'h7: chip_q = ram_bank[A[1:0]];
            4'h8: chip_q = rom_bank;
            default: ;
        endcase
    end
    always_comb begin
        di = 8'h00;
        if (inta)                       di = irq_vec[last_lvl];
        else if (a_rom_fix || a_rom_bank) di = rom_bitrev ? {rom_q[0], rom_q[1], rom_q[2], rom_q[3], rom_q[4], rom_q[5], rom_q[6], rom_q[7]} : rom_q;
        else if (a_ext)                 di = ext_rdata;
        else if (a_win)                 di = v_rdata;
        else if (a_vreg)                di = (A[7:3] == 5'd0) ? vr[A[2:0]] : vrx_q;
        else if (a_chip)                di = chip_q;
    end
endmodule
`default_nettype wire
