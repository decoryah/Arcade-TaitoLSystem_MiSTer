// CRT Adjust bench: the raster (taitol_video, line buffers idle: a flat colour) through taitol_crt_adjust, to check the HSync / VSync
// shifts and the pixel clock enable of the adjusted stream against the native one.
`default_nettype none
module tb_crt_top (
    input  logic clk_vid,
    input  logic clk_sys,
    input  logic osd_on,
    input  logic [4:0] osd_hsize,
    input  logic [3:0] osd_hpos,
    input  logic [5:0] osd_vshift,
    output logic ce_pix, hsync, vsync, hblank, vblank,
    output logic av_ce, av_hs, av_vs, av_hb, av_vb,
    output logic [23:0] av_rgb
);
    logic [23:0] rgb;
    logic ls_pulse, frame_pulse, vb_next;
    logic [8:0] ln_out;
    logic [7:0] pal_raddr;
    taitol_video u_v (
        .clk_vid(clk_vid), .clk_sys(clk_sys),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .ls_pulse(ls_pulse), .frame_pulse(frame_pulse), .ln_out(ln_out), .vb_next(vb_next),
        .bg1_we(1'b0), .bg1_waddr(10'd0), .bg1_wdata(8'd0), .bg0_we(1'b0), .bg0_waddr(10'd0), .bg0_wdata(8'd0),
        .tx_we(1'b0), .tx_waddr(10'd0), .tx_wdata(8'd0), .sp_we(1'b0), .sp_waddr(10'd0), .sp_wdata(10'd0),
        .scr_en(1'b1), .bg0_pri(1'b0), .bm_mode(1'b0), .pal_raddr(pal_raddr), .pal_rdata(16'h7FFF)
    );
    logic vsync_d = 1'b0;
    always_ff @(posedge clk_vid) vsync_d <= vsync;
    taitol_crt_adjust #(.SYS_HZ(26_661_120), .PIX_DIV(4), .HTOTAL(424), .VTOTAL(262)) u_crt (
        .clk_sys(clk_vid), .ce_pix(ce_pix), .frame_event(vsync & ~vsync_d),
        .osd_on(osd_on), .osd_hsize(osd_hsize), .osd_hpos(osd_hpos), .osd_vshift(osd_vshift), .sd_off(1'b1),
        .rgb_in(rgb), .hblank_in(hblank), .vblank_in(vblank), .hsync_in(hsync), .vsync_in(vsync), .vb_next_in(vb_next),
        .ce_out(av_ce), .rgb_out(av_rgb), .hblank_out(av_hb), .vblank_out(av_vb), .hsync_out(av_hs), .vsync_out(av_vs), .active()
    );
endmodule
`default_nettype wire
