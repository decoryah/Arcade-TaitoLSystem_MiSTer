// The slave and sound Z80s of the 3-CPU boards (7 = Fighting Hawk, 8 = Champion Wrestler; 9 = Raimais is wired but its YM2610 is
// not in yet). MAME: fhawk_2_map / fhawk_3_map, champwr_2_map / champwr_3_map, raimais_2_map / raimais_3_map.
//
//   slave Z80 (12 MHz / 3), vblank interrupt held until acknowledged:
//     fhawk    0000-7FFF ROM, 8000-BFFF ROM bank n (16 KB units, C000 write), C800 PC060HA port, C801 comm,
//              D000-D007 TC0220IOC, E000-FFFF shared RAM (the main CPU's 8000-9FFF)
//     champwr  0000-7FFF ROM, 8000-BFFF ROM bank (F000 read / write), C000-DFFF shared RAM (the main CPU's A000-BFFF),
//              E000-E007 TC0220IOC, E800 PC060HA port, E801 comm
//     raimais  0000-BFFF ROM, C000-DFFF RAM, E000-E7FF MB8421 dual-port RAM (left port; the main CPU has the right at 8000-87FF)
//   sound Z80 (12 MHz / 3): YM2203 (jt03 of the board) interrupt -> INT, the communication chip's NMI and reset
//     fhawk    0000-3FFF ROM, 4000-7FFF ROM bank (YM port A write & 3; 1 after reset), 8000-9FFF RAM, E000 / E001 PC060HA, F000-F001 YM2203
//     champwr  the same with RAM 8000-8FFF, YM2203 9000-9001, PC060HA A000 / A001, and the MSM5205: B000 write = sample address bit 16,
//              C000 write = address bits 15-8, D000 write = start, E000 write = stop (address bits 7-0 cleared); at every 8 kHz VCK the
//              next nibble comes from the ADPCM ROM (128 KB, SDRAM, read through a cache); YM port B write = its volume (data / 255)
//     raimais  0000-3FFF ROM, 4000-7FFF ROM bank (F200 write & 3), RAM C000-DFFF, YM2610 E000-E003, TC0140SYT E200 / E201
// Both ROMs live in SDRAM and are read through 8 KB caches (a miss holds the Z80 with WAIT).
`default_nettype none
module taitol_tri (
    input  logic        clk,
    input  logic        rst,
    input  logic [3:0]  board,
    input  logic        cen,                  // 4 MHz
    input  logic        vbl_pulse,

    input  logic [7:0]  dswa, dswb, in0, in1, in2,

    // main CPU side: the shared RAM (an 8 KB array; Raimais uses the first 2 KB as its dual-port RAM)
    input  logic        msh_we,
    input  logic [12:0] msh_addr,
    input  logic [7:0]  msh_wdata,
    output logic [7:0]  msh_q,
    // main CPU side: the communication chip (Raimais)
    input  logic        msyt_port_wr, msyt_comm_wr, msyt_comm_rd,
    input  logic [7:0]  msyt_wdata,
    output logic [7:0]  msyt_q,

    // SDRAM line fills for the two ROM caches
    input  logic        cache_inval,
    output logic        s_req,  output logic [16:4] s_addr,
    input  logic        s_wr,   input logic [2:0] s_idx, input logic [15:0] s_data, input logic s_done,
    output logic        a_req,  output logic [15:4] a_addr,
    input  logic        a_wr,   input logic [2:0] a_idx, input logic [15:0] a_data, input logic a_done,
    output logic        m_req,  output logic [16:4] m_addr,         // the ADPCM ROM (Champion Wrestler)
    input  logic        m_wr,   input logic [2:0] m_idx, input logic [15:0] m_data, input logic m_done,
    output logic signed [15:0] msm_snd,                             // the MSM5205, volume applied, in the YM mix's units

    // the sound chip on the sound Z80's bus
    output logic        ym_rd, ym_wr, ym_a0,
    output logic [7:0]  ym_wdata,
    input  logic [7:0]  ym_q,
    input  logic        ym_irq_n,
    input  logic        ym_pa_we,             // the chip's port A register was written (fhawk / champwr: the audio ROM bank)
    input  logic [7:0]  ym_pa_d,
    input  logic        ym_pb_we,             // port B (champwr: the MSM5205's volume; not used yet)
    input  logic [7:0]  ym_pb_d
);
    wire fhawk = (board == 4'd7), champ = (board == 4'd8), raim = (board == 4'd9);

    // ================================================================ the communication chip
    logic        sy_m_pw, sy_m_cw, sy_m_cr, sy_s_pw, sy_s_cw, sy_s_cr, sy_nmi, sy_reset;
    logic [7:0]  sy_m_wd, sy_s_wd, sy_m_q, sy_s_q;
    // the master side: the slave Z80 (fhawk, champwr), or the main CPU (raimais)
    logic        sl_syt_pw, sl_syt_cw, sl_syt_cr;
    logic [7:0]  sl_dout;
    assign sy_m_pw = raim ? msyt_port_wr : sl_syt_pw;
    assign sy_m_cw = raim ? msyt_comm_wr : sl_syt_cw;
    assign sy_m_cr = raim ? msyt_comm_rd : sl_syt_cr;
    assign sy_m_wd = raim ? msyt_wdata   : sl_dout;
    assign msyt_q  = sy_m_q;
    taitol_syt u_syt (
        .clk(clk), .rst(rst),
        .m_port_wr(sy_m_pw), .m_comm_wr(sy_m_cw), .m_comm_rd(sy_m_cr), .m_wdata(sy_m_wd), .m_rdata(sy_m_q),
        .s_port_wr(sy_s_pw), .s_comm_wr(sy_s_cw), .s_comm_rd(sy_s_cr), .s_wdata(sy_s_wd), .s_rdata(sy_s_q),
        .nmi(sy_nmi), .sound_reset(sy_reset)
    );

    // ================================================================ shared RAM
    logic [7:0] sh_qa, sh_qb;
    logic       sh_web;
    logic [12:0] sh_addrb;
    logic [7:0] sh_wdb;
    taitol_tdp8 #(.AW(13)) u_sh (
        .clk(clk),
        .wea(msh_we), .addra(msh_addr), .da(msh_wdata), .qa(msh_q),
        .web(sh_web), .addrb(sh_addrb), .db(sh_wdb), .qb(sh_qb)
    );
    assign sh_qa = 8'h00;

    // ================================================================ slave Z80
    logic        sl_mreq_n, sl_iorq_n, sl_rd_n, sl_wr_n, sl_m1_n, sl_wait_n;
    logic [15:0] sl_a;
    logic  [7:0] sl_di;
    logic        sl_irq = 1'b0, sl_inta_d;
    tv80s_cen u_slave (
        .reset_n(~rst), .clk(clk), .cen(cen), .wait_n(sl_wait_n), .int_n(~sl_irq), .nmi_n(1'b1), .busrq_n(1'b1),
        .m1_n(sl_m1_n), .mreq_n(sl_mreq_n), .iorq_n(sl_iorq_n), .rd_n(sl_rd_n), .wr_n(sl_wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(sl_a), .di(sl_di), .dout(sl_dout), .im()
    );
    wire sl_rd   = ~sl_mreq_n & ~sl_rd_n;
    wire sl_wr   = ~sl_mreq_n & ~sl_wr_n;
    wire sl_inta = ~sl_iorq_n & ~sl_m1_n;
    always_ff @(posedge clk) begin
        sl_inta_d <= sl_inta;
        if (rst) sl_irq <= 1'b0;
        else begin
            if (vbl_pulse) sl_irq <= 1'b1;
            if (sl_inta && !sl_inta_d) sl_irq <= 1'b0;
        end
    end

    // ROM bank register
    logic [3:0] sl_bank;
    // decode
    logic sl_rom, sl_bankw, sl_shr, sl_ioc, sl_ramp, sl_dpr, sl_syt_p, sl_syt_c, sl_bankrw;
    always_comb begin
        sl_rom = 1'b0; sl_shr = 1'b0; sl_ioc = 1'b0; sl_ramp = 1'b0; sl_syt_p = 1'b0; sl_syt_c = 1'b0; sl_bankrw = 1'b0;
        sh_addrb = sl_a[12:0];
        if (fhawk) begin
            sl_rom    = (sl_a[15:14] != 2'b11);
            sl_bankrw = (sl_a == 16'hC000);
            sl_syt_p  = (sl_a == 16'hC800);
            sl_syt_c  = (sl_a == 16'hC801);
            sl_ioc    = (sl_a[15:3] == 13'h1A00);                      // D000-D007
            sl_shr    = (sl_a[15:13] == 3'b111);                       // E000-FFFF
        end else if (champ) begin
            sl_rom    = (sl_a[15:14] != 2'b11);
            sl_shr    = (sl_a[15:13] == 3'b110);                       // C000-DFFF
            sl_ioc    = (sl_a[15:3] == 13'h1C00);                      // E000-E007
            sl_syt_p  = (sl_a == 16'hE800);
            sl_syt_c  = (sl_a == 16'hE801);
            sl_bankrw = (sl_a == 16'hF000);
        end else begin                                                  // raimais
            sl_rom    = (sl_a[15:14] != 2'b11);
            sl_ramp   = (sl_a[15:13] == 3'b110);                       // C000-DFFF
            sl_shr    = (sl_a[15:11] == 5'b11100);                     // E000-E7FF
            sh_addrb  = {2'b00, sl_a[10:0]};
        end
    end
    wire sl_bank_win = (fhawk || champ) && sl_a[15:14] == 2'b10;       // 8000-BFFF
    wire [16:0] sl_rom_a = sl_bank_win ? {sl_bank[2:0], sl_a[13:0]} : {1'b0, sl_a};

    logic        sl_hit;
    logic  [7:0] sl_rom_q;
    taitol_cache #(.AB(17)) u_scache (
        .clk(clk), .inval(cache_inval), .rd(sl_rd & sl_rom), .addr(sl_rom_a), .hit(sl_hit), .data(sl_rom_q),
        .fill_req(s_req), .fill_addr(s_addr), .fill_wr(s_wr), .fill_idx(s_idx), .fill_data(s_data), .fill_done(s_done)
    );
    assign sl_wait_n = ~(sl_rd & sl_rom & ~sl_hit);

    logic [7:0] slram_q;
    taitol_ram8 #(.AW(13)) u_slram (.clk(clk), .we(sl_wr & sl_ramp), .addr(sl_a[12:0]), .d(sl_dout), .q(slram_q));
    assign sh_web = sl_wr & sl_shr;
    assign sh_wdb = sl_dout;

    // TC0220IOC
    logic [7:0] ioc_reg4;
    always_ff @(posedge clk) begin
        if (rst) ioc_reg4 <= 8'h00;
        else if (sl_wr && sl_ioc && sl_a[2:0] == 3'd4) ioc_reg4 <= sl_dout;
    end
    logic [7:0] ioc_q;
    always_comb begin
        case (sl_a[2:0])
            3'd0: ioc_q = dswa; 3'd1: ioc_q = dswb; 3'd2: ioc_q = in0; 3'd3: ioc_q = in1;
            3'd4: ioc_q = ioc_reg4; 3'd7: ioc_q = in2; default: ioc_q = 8'hFF;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) sl_bank <= 4'd0;
        else if (sl_wr && sl_bankrw) sl_bank <= sl_dout[3:0];
    end
    assign sl_syt_pw = sl_wr & sl_syt_p;
    assign sl_syt_cw = sl_wr & sl_syt_c;
    assign sl_syt_cr = sl_rd & sl_syt_c;

    always_comb begin
        sl_di = 8'h00;
        if (sl_inta)         sl_di = 8'hFF;
        else if (sl_rom)     sl_di = sl_rom_q;
        else if (sl_shr)     sl_di = sh_qb;
        else if (sl_ramp)    sl_di = slram_q;
        else if (sl_ioc)     sl_di = ioc_q;
        else if (sl_syt_c)   sl_di = sy_m_q;
        else if (sl_bankrw)  sl_di = {4'h0, sl_bank};
    end

    // ================================================================ sound Z80
    logic        au_mreq_n, au_iorq_n, au_rd_n, au_wr_n, au_m1_n, au_wait_n;
    logic [15:0] au_a;
    logic  [7:0] au_di, au_dout;
    tv80s_cen u_audio (
        .reset_n(~(rst | sy_reset)), .clk(clk), .cen(cen), .wait_n(au_wait_n), .int_n(ym_irq_n), .nmi_n(~sy_nmi), .busrq_n(1'b1),
        .m1_n(au_m1_n), .mreq_n(au_mreq_n), .iorq_n(au_iorq_n), .rd_n(au_rd_n), .wr_n(au_wr_n), .rfsh_n(), .halt_n(), .busak_n(),
        .A(au_a), .di(au_di), .dout(au_dout), .im()
    );
    wire au_rd   = ~au_mreq_n & ~au_rd_n;
    wire au_wr   = ~au_mreq_n & ~au_wr_n;
    wire au_inta = ~au_iorq_n & ~au_m1_n;

    logic au_rom, au_ram, au_ym, au_syt_p, au_syt_c, au_bankw;
    always_comb begin
        au_rom = ~au_a[15];                                              // 0000-7FFF: ROM, 4000-7FFF the bank window
        au_ram = 1'b0; au_ym = 1'b0; au_syt_p = 1'b0; au_syt_c = 1'b0; au_bankw = 1'b0;
        if (fhawk) begin
            au_ram = (au_a[15:13] == 3'b100);                           // 8000-9FFF
            au_syt_p = (au_a == 16'hE000); au_syt_c = (au_a == 16'hE001);
            au_ym  = (au_a[15:1] == 15'h7800);                          // F000-F001
        end else if (champ) begin
            au_ram = (au_a[15:12] == 4'h8);                             // 8000-8FFF
            au_ym  = (au_a[15:1] == 15'h4800);                          // 9000-9001
            au_syt_p = (au_a == 16'hA000); au_syt_c = (au_a == 16'hA001);
        end else begin
            au_ram = (au_a[15:13] == 3'b110);                           // C000-DFFF
            au_ym  = (au_a[15:2] == 14'h3800);                          // E000-E003 (YM2610)
            au_syt_p = (au_a == 16'hE200); au_syt_c = (au_a == 16'hE201);
            au_bankw = (au_a == 16'hF200);
        end
    end
    logic [1:0] au_bank;
    always_ff @(posedge clk) begin
        if (rst) au_bank <= 2'd1;                                         // MAME: entry 1 at machine reset (a reset by the comm chip leaves it)
        else if (raim) begin if (au_wr && au_bankw) au_bank <= au_dout[1:0]; end
        else if (ym_pa_we) au_bank <= ym_pa_d[1:0];                       // fhawk / champwr: the YM2203's port A
    end
    wire [15:0] au_rom_a = au_a[14] ? {au_bank, au_a[13:0]} : {2'b00, au_a[13:0]};
    logic        au_hit;
    logic  [7:0] au_rom_q, auram_q;
    taitol_cache #(.AB(16)) u_acache (
        .clk(clk), .inval(cache_inval), .rd(au_rd & au_rom), .addr(au_rom_a), .hit(au_hit), .data(au_rom_q),
        .fill_req(a_req), .fill_addr(a_addr), .fill_wr(a_wr), .fill_idx(a_idx), .fill_data(a_data), .fill_done(a_done)
    );
    assign au_wait_n = ~(au_rd & au_rom & ~au_hit);
    taitol_ram8 #(.AW(13)) u_auram (.clk(clk), .we(au_wr & au_ram), .addr(au_a[12:0]), .d(au_dout), .q(auram_q));

    assign sy_s_pw = au_wr & au_syt_p;
    assign sy_s_cw = au_wr & au_syt_c;
    assign sy_s_cr = au_rd & au_syt_c;
    assign sy_s_wd = au_dout;
    assign ym_rd = au_rd & au_ym;
    assign ym_wr = au_wr & au_ym;
    assign ym_a0 = au_a[0];
    assign ym_wdata = au_dout;
    always_comb begin
        au_di = 8'h00;
        if (au_inta)         au_di = 8'hFF;
        else if (au_rom)     au_di = au_rom_q;
        else if (au_ram)     au_di = auram_q;
        else if (au_ym)      au_di = ym_q;
        else if (au_syt_c)   au_di = sy_s_q;
    end

    // ================================================================ MSM5205 (Champion Wrestler)
    logic        cen384 = 1'b0;                                       // 96 MHz / 250
    logic  [7:0] c384 = 8'd0;
    always_ff @(posedge clk) begin c384 <= (c384 == 8'd249) ? 8'd0 : c384 + 8'd1; cen384 <= (c384 == 8'd249); end
    logic [16:0] msm_pos = 17'd0;
    logic        msm_run = 1'b0;
    logic  [7:0] msm_vol = 8'd255;
    logic  [3:0] nib = 4'd0, pend_n = 4'd0;
    logic        pend_v = 1'b0, fetch = 1'b0;
    wire         msm_w_hi = champ & au_wr & (au_a == 16'hB000);
    wire         msm_w_lo = champ & au_wr & (au_a == 16'hC000);
    wire         msm_w_st = champ & au_wr & (au_a == 16'hD000);
    wire         msm_w_sp = champ & au_wr & (au_a == 16'hE000);
    logic        msm_irq, m_hit;
    logic  [7:0] m_q;
    logic signed [11:0] msm_s;
    jt5205 #(.INTERPOL(0)) u_msm (
        .rst(~msm_run | rst), .clk(clk), .cen(cen384), .sel(2'd2), .din(nib), .sound(msm_s), .sample(), .irq(msm_irq), .vclk_o()
    );
    always_ff @(posedge clk) begin
        if (rst) begin
            msm_run <= 1'b0; pend_v <= 1'b0; fetch <= 1'b0; msm_pos <= 17'd0; msm_vol <= 8'd255; nib <= 4'd0;
        end else begin
            if (msm_irq && msm_run) begin                             // the chip has taken `nib`; line up the next one (MAME: msm5205_vck)
                if (pend_v) begin nib <= pend_n; pend_v <= 1'b0; end
                else fetch <= 1'b1;
            end
            if (fetch && m_hit) begin
                nib <= m_q[7:4]; pend_n <= m_q[3:0]; pend_v <= 1'b1; fetch <= 1'b0; msm_pos <= msm_pos + 17'd1;
            end
            if (msm_w_hi) msm_pos[16] <= au_dout[0];
            if (msm_w_lo) msm_pos[15:8] <= au_dout;
            if (msm_w_st) msm_run <= 1'b1;
            if (msm_w_sp) begin msm_run <= 1'b0; msm_pos[7:0] <= 8'd0; end
            if (ym_pb_we && champ) msm_vol <= ym_pb_d;
        end
    end
    taitol_cache #(.AB(17)) u_mcache (
        .clk(clk), .inval(cache_inval), .rd(fetch), .addr(msm_pos), .hit(m_hit), .data(m_q),
        .fill_req(m_req), .fill_addr(m_addr), .fill_wr(m_wr), .fill_idx(m_idx), .fill_data(m_data), .fill_done(m_done)
    );
    // MAME: the MSM5205 output is its 12 bit signal x 16, route 0.80, and the volume (data / 255); the board's sum is followed by
    // the core's x3.33, so the signal x 16 x 0.8 / 3.33 = x 3.84; the first measurement against MAME's output found the voice bands 4-5 dB
    // too loud, so the factor is x2.25
    wire        [8:0]  msm_k  = {1'b0, msm_vol} + 9'd1;                          // (vol + 1) / 256: 1/256 .. 1
    logic signed [21:0] msm_v;                                                       // the sample rate is 8 kHz: the chain below is registered stage by stage
    always_ff @(posedge clk) msm_v <= msm_s * $signed({1'b0, msm_k});
    wire signed [13:0] msm_vs = msm_v[21:8];
    logic signed [15:0] msm_snd_q;
    always_ff @(posedge clk) msm_snd_q <= champ ? ((msm_vs <<< 1) + (msm_vs >>> 2)) : 16'sd0;      // x2.25: measured +4.5 dB hot at x3.875 against MAME
    assign msm_snd = msm_snd_q;

    wire unused = ^{sh_qa, ym_pb_we, ym_pb_d};
endmodule
`default_nettype wire
