// The whole machine, without its memory (SDRAM) and the platform: the TC0090LVC (Z80 + video), the board around it and
// the sound. Clocks: clk 96 MHz, clk_vid 26.66112 MHz (the raster; pixel clock = clk_vid / 4).
`default_nettype none
module taitol_core #(
    parameter [24:1] GFX_BASE = 24'h080000
) (
    input  logic        clk,
    input  logic        clk_ym,               // 48 MHz, in phase with clk (the same PLL): the YM2610
    input  logic        clk_vid,
    input  logic        rst,                  // the machine
    input  logic        vid_rst,              // the video renderers (normally = rst)

    // program load
    input  logic        cache_inval,          // a ROM load starts

    // configuration from the image (taitol_mem)
    input  logic [3:0]  cfg_board,
    input  logic [17:0] cfg_pmask,
    input  logic [16:0] cfg_n8,
    input  logic [19:0] cfg_rmask,
    input  logic [7:0]  cfg_flags,
    input  logic        opt_scr_latch,        // OSD: BG scroll registers latched at vblank

    // memory clients (target/mister/taitol_mem.sv)
    output logic        p_req,  output logic [19:4] p_addr,
    input  logic        p_wr,   input logic [2:0] p_idx,  input logic [15:0] p_data,  input logic p_done,
    output logic        s_req,  output logic [16:4] s_addr,         // slave Z80 ROM (3-CPU boards)
    input  logic        s_wr,   input logic [2:0] s_idx,  input logic [15:0] s_data,  input logic s_done,
    output logic        a_req,  output logic [15:4] a_addr,         // sound Z80 ROM
    input  logic        a_wr,   input logic [2:0] a_idx,  input logic [15:0] a_data,  input logic a_done,
    output logic        m_req,  output logic [18:4] m_addr,         // ADPCM ROM (Champion Wrestler's MSM5205, Raimais' YM2610 ADPCM-A)
    input  logic        m_wr,   input logic [2:0] m_idx,  input logic [15:0] m_data,  input logic m_done,
    output logic        g0_req, output logic [24:1] g0_addr,
    input  logic        g0_wr,  input logic [1:0] g0_idx, input logic [15:0] g0_data, input logic g0_done,
    output logic        g1_req, output logic [24:1] g1_addr,
    input  logic        g1_wr,  input logic [1:0] g1_idx, input logic [15:0] g1_data, input logic g1_done,
    output logic        gs_req, output logic [24:1] gs_addr,
    input  logic        gs_wr,  input logic [1:0] gs_idx, input logic [15:0] gs_data, input logic gs_done,

    // controls, active low, the board's bit order
    input  logic [7:0]  dswa, dswb, in0, in1, in2,

    // the MC68705's program, as the loader writes it (Puzznic)
    input  logic        mcu_we,
    input  logic [10:0] mcu_waddr,
    input  logic [7:0]  mcu_wdata,

    // the second Z80's ROM, as the loader writes it (Kuri Kinton, Evil Stone)
    input  logic        sub_we,
    input  logic [15:0] sub_waddr,
    input  logic [7:0]  sub_wdata,

    // the trackball's movement (American Horseshoes): counter steps
    input  logic        tb_add_x, tb_add_y,
    input  logic signed [8:0] tb_dx, tb_dy,

    // picture and sound
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic        vb_next,
    output logic [23:0] rgb,
    output logic signed [15:0] snd_l, snd_r,
    output logic        snd_valid,

    // debug
    output logic        dbg_ovr,
    output logic [3:0]  dbg_ovr_bits,           // bg0, bg1, text, sprites
    output logic [3:0]  dbg_busy,               // the same renderers: busy (the bench measures the longest line)
    output logic        dbg_irq,
    output logic        dbg_m1,
    output logic        dbg_ym_wr,
    output logic        dbg_ym_a0,
    output logic        dbg_ym_a1,
    output logic  [8:0] dbg_pcm_max,
    output logic [7:0]  dbg_ym_d
);
    logic cen_cpu, cen_ym1, cen_z80b, cen_ym2, cen_ym2610, cen_mcu;
    taitol_cen u_cen (.clk(clk), .cen_cpu(cen_cpu), .cen_ym1(cen_ym1), .cen_z80b(cen_z80b), .cen_ym2(cen_ym2), .cen_ym2610(cen_ym2610), .cen_mcu(cen_mcu));

    // ---------------------------------------------------------------- video
    logic [19:0] v_addr;
    logic        v_we;
    logic [7:0]  v_wdata, v_rdata;
    logic [7:0]  vreg4;
    logic [31:0] tbank;
    logic        ls_pulse, frame_pulse;
    logic [8:0]  ln_new;
    logic        ovr_bg0, ovr_bg1, ovr_tx, ovr_spr;
    logic  [7:0] gbank;
    wire         copy = ls_pulse && (ln_new == 9'd240);                 // the sprite RAM is latched at the start of vblank

    taitol_vcore #(.GFX_BASE(GFX_BASE)) u_vcore (
        .clk(clk), .clk_vid(clk_vid), .rst(vid_rst),
        .v_addr(v_addr), .v_we(v_we), .v_wdata(v_wdata), .v_rdata(v_rdata),
        .vreg4(vreg4), .tbank(tbank), .copy(copy), .scr_latch(opt_scr_latch),
        .gfx_pmask(cfg_pmask), .gfx_n(cfg_n8), .gbank(gbank),
        .g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
        .g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
        .gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .ls_pulse(ls_pulse), .frame_pulse(frame_pulse), .ln_new(ln_new), .vb_next(vb_next),
        .dbg_ovr_bg0(ovr_bg0), .dbg_ovr_bg1(ovr_bg1), .dbg_ovr_tx(ovr_tx), .dbg_ovr_spr(ovr_spr),
        .busy_bg0(dbg_busy[0]), .busy_bg1(dbg_busy[1]), .busy_tx(dbg_busy[2]), .busy_spr(dbg_busy[3])
    );
    assign dbg_ovr = ovr_bg0 | ovr_bg1 | ovr_tx | ovr_spr;
    assign dbg_ovr_bits = {ovr_spr, ovr_tx, ovr_bg1, ovr_bg0};

    // ---------------------------------------------------------------- the CPU
    logic        rom_rd, rom_hit;
    logic [19:0] rom_addr;
    logic [7:0]  rom_q;
    logic        ext_rd, ext_wr;
    logic [15:0] ext_a;
    logic [7:0]  ext_wdata, ext_rdata;

    taitol_main u_main (
        .clk(clk), .rst(rst), .cen(cen_cpu),
        .rom_rd(rom_rd), .rom_addr(rom_addr), .rom_hit(rom_hit), .rom_q(rom_q), .rom_mask(cfg_rmask), .rom_bitrev(cfg_flags[0]),
        .ext_rd(ext_rd), .ext_wr(ext_wr), .ext_a(ext_a), .ext_wdata(ext_wdata), .ext_rdata(ext_rdata),
        .v_addr(v_addr), .v_we(v_we), .v_wdata(v_wdata), .v_rdata(v_rdata),
        .vreg4(vreg4), .tbank(tbank),
        .ls_pulse(ls_pulse), .ln_new(ln_new),
        .dbg_irq(dbg_irq), .dbg_m1(dbg_m1)
    );

`ifdef IDEAL_ROM
    // simulation experiment only: the program ROM answers at once from a behavioural array (no cache, no wait states)
    logic [7:0] ideal [0:262143];
    initial $readmemh("ideal_prog.hex", ideal);
    assign rom_hit = 1'b1;
    assign rom_q   = ideal[rom_addr[17:0]];
    assign p_req = 1'b0; assign p_addr = '0;
`else
    taitol_cache #(.AB(20)) u_cache (
        .clk(clk), .inval(cache_inval), .rd(rom_rd), .addr(rom_addr), .hit(rom_hit), .data(rom_q),
        .fill_req(p_req), .fill_addr(p_addr), .fill_wr(p_wr), .fill_idx(p_idx), .fill_data(p_data), .fill_done(p_done)
    );
`endif

    // ---------------------------------------------------------------- the board and the sound
    logic signed [15:0] snd;
    logic        snd_sample;
    taitol_board u_board (
        .clk(clk), .clk_ym(clk_ym), .rst(rst), .cen_ym(cen_ym1), .cen_mcu(cen_mcu), .board(cfg_board),
        .ext_rd(ext_rd), .ext_wr(ext_wr), .ext_a(ext_a), .ext_wdata(ext_wdata), .ext_rdata(ext_rdata),
        .dswa(dswa), .dswb(dswb), .in0(in0), .in1(in1), .in2(in2),
        .mcu_we(mcu_we), .mcu_waddr(mcu_waddr), .mcu_wdata(mcu_wdata),
        .cache_inval(cache_inval),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
        .m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done),
        .sub_we(sub_we), .sub_waddr(sub_waddr), .sub_wdata(sub_wdata),
        .cen_ym2(cen_ym2), .cen_sub(cen_z80b), .vbl_pulse(copy),
        .tb_add_x(tb_add_x), .tb_dx(tb_dx), .tb_add_y(tb_add_y), .tb_dy(tb_dy), .gbank(gbank),
        .snd(snd), .snd_sample(snd_sample), .dbg_ym_wr(dbg_ym_wr), .dbg_ym_a0(dbg_ym_a0), .dbg_ym_a1(dbg_ym_a1), .dbg_pcm_max(dbg_pcm_max), .dbg_ym_d(dbg_ym_d)
    );
    // jt03's mix is 10.5 dB (x3.33) below MAME's for the same register writes: measured in simulation on the real
    // program (tools/audiocmp.py on 5 s of Plotting's coin sound and music: the energy ratio is the same -10 dB in every
    // frequency band, SSG and FM alike, so it is one constant). 853 / 256 = 3.332.
    wire signed [26:0] snd_x = snd * 11'sd853;
    wire signed [18:0] snd_g = snd_x >>> 8;
    wire signed [15:0] snd_c = (snd_g > 19'sd32767) ? 16'sd32767 : (snd_g < -19'sd32768) ? -16'sd32768 : snd_g[15:0];
    always_ff @(posedge clk) begin
        snd_valid <= snd_sample;
        if (snd_sample) begin snd_l <= snd_c; snd_r <= snd_c; end
    end
    wire unused = ^{frame_pulse, cen_ym2610};
endmodule
`default_nettype wire
