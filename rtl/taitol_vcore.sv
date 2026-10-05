// The TC0090LVC's video half: the video RAMs behind the CPU's window, four line renderers (two BG layers, the text
// layer, sprites), the raster, line buffers and mixer. clk 96 MHz (machine), clk_vid 26.66112 MHz (raster).
//
// A raster line is drawn while the one before it is shown: when line k starts, line k + 1 is started in the
// renderers (the last line of the frame, 261, draws line 0 of the next, which is not visible, so nothing is
// started for it). Lines 16..239 are the visible ones.
`default_nettype none
module taitol_vcore #(
    parameter [24:1] GFX_BASE = 24'h080000
) (
    input  logic        clk,
    input  logic        clk_vid,
    input  logic        rst,

    // the CPU's window onto the chip's VRAM space
    input  logic [19:0] v_addr,
    input  logic        v_we,
    input  logic [7:0]  v_wdata,
    output logic [7:0]  v_rdata,

    // video registers
    input  logic [7:0]  vreg4,                    // [5] screen enable [4] flip [3] BG0 priority
    input  logic [31:0] tbank,                    // registers 3..0
    input  logic        copy,                     // latch the sprite RAM (start of vblank)
    input  logic        scr_latch,                // latch the BG scroll registers there too (OSD option)

    // graphics ROM geometry (8x8 tiles; sprite codes are in 16x16 blocks of four)
    input  logic [17:0] gfx_pmask,
    input  logic [16:0] gfx_n,
    input  logic [7:0]  gbank,                    // graphics bank (Horseshoes)

    // graphics ROM bursts of 2 words
    output logic        g0_req, output logic [24:1] g0_addr,
    input  logic        g0_wr,  input logic [1:0] g0_idx, input logic [15:0] g0_data, input logic g0_done,
    output logic        g1_req, output logic [24:1] g1_addr,
    input  logic        g1_wr,  input logic [1:0] g1_idx, input logic [15:0] g1_data, input logic g1_done,
    output logic        gs_req, output logic [24:1] gs_addr,
    input  logic        gs_wr,  input logic [1:0] gs_idx, input logic [15:0] gs_data, input logic gs_done,

    // the picture
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,

    // raster events (machine clock)
    output logic        ls_pulse,                 // a raster line starts ...
    output logic        frame_pulse,              // ... line 0 of the frame
    output logic [8:0]  ln_new,                   // its number (valid with ls_pulse)
    output logic        vb_next,                  // (clk_vid) the next line is in the vertical blank

    // debug
    output logic        dbg_ovr_bg0, dbg_ovr_bg1, dbg_ovr_tx, dbg_ovr_spr,
    output logic        busy_bg0, busy_bg1, busy_tx, busy_spr
);
    wire flip = vreg4[4];
    wire bm_mode = (vreg4[2:0] == 3'd7);

    // ------------------------------------------------------------ memories
    logic [15:0] bg0_sx, bg1_sx;
    logic [7:0]  bg0_sy, bg1_sy;
    logic [7:0]  pal_addr;
    logic [16:0] bm_addr;
    logic [7:0]  bm_q;
    logic [15:0] pal_q;
    logic [15:0] tx_addr;
    logic [7:0]  tx_q;
    logic [10:0] bg0_maddr, bg1_maddr;
    logic [15:0] bg0_mq, bg1_mq;
    logic [6:0]  sp_addr;
    logic [63:0] sp_q;
    taitol_vmem u_vmem (
        .clk(clk), .v_addr(v_addr), .v_we(v_we), .v_wdata(v_wdata), .v_rdata(v_rdata),
        .scr_latch(scr_latch), .bg0_sx(bg0_sx), .bg1_sx(bg1_sx), .bg0_sy(bg0_sy), .bg1_sy(bg1_sy),
        .bm_addr(bm_addr), .bm_q(bm_q),
        .pal_clk(clk_vid), .pal_addr(pal_addr), .pal_q(pal_q),
        .tx_addr(tx_addr), .tx_q(tx_q),
        .bg0_addr(bg0_maddr), .bg0_q(bg0_mq), .bg1_addr(bg1_maddr), .bg1_q(bg1_mq),
        .copy(copy), .sp_addr(sp_addr), .sp_q(sp_q)
    );

    // ------------------------------------------------------------ raster and mixer
    logic        bg1_we, bg0_we, tx_we, sp_we;
    logic [9:0]  bg1_wa, bg0_wa, tx_wa, sp_wa;
    logic [7:0]  bg1_wd, bg0_wd, tx_wd;
    logic        bg1r_we, bmr_we;                // BG1 renderer / bitmap renderer writes into the BG1 line buffer
    logic [9:0]  bg1r_wa, bmr_wa;
    logic [7:0]  bg1r_wd, bmr_wd;
    assign bg1_we = bm_mode ? bmr_we : bg1r_we;
    assign bg1_wa = bm_mode ? bmr_wa : bg1r_wa;
    assign bg1_wd = bm_mode ? bmr_wd : bg1r_wd;
    logic [9:0]  sp_wd;
    taitol_video u_video (
        .clk_vid(clk_vid), .clk_sys(clk),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .ls_pulse(ls_pulse), .frame_pulse(frame_pulse), .ln_out(ln_new), .vb_next(vb_next),
        .bg1_we(bg1_we), .bg1_waddr(bg1_wa), .bg1_wdata(bg1_wd),
        .bg0_we(bg0_we), .bg0_waddr(bg0_wa), .bg0_wdata(bg0_wd),
        .tx_we(tx_we),   .tx_waddr(tx_wa),   .tx_wdata(tx_wd),
        .sp_we(sp_we),   .sp_waddr(sp_wa),   .sp_wdata(sp_wd),
        .scr_en(vreg4[5]), .bg0_pri(vreg4[3]), .bm_mode(bm_mode),
        .pal_raddr(pal_addr), .pal_rdata(pal_q)
    );

    // ------------------------------------------------------------ which line to draw
    logic [8:0] lk = 9'd0;                                    // the last line seen (debug); ln_new comes exact from the raster
    wire  [8:0] tgt = (ln_new == 9'd261) ? 9'd0 : ln_new + 9'd1;
    logic       r_start = 1'b0;
    logic [8:0] r_line;
    logic       r_bank;
    always_ff @(posedge clk) begin
        r_start <= 1'b0;
        if (ls_pulse) begin
            lk <= ln_new;
            if (tgt >= 9'd16 && tgt <= 9'd239) begin r_start <= 1'b1; r_line <= tgt; r_bank <= tgt[0]; end
        end
    end

    // ------------------------------------------------------------ the renderers
    taitol_bg #(.KN(9'd28), .KF(9'd331), .GFX_BASE(GFX_BASE)) u_bg0 (
        .clk(clk), .rst(rst), .start(r_start), .line(r_line), .bank(r_bank), .busy(busy_bg0), .overrun(dbg_ovr_bg0),
        .flip(flip), .sx(bg0_sx), .sy(bg0_sy), .tbank(tbank), .gfx_pmask(gfx_pmask), .gfx_n(gfx_n), .gbank(gbank),
        .map_addr(bg0_maddr), .map_q(bg0_mq),
        .m_req(g0_req), .m_addr(g0_addr), .m_wr(g0_wr), .m_idx(g0_idx), .m_data(g0_data), .m_done(g0_done),
        .lb_we(bg0_we), .lb_addr(bg0_wa), .lb_data(bg0_wd)
    );
    taitol_bg #(.KN(9'd38), .KF(9'd341), .GFX_BASE(GFX_BASE)) u_bg1 (
        .clk(clk), .rst(rst), .start(r_start), .line(r_line), .bank(r_bank), .busy(busy_bg1), .overrun(dbg_ovr_bg1),
        .flip(flip), .sx(bg1_sx), .sy(bg1_sy), .tbank(tbank), .gfx_pmask(gfx_pmask), .gfx_n(gfx_n), .gbank(gbank),
        .map_addr(bg1_maddr), .map_q(bg1_mq),
        .m_req(g1_req), .m_addr(g1_addr), .m_wr(g1_wr), .m_idx(g1_idx), .m_data(g1_data), .m_done(g1_done),
        .lb_we(bg1r_we), .lb_addr(bg1r_wa), .lb_data(bg1r_wd)
    );
    taitol_bm u_bm (
        .clk(clk), .start(r_start & bm_mode), .line(r_line), .bank(r_bank), .flip(flip),
        .rd_addr(bm_addr), .rd_q(bm_q), .lb_we(bmr_we), .lb_addr(bmr_wa), .lb_data(bmr_wd)
    );
    taitol_tx u_tx (
        .clk(clk), .rst(rst), .start(r_start), .line(r_line), .bank(r_bank), .busy(busy_tx), .overrun(dbg_ovr_tx),
        .flip(flip), .vr_addr(tx_addr), .vr_q(tx_q),
        .lb_we(tx_we), .lb_addr(tx_wa), .lb_data(tx_wd)
    );
    taitol_spr #(.GFX_BASE(GFX_BASE)) u_spr (
        .clk(clk), .rst(rst), .start(r_start), .line(r_line), .bank(r_bank), .busy(busy_spr), .overrun(dbg_ovr_spr),
        .flip(flip), .gfx_pmask16(gfx_pmask[17:2]), .gfx_n16(gfx_n[16:2]), .gbank(gbank),
        .sp_addr(sp_addr), .sp_q(sp_q),
        .m_req(gs_req), .m_addr(gs_addr), .m_wr(gs_wr), .m_idx(gs_idx), .m_data(gs_data), .m_done(gs_done),
        .lb_we(sp_we), .lb_addr(sp_wa), .lb_data(sp_wd)
    );
endmodule
`default_nettype wire
