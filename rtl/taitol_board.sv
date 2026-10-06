// The board around the TC0090LVC: everything the chip maps into 8000-BFFF, per game family (MAME: taitol_1cpu_state
// and friends). Plotting / Flipull so far (the "1-CPU" board with the YM2203 and no extra chips):
//
//   8000-9FFF  work RAM
//   A000-A003  YM2203. The DIP switches and the inputs are read through its two I/O ports: two 74LS157 multiplexers
//              (DSWA|DSWB into port A, IN0|IN1 into port B) whose select line is bit 1 of the address of the last
//              read of A000-A003 (MAME: extport_select_and_ym2203_r). Reads of offset 0/1 give the status / data port.
//   A800, B800 write: watchdog / control, ignored
//
// The Palamedes family (board 3: Palamedes, Cachat, Tube-It, Cuby Bop, Play Girls ...) differs in the controls:
//   A000-A003 YM2203, its port A and B read DSWA and DSWB directly (no multiplexer),  A800-A803 an 8255 (IN0, IN1, IN2),
//   B000 write and B001 read: ignored (watchdog / acknowledge).
//
// Puzznic's family (board 2 = the three bootlegs without the MCU, 1 = the original with it) is the same board with
//   A800 read: watchdog (nothing),  B801 read: the MCU control port, which MAME answers with a constant 1,  BC00 write: ignored;
//   and on the original B800 reads/writes the MC68705 (taitol_mcu).
//
// The 2-CPU boards (5 = Kuri Kinton, 6 = Evil Stone) move the YM2203 to a second Z80 (taitol_sub); the main CPU has instead
//   A000-A7FF  MB8421 dual-port RAM, right port (the sub CPU has the left port at E000-E7FF)
//   A800-A801  TC0040IOC (Kuri Kinton): A801 write selects a register, A800 reads / writes it (0 DSWA, 1 DSWB, 2 IN0, 3 IN1,
//              4 coin lockout / counter latch, 7 IN2; others read FF);   A800-A807  TC0510NIO (Evil Stone): the same registers at
//              A800+n.
//
// The 3-CPU boards (7 = Fighting Hawk, 8 = Champion Wrestler, 9 = Raimais) add a slave and a sound Z80 (taitol_tri): the main
// CPU has a RAM it shares with the slave (7: 8000-9FFF, 8: A000-BFFF, 9: the MB8421 at 8000-87FF), a private RAM (7: A000-BFFF,
// 8: 8000-9FFF, 9: A000-BFFF) and on Raimais the TC0040IOC at 8800/8801 and the TC0140SYT at 8C00 (port) / 8C01 (communication).
// Raimais' sound chip is a YM2610 (jt10, 8 MHz) on the sound Z80's bus at E000-E003; its ADPCM-A samples come out of the SDRAM through
// the cache in taitol_tri.
//
// American Horseshoes (board 4) is the Plotting board plus a uPD4701A trackball counter at A800-A803 (taitol_upd4701) and a
// graphics bank register: a write to B802 ORs (data << 12) into the background tiles' codes and (data << 10) into the sprites'.
`default_nettype none
module taitol_board (
    input  logic        clk,
    input  logic        clk_ym,               // 48 MHz, in phase with clk: Raimais' YM2610
    input  logic        rst,
    input  logic        cen_ym,               // 3.33264 MHz
    input  logic        cen_mcu,              // 3.579545 MHz: Puzznic's MC68705
    input  logic        cen_ym2,              // 3 MHz: the YM2203 of the 2- and 3-CPU boards
    input  logic        cen_sub,              // 4 MHz: their second Z80
    input  logic        vbl_pulse,            // start of vblank (the sub CPU's interrupt)

    input  logic [3:0]  board,

    // the chip's external bus
    input  logic        ext_rd,
    input  logic        ext_wr,
    input  logic [15:0] ext_a,
    input  logic [7:0]  ext_wdata,
    output logic [7:0]  ext_rdata,

    // controls, active low (MAME's INPUT_PORTS bit order)
    input  logic [7:0]  dswa, dswb, in0, in1, in2,

    // the MC68705's program, as the loader writes it (Puzznic)
    input  logic        mcu_we,
    input  logic [10:0] mcu_waddr,
    input  logic [7:0]  mcu_wdata,

    // SDRAM line fills of the 3-CPU boards' slave and sound ROM caches
    input  logic        cache_inval,
    output logic        s_req,  output logic [16:4] s_addr,
    input  logic        s_wr,   input logic [2:0] s_idx, input logic [15:0] s_data, input logic s_done,
    output logic        a_req,  output logic [15:4] a_addr,
    input  logic        a_wr,   input logic [2:0] a_idx, input logic [15:0] a_data, input logic a_done,
    output logic        m_req,  output logic [18:4] m_addr,
    input  logic        m_wr,   input logic [2:0] m_idx, input logic [15:0] m_data, input logic m_done,

    // the sound / second Z80's ROM (the image's audiocpu region, first 64 KB)
    input  logic        sub_we,
    input  logic [15:0] sub_waddr,
    input  logic [7:0]  sub_wdata,

    // the trackball (Horseshoes): movement of the counters, and the tile graphics bank it writes
    input  logic        tb_add_x, tb_add_y,
    input  logic signed [8:0] tb_dx, tb_dy,
    output logic [7:0]  gbank,

    // sound
    output logic signed [15:0] snd,
    output logic        snd_sample,
    output logic        dbg_ym_wr,
    output logic        dbg_ym_a0,
    output logic        dbg_ym_a1,
    output logic  [8:0] dbg_pcm_max,
    output logic [7:0]  dbg_ym_d
);
    // ---------------------------------------------------------------- work RAM
    wire        is3cpu     = (board == 4'd7) || (board == 4'd8) || (board == 4'd9);
    wire        ram_hi  = (board == 4'd7) || (board == 4'd9);          // the private RAM is at A000-BFFF there
    wire        sel_ram = ram_hi ? (ext_a[15:13] == 3'b101) : (ext_a[15:13] == 3'b100);
    logic [7:0] ram_q;
    taitol_ram8 #(.AW(13)) u_ram (.clk(clk), .we(ext_wr & sel_ram), .addr(ext_a[12:0]), .d(ext_wdata), .q(ram_q));

    // ---------------------------------------------------------------- YM2203
    // The chip's pipelines (jt12's shift registers) need a long reset to take their reset values.
    logic [12:0] rst_cnt = '1;
    logic        rst_q = 1'b1;
    always_ff @(posedge clk) begin
        if (rst) rst_cnt <= '1;
        else if (rst_cnt != 13'd0) rst_cnt <= rst_cnt - 13'd1;
        rst_q <= rst | (rst_cnt != 13'd0);
    end

    wire        two    = (board == 4'd5) || (board == 4'd6);            // the YM2203 is on the second Z80's bus
    wire        sndcpu = two || is3cpu;
    wire        sel_ym = (ext_a[15:2] == 14'h2800) && !sndcpu;          // A000-A003
    logic       t_ym_rd, t_ym_wr, t_ym_a0;                              // the 3-CPU boards' sound Z80
    logic [1:0] t_ym_a;
    logic [7:0] t_ym_wdata;
    logic       s_ym_sel, s_ym_rd, s_ym_wr, s_ym_a0;                   // the second Z80's access
    logic [7:0] s_ym_wdata;
    wire        ym_rd_i = two ? s_ym_rd : is3cpu ? t_ym_rd : (ext_rd & sel_ym);
    wire        ym_wr_i = two ? s_ym_wr : is3cpu ? t_ym_wr : (ext_wr & sel_ym);
    wire        ym_a0_i = two ? s_ym_a0 : is3cpu ? t_ym_a0 : ext_a[0];
    wire  [7:0] ym_din_i = two ? s_ym_wdata : is3cpu ? t_ym_wdata : ext_wdata;
    wire        cen_ym_i = sndcpu ? cen_ym2 : cen_ym;
    // the YM's I/O port registers (0E, 0F), as the sound CPU writes them: the audio ROM bank and the MSM5205 volume
    logic [7:0] ym_regsel;
    always_ff @(posedge clk) if (ym_wr_i & ~ym_a0_i) ym_regsel <= ym_din_i;
    wire        ym_pa_we = ym_wr_i & ym_a0_i & (ym_regsel == 8'h0E);
    wire        ym_pb_we = ym_wr_i & ym_a0_i & (ym_regsel == 8'h0F);
    wire        raim = (board == 4'd9);                                  // the YM2610 board
    logic       ym_irq_n;
    logic       mux_sel;                                                // 0: DSWA / IN0, 1: DSWB / IN1
    always_ff @(posedge clk) begin
        if (rst) mux_sel <= 1'b0;
        else if (ext_rd & sel_ym) mux_sel <= ext_a[1];
    end
    wire direct = (board == 4'd3);
    wire [7:0] ioa = direct ? dswa : (mux_sel ? dswb : dswa);
    wire [7:0] iob = direct ? dswb : (mux_sel ? in1  : in0);

    logic [7:0] ym_q;
    logic        pcm_rd;                                                    // Raimais' ADPCM-A reads (taitol_tri's cache)
    logic [18:0] pcm_addr;
    logic  [7:0] pcm_q;
    logic        pcmb_rd;                                                   // ... and its ADPCM-B
    logic [18:0] pcmb_addr;
    logic  [7:0] pcmb_q;
`ifdef NOYM
    // simulation speed-up: no sound chip (the I/O ports are still read through it, so they are modelled here)
    logic [7:0] ym_reg;
    always_ff @(posedge clk) if (ym_wr_i & ~ym_a0_i) ym_reg <= ym_din_i;
    assign ym_q = ym_a0_i ? ((ym_reg == 8'h0E) ? ioa : (ym_reg == 8'h0F) ? iob : 8'h00) : 8'h00;
    assign snd = 16'sd0;
    assign snd_sample = 1'b0;
    assign ym_irq_n = 1'b1;
    assign pcm_rd   = 1'b0;
    assign pcm_addr = 19'd0;
    assign pcmb_rd   = 1'b0;
    assign pcmb_addr = 19'd0;
`else
    logic signed [15:0] fm_w;
    logic        [9:0]  psg_w;
    logic [7:0] q03, q10;
    logic       irq03_n, irq10_n;
    logic       snd_sample03, snd_sample10;
    jt03 u_ym (
        .rst(rst_q), .clk(clk), .cen(cen_ym_i),
        .din(ym_din_i), .addr(ym_a0_i), .cs_n(~((ym_rd_i | ym_wr_i) & ~raim)), .wr_n(~ym_wr_i),
        .dout(q03), .irq_n(irq03_n),
        .IOA_in(ioa), .IOB_in(iob),
        .psg_A(), .psg_B(), .psg_C(), .fm_snd(fm_w), .psg_snd(psg_w), .snd(), .snd_sample(snd_sample03),
        .debug_view()
    );

    // Raimais: the YM2610, on the 48 MHz clock (the PLL's third output, in phase with the 96 MHz one) with its own 8 MHz enable: jt12_div and
    // jt12_rst make their enables on the falling edge, a half-cycle path to every flip-flop they enable, 5 ns at 96 MHz (TaitoL.sdc). The Z80's
    // side of the chip (address, data, strobes: held for whole Z80 cycles) and the sample reads cross between the two clocks of one PLL,
    // edge to edge. FM and ADPCM come out left and right (snd_left / snd_right include the SSG, psg << 5, which is taken out again below);
    // MAME's routes into one speaker: the SSG 0.75, the left and the right 1.0 each.
    logic [2:0]  ydiv = 3'd0;
    logic        cen_ym48 = 1'b0;
    always_ff @(posedge clk_ym) begin
        ydiv     <= (ydiv == 3'd5) ? 3'd0 : ydiv + 3'd1;
        cen_ym48 <= (ydiv == 3'd5);
    end
    logic        rst_ym = 1'b1;                                          // the reset, registered on the chip's clock
    always_ff @(posedge clk_ym) rst_ym <= rst_q;
    logic [19:0] adpcma_addr;
    logic [23:0] adpcmb_addr;
    logic [3:0]  adpcma_bank;
    logic        adpcma_roe_n;
    logic signed [15:0] ym10_l, ym10_r;
    logic        [9:0]  psg10;
    jt10 u_ym10 (
        .rst(rst_ym), .clk(clk_ym), .cen(cen_ym48),
        .din(ym_din_i), .addr(t_ym_a), .cs_n(~((ym_rd_i | ym_wr_i) & raim)), .wr_n(~ym_wr_i),
        .dout(q10), .irq_n(irq10_n),
        .adpcma_addr(adpcma_addr), .adpcma_bank(adpcma_bank), .adpcma_roe_n(adpcma_roe_n), .adpcma_data(pcm_q),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(), .adpcmb_data(pcmb_q),
        .psg_A(), .psg_B(), .psg_C(), .fm_snd(), .psg_snd(psg10), .snd_right(ym10_r), .snd_left(ym10_l), .snd_sample(snd_sample10)
    );
    assign pcm_rd   = ~adpcma_roe_n & raim;
    assign pcm_addr = adpcma_addr[18:0];
    assign pcmb_rd   = raim;                                                // the cache follows whatever address ADPCM-B shows
    assign pcmb_addr = adpcmb_addr[18:0];
    assign ym_q = raim ? q10 : q03;
    assign ym_irq_n = raim ? irq10_n : irq03_n;
    assign snd_sample = raim ? smp10_d : snd_sample03;
    // jt03 sums the FM section and the SSG (psg << 5); on the board the two reach the amplifier through different resistors
    // (MAME: SSG channels 0.20, FM 0.80). Measured against MAME's own output (Kuri Kinton music, Plotting: tools/audiocmp.py,
    // docs/status.md): with the FM section at the core's gain the SSG wants 10.4 per raw unit, i.e. 3.125 per unit before it.
    wire        [12:0] psg_adj = {psg_w, 1'b0} + {3'b000, psg_w} + {6'b000000, psg_w[9:3]};            // psg * 3 + psg / 8 = 3.125 psg
    logic signed [15:0] snd_mix;                                    // registered: the core multiplies this by 3.33 right after (96 MHz timing)
    wire signed [15:0] psg10_s = $signed({1'b0, psg10, 5'd0});
    wire signed [16:0] fm10_s  = (ym10_l - psg10_s) + (ym10_r - psg10_s);                          // FM + ADPCM, both sides
    // MAME (ymfm) into one speaker: SSG route 0.75 of (a + b + c) * 2/3 (a jt49 level is 64.25 ymfm steps: 42.8 per unit of psg_snd) and the left and
    // right FM + ADPCM at 1.0 each, jt10's units being ymfm's (the same figures as the owner's MCatAdv core, whose YM2610 is checked on hardware);
    // the core multiplies by 3.33 right after: SSG 0.75 * 42.8 / 3.33 = 9.64 per unit (9.625), FM + ADPCM (L + R) / 3.33 = 0.3 (0.297)
    wire        [13:0] psg10_a = {psg10, 3'b000} + {4'b0000, psg10} + {5'b00000, psg10[9:1]} + {7'b0000000, psg10[9:3]};   // x9.625
    wire signed [16:0] fm10_a  = (fm10_s >>> 2) + (fm10_s >>> 5) + (fm10_s >>> 6);                                       // x0.297
    // made on the chip's clock (20 ns for the adders), handed over registered at each sample
    logic signed [15:0] mix10;
    logic               smp10_d = 1'b0;
    always_ff @(posedge clk_ym) begin
        smp10_d <= snd_sample10;
        if (snd_sample10) mix10 <= fm10_a + $signed({2'b00, psg10_a});
    end
    always_ff @(posedge clk) snd_mix <= raim ? mix10 : (fm_w + $signed({3'b000, psg_adj}) + msm_snd);
    assign snd = snd_mix;
`endif
    assign dbg_ym_wr = ym_wr_i;
    assign dbg_ym_a0 = ym_a0_i;
    assign dbg_ym_a1 = raim ? t_ym_a[1] : 1'b0;
    assign dbg_ym_d  = ym_din_i;

    // ---------------------------------------------------------------- bus
    // ---------------------------------------------------------------- Puzznic's MC68705 (board 1)
    wire sel_b800 = (ext_a == 16'hB800);
    logic [7:0] mcu_q;
    taitol_mcu u_mcu (
        .clk(clk), .rst(rst | (board != 4'd1)), .cen(cen_mcu),
        .rom_we(mcu_we), .rom_waddr(mcu_waddr), .rom_wdata(mcu_wdata),
        .host_wr(ext_wr & sel_b800), .host_wdata(ext_wdata), .host_rd(ext_rd & sel_b800), .host_rdata(mcu_q)
    );

    // ---------------------------------------------------------------- the Palamedes family's 8255 (board 3)
    wire        sel_ppi = (ext_a[15:2] == 14'h2A00);                   // A800-A803
    logic [7:0] ppi_q;
    taitol_i8255 u_ppi (.clk(clk), .rst(rst), .wr(ext_wr & sel_ppi), .rd(ext_rd & sel_ppi), .a(ext_a[1:0]), .d(ext_wdata), .q(ppi_q),
                        .pa_in(in0), .pb_in(in1), .pc_in(in2));

    // ---------------------------------------------------------------- American Horseshoes (board 4)
    wire        sel_trk = (ext_a[15:4] == 12'hA80) && (ext_a[1:0] == 2'b00 || ext_a[3:0] == 4'h2 || ext_a[3:0] == 4'h3);   // A800 A804 A808 A80C; A802 A803 reset
    logic [7:0] trk_q;
    taitol_upd4701 u_trk (.clk(clk), .rst(rst | (board != 4'd4)), .add_x(tb_add_x), .dx(tb_dx), .add_y(tb_add_y), .dy(tb_dy),
                          .rd(ext_rd & sel_trk), .a(ext_a[3:0]), .q(trk_q));
    always_ff @(posedge clk) begin
        if (rst) gbank <= 8'h00;
        else if (ext_wr && ext_a == 16'hB802 && board == 4'd4) gbank <= ext_wdata;
    end

    // ---------------------------------------------------------------- the 2-CPU boards: dual-port RAM, I/O chip, second Z80
    wire        sel_dpm = two && (ext_a[15:11] == 5'b10100);                       // A000-A7FF
    logic [7:0] dpm_q, sdp_q;
    logic [10:0] sdp_addr;
    logic        sdp_we;
    logic [7:0]  sdp_wdata;
    taitol_tdp8 #(.AW(11)) u_dp (
        .clk(clk),
        .wea(ext_wr & sel_dpm), .addra(ext_a[10:0]), .da(ext_wdata), .qa(dpm_q),
        .web(sdp_we), .addrb(sdp_addr), .db(sdp_wdata), .qb(sdp_q)
    );
    taitol_sub u_sub (
        .clk(clk), .rst(rst | ~two), .cen(cen_sub), .big_rom(board == 4'd6), .vbl_pulse(vbl_pulse),
        .rom_we(sub_we), .rom_waddr(sub_waddr), .rom_wdata(sub_wdata),
        .dp_addr(sdp_addr), .dp_we(sdp_we), .dp_wdata(sdp_wdata), .dp_q(sdp_q),
        .ym_sel(s_ym_sel), .ym_rd(s_ym_rd), .ym_wr(s_ym_wr), .ym_a0(s_ym_a0), .ym_wdata(s_ym_wdata), .ym_q(ym_q)
    );

    // TC0040IOC (board 5) at A800-A801, TC0510NIO (board 6) at A800-A807
    wire        sel_ioc = ((board == 4'd5) && (ext_a[15:1] == 15'h5400)) || ((board == 4'd9) && (ext_a[15:1] == 15'h4400));   // A800 / 8800
    wire        sel_nio = (board == 4'd6) && (ext_a[15:3] == 13'h1500);
    logic [7:0] ioc_port, ioc_reg4;
    function automatic [7:0] io_reg(input [2:0] n, input [7:0] r4, input [7:0] a, b, c, d, e);
        case (n)
            3'd0: io_reg = a;  3'd1: io_reg = b;  3'd2: io_reg = c;  3'd3: io_reg = d;
            3'd4: io_reg = r4; 3'd7: io_reg = e;  default: io_reg = 8'hFF;
        endcase
    endfunction
    always_ff @(posedge clk) begin
        if (rst || !(two || board == 4'd9)) begin ioc_port <= 8'h00; ioc_reg4 <= 8'h00; end
        else if (ext_wr) begin
            if (sel_ioc &&  ext_a[0]) ioc_port <= ext_wdata;
            if (sel_ioc && !ext_a[0] && ioc_port == 8'h04) ioc_reg4 <= ext_wdata;
            if (sel_nio && ext_a[2:0] == 3'd4) ioc_reg4 <= ext_wdata;
        end
    end
    wire [7:0] ioc_q = ext_a[0] ? 8'h00 : (ioc_port[7:3] != 5'd0) ? 8'hFF : io_reg(ioc_port[2:0], ioc_reg4, dswa, dswb, in0, in1, in2);
    wire [7:0] nio_q = io_reg(ext_a[2:0], ioc_reg4, dswa, dswb, in0, in1, in2);

    // ---------------------------------------------------------------- the 3-CPU boards: shared RAM, slave and sound Z80s
    wire        sel_sh = ((board == 4'd7) && (ext_a[15:13] == 3'b100)) || ((board == 4'd8) && (ext_a[15:13] == 3'b101)) ||
                         ((board == 4'd9) && (ext_a[15:11] == 5'b10000));
    wire        sel_syt_p = (board == 4'd9) && (ext_a == 16'h8C00);
    wire        sel_syt_c = (board == 4'd9) && (ext_a == 16'h8C01);
    logic [7:0] msh_q, msyt_q;
    logic signed [15:0] msm_snd;
    taitol_tri u_tri (
        .clk(clk), .rst(rst | ~is3cpu), .board(board), .cen(cen_sub), .vbl_pulse(vbl_pulse),
        .dswa(dswa), .dswb(dswb), .in0(in0), .in1(in1), .in2(in2),
        .msh_we(ext_wr & sel_sh), .msh_addr(ext_a[12:0]), .msh_wdata(ext_wdata), .msh_q(msh_q),
        .msyt_port_wr(ext_wr & sel_syt_p), .msyt_comm_wr(ext_wr & sel_syt_c), .msyt_comm_rd(ext_rd & sel_syt_c),
        .msyt_wdata(ext_wdata), .msyt_q(msyt_q),
        .cache_inval(cache_inval),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
        .m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done), .msm_snd(msm_snd),
        .pcm_rd(pcm_rd), .pcm_addr(pcm_addr), .pcm_q(pcm_q), .pcmb_rd(pcmb_rd), .pcmb_addr(pcmb_addr), .pcmb_q(pcmb_q), .dbg_pcm_max(dbg_pcm_max),
        .ym_rd(t_ym_rd), .ym_wr(t_ym_wr), .ym_a0(t_ym_a0), .ym_a(t_ym_a), .ym_wdata(t_ym_wdata), .ym_q(ym_q), .ym_irq_n(ym_irq_n),
        .ym_pa_we(ym_pa_we), .ym_pa_d(ym_din_i), .ym_pb_we(ym_pb_we), .ym_pb_d(ym_din_i)
    );

    wire sel_b801 = (ext_a == 16'hB801);
    always_comb begin
        ext_rdata = 8'h00;
        if (sel_ram)     ext_rdata = ram_q;
        else if (sel_ym) ext_rdata = ym_q;
        else if (sel_b801 && (board == 4'd1 || board == 4'd2)) ext_rdata = 8'h01;
        else if (sel_b800 && board == 4'd1) ext_rdata = mcu_q;
        else if (sel_ppi && board == 4'd3) ext_rdata = ppi_q;
        else if (sel_sh)                   ext_rdata = msh_q;
        else if (sel_syt_c)                ext_rdata = msyt_q;
        else if (sel_dpm)                  ext_rdata = dpm_q;
        else if (sel_ioc)                  ext_rdata = ioc_q;
        else if (sel_nio)                  ext_rdata = nio_q;
        else if (sel_trk && board == 4'd4) ext_rdata = trk_q;
    end
endmodule
`default_nettype wire
