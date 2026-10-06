//============================================================================
//
//  Taito L System (TC0090LVC) for MiSTer: Plotting, Flipull, ... (see README).
//
//  Written for MiSTer from MAME's driver (src/mame/taito/taito_l.cpp, src/devices/machine/tc009xlvc.cpp). The
//  platform layer (SDRAM controller, loader, arbiter, line-buffer raster) follows the MCatAdv core's; the CPU
//  (tv80, Guy Hutchison) and the YM2203 (jt03/jt49, Jose Tejada) are open-source cores.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;       // signed samples
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

// the DDR3 is only the rotated games' frame buffer (screen_rotate, below)
assign FB_FORCE_BLANK = 1'b0;

//////////////////////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

wire  [1:0] ar = status[122:121];
wire        video_rotated;
assign VIDEO_ARX = (!ar) ? (video_rotated ? 13'd3 : 13'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (video_rotated ? 13'd4 : 13'd3) : 13'd0;

`include "build_id.v"
localparam CONF_STR = {
	"TaitoL;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"H0O[13],Vertical games,Rotated,As is;",
	"O[19],BG scroll update,Live,At vblank;",
	"O[17:16],Trackball invert,None,Horizontal,Vertical,Both;",
	"-;",
	"DIP;",
	"-;",
	"P1,CRT Adjust;",
	"P1O[96],CRT Adjust,Off,On;",
	"H1P1O[116:112],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[104:101],CRT H-Position,0,+6,+12,+18,+24,+30,+36,+42,-48,-42,-36,-30,-24,-18,-12,-6;",
	"H1P1O[27:22],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"O[20],SDRAM read capture,Normal,Late;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Start,Coin;",
	"jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;           // 96 MHz: the machine
wire clk_sdram;         // 96 MHz, shifted: the SDRAM chip's clock pin
wire clk_ym;            // 48 MHz, in phase with clk_sys: Raimais' YM2610
wire clk_vid;           // 26.66112 MHz: the raster (pixel clock = this / 4 = 6.66528 MHz)
wire pll_locked;

wire pll_locked_sys, pll_locked_vid;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.outclk_2(clk_ym),
	.locked(pll_locked_sys)
);
pll_vid pll_vid
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
	.locked(pll_locked_vid)
);
assign pll_locked = pll_locked_sys & pll_locked_vid;

///////////////////////////////////////////////////

wire         ioctl_download;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;
wire  [24:0] ps2_mouse;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, ~status[96], direct_video}),     // H0: hidden with direct video; H1: the CRT Adjust amounts while it is Off
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.video_rotated(video_rotated),
	.gamma_bus(gamma_bus),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
);

///////////////////////   DIP SWITCHES (from the MRA)   ///////////////////////

reg [7:0] sw[8];
integer sw_i;
initial for (sw_i = 0; sw_i < 8; sw_i = sw_i + 1) sw[sw_i] = 8'hFF;      // MAME's defaults until the MRA sends its own
always @(posedge clk_sys) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[26:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;
end

///////////////////////   CONTROLS   ///////////////////////

// keyboard: 1/2 start, 5/6 coin, 9 service (MAME's defaults)
reg key_start1, key_start2, key_coin1, key_coin2, key_service;
always @(posedge clk_sys) begin
	reg old_stb;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		case (ps2_key[7:0])
			8'h16: key_start1  <= ps2_key[9];
			8'h1E: key_start2  <= ps2_key[9];
			8'h2E: key_coin1   <= ps2_key[9];
			8'h36: key_coin2   <= ps2_key[9];
			8'h46: key_service <= ps2_key[9];
			default: ;
		endcase
	end
end

// joystick bits: 0 right, 1 left, 2 down, 3 up, 4-5 buttons 1-2, 6 start, 7 coin
wire j1_r = joystick_0[0], j1_l = joystick_0[1], j1_d = joystick_0[2], j1_u = joystick_0[3];
wire j1_b1 = joystick_0[4] | ps2_mouse[0], j1_b2 = joystick_0[5] | ps2_mouse[1];     // the mouse buttons too (Horseshoes)
wire j1_start = joystick_0[6] | key_start1, j1_coin = joystick_0[7] | key_coin1;
wire j2_r = joystick_1[0], j2_l = joystick_1[1], j2_d = joystick_1[2], j2_u = joystick_1[3];
wire j2_b1 = joystick_1[4], j2_b2 = joystick_1[5];
wire j2_start = joystick_1[6] | key_start2, j2_coin = joystick_1[7] | key_coin2;

// Which bit of the board's input ports carries what is per game, and comes from MAME through the ROM image's configuration
// block (tools/inputmap.py); taitol_ctrl builds IN0..IN2 from these signals.
reg [31:0] sig;
always @* begin
	sig = 32'd0;
	sig[1] = j1_u;  sig[2] = j1_d;  sig[3] = j1_l;  sig[4] = j1_r;  sig[5] = j1_b1;  sig[6] = j1_b2;
	sig[8] = j2_u;  sig[9] = j2_d;  sig[10] = j2_l; sig[11] = j2_r; sig[12] = j2_b1;  sig[13] = j2_b2;
	sig[15] = j1_coin;  sig[16] = j2_coin;  sig[17] = j1_start;  sig[18] = j2_start;  sig[19] = key_service;
end
// American Horseshoes' trackball (uPD4701A): the mouse, or the joystick as a slow ball. In MAME the chip's X counter is the
// analog port AN0 = trackball Y (reversed) and its Y counter AN1 = trackball X, so the mouse's vertical movement (PS/2: up is
// positive) feeds X and its horizontal movement feeds Y. [17:16] inverts either if the ball runs the wrong way.
wire signed [8:0] mouse_dx = {ps2_mouse[4], ps2_mouse[15:8]};
wire signed [8:0] mouse_dy = {ps2_mouse[5], ps2_mouse[23:16]};
reg         tb_add_x, tb_add_y;
reg  signed [8:0] tb_dx, tb_dy;
reg  [16:0] tb_tick;                                   // the joystick: one count every 1/1200 s
always @(posedge clk_sys) begin
	reg old_m;
	tb_add_x <= 1'b0; tb_add_y <= 1'b0;
	old_m <= ps2_mouse[24];
	tb_tick <= (tb_tick == 17'd79999) ? 17'd0 : tb_tick + 1'd1;
	if (old_m != ps2_mouse[24]) begin
		tb_add_x <= 1'b1; tb_dx <= status[17] ? -mouse_dy : mouse_dy;
		tb_add_y <= 1'b1; tb_dy <= status[16] ? -mouse_dx : mouse_dx;
	end else if (tb_tick == 17'd0) begin
		if (j1_u ^ j1_d) begin tb_add_x <= 1'b1; tb_dx <= (j1_u ^ status[17]) ? 9'sd1 : -9'sd1; end
		if (j1_l ^ j1_r) begin tb_add_y <= 1'b1; tb_dy <= (j1_r ^ status[16]) ? 9'sd1 : -9'sd1; end
	end
end

wire [119:0] cfg_in_id;
wire  [23:0] cfg_in_idle;
wire   [7:0] in0, in1, in2;
taitol_ctrl u_ctrl (.id_flat(cfg_in_id), .idle(cfg_in_idle), .sig(sig), .in0(in0), .in1(in1), .in2(in2));

///////////////////////   MEMORY   ///////////////////////

// the ROM image: MRA index 0
wire        rom_dl = ioctl_download && (ioctl_index[7:0] == 8'd0);
wire        dl_we  = rom_dl && ioctl_wr;

wire        mem_init = ~pll_locked | RESET;
wire        mem_ready;

wire        p_req, g0_req, g1_req, gs_req, s_req, a_req, m_req;
wire [18:4] m_addr;
wire        m_wr, m_done;
wire  [2:0] m_idx;
wire [15:0] m_data;
wire [19:4] p_addr;
wire [16:4] s_addr;
wire [15:4] a_addr;
wire        s_wr, a_wr, s_done, a_done;
wire  [2:0] s_idx, a_idx;
wire [15:0] s_data, a_data;
wire [24:1] g0_addr, g1_addr, gs_addr;
wire        p_wr, g0_wr, g1_wr, gs_wr, p_done, g0_done, g1_done, gs_done;
wire  [2:0] p_idx;
wire  [1:0] g0_idx, g1_idx, gs_idx;
wire [15:0] p_data, g0_data, g1_data, gs_data;
wire        dl_busy;
wire  [3:0] cfg_board;
wire [15:0] cfg_n8;
wire [17:0] cfg_pmask;
wire [19:0] cfg_rmask;
wire  [1:0] cfg_rot;
wire  [7:0] cfg_flags;
wire        mcu_we;
wire [10:0] mcu_waddr;
wire  [7:0] mcu_wdata;
wire        sub_we;
wire [15:0] sub_waddr;
wire  [7:0] sub_wdata;

taitol_mem u_mem
(
	.clk(clk_sys), .clk_sdram(clk_sdram), .init(mem_init), .rd_late(status[20]), .ready(mem_ready),
	.dl_we(dl_we), .dl_addr(ioctl_addr[24:0]), .dl_data(ioctl_dout), .dl_wait(ioctl_wait), .dl_busy(dl_busy),
	.cfg_board(cfg_board), .cfg_n8(cfg_n8), .cfg_pmask(cfg_pmask), .cfg_rmask(cfg_rmask), .cfg_rot(cfg_rot), .cfg_flags(cfg_flags),
	.cfg_in_id(cfg_in_id), .cfg_in_idle(cfg_in_idle), .mcu_we(mcu_we), .mcu_waddr(mcu_waddr), .mcu_wdata(mcu_wdata),
	.sub_we(sub_we), .sub_waddr(sub_waddr), .sub_wdata(sub_wdata),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
	.m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done),
	.g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
	.g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
	.gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

///////////////////////   THE MACHINE   ///////////////////////

wire        reset_sw = RESET | status[0] | buttons[1];
// the machine is held while a ROM loads and until the memory is up; registered, it fans out to the whole core
reg         mc_rst = 1'b1, vid_rst = 1'b1;
always @(posedge clk_sys) begin
	mc_rst  <= reset_sw | rom_dl | dl_busy | ~mem_ready | ~pll_locked;
	vid_rst <= rom_dl | dl_busy | ~mem_ready | ~pll_locked;
end

wire        ce_pix, hblank, vblank, hsync, vsync, vb_next;
wire [23:0] rgb;
wire signed [15:0] snd_l, snd_r;
wire        snd_valid;
wire        dbg_ovr, dbg_irq, dbg_m1, dbg_ym_wr;

taitol_core u_core
(
	.clk(clk_sys), .clk_ym(clk_ym), .clk_vid(clk_vid), .rst(mc_rst), .vid_rst(vid_rst),
	.cache_inval(rom_dl | mem_init),
	.cfg_board(cfg_board), .cfg_pmask(cfg_pmask), .cfg_n8({1'b0, cfg_n8}), .cfg_rmask(cfg_rmask), .cfg_flags(cfg_flags), .opt_scr_latch(status[19]),
	.p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
	.s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
	.a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
	.m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done),
	.g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
	.g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
	.gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
	.dswa(sw[0]), .dswb(sw[1]), .in0(in0), .in1(in1), .in2(in2),
	.mcu_we(mcu_we), .mcu_waddr(mcu_waddr), .mcu_wdata(mcu_wdata),
	.sub_we(sub_we), .sub_waddr(sub_waddr), .sub_wdata(sub_wdata),
	.tb_add_x(tb_add_x), .tb_add_y(tb_add_y), .tb_dx(tb_dx), .tb_dy(tb_dy),
	.ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .vb_next(vb_next), .rgb(rgb),
	.snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
	.dbg_ovr(dbg_ovr), .dbg_irq(dbg_irq), .dbg_m1(dbg_m1), .dbg_ym_wr(dbg_ym_wr)
);

///////////////////////   AUDIO   ///////////////////////

reg [15:0] aud_l, aud_r;
always @(posedge clk_sys) if (snd_valid) begin aud_l <= snd_l; aud_r <= snd_r; end
assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

///////////////////////   VIDEO   ///////////////////////

// CRT Adjust (rmonic79's module, as in the owner's other cores): H-Size / H-Position / V-Shift for a 15 kHz CRT. Off = the native stream.
reg  vsync_d = 1'b0;
always @(posedge clk_vid) vsync_d <= vsync;
wire        frame_event = vsync && !vsync_d;            // once per frame, inside the vertical blank
wire        av_ce, av_hb, av_vb, av_hs, av_vs;
wire [23:0] av_rgb;
taitol_crt_adjust #(.SYS_HZ(26_661_120), .PIX_DIV(4), .HTOTAL(424), .VTOTAL(262)) crt_adjust
(
	.clk_sys(clk_vid),
	.ce_pix(ce_pix),
	.frame_event(frame_event),
	.osd_on(status[96]),
	.osd_hsize(status[116:112]),
	.osd_hpos(status[104:101]),
	.osd_vshift(status[27:22]),
	.sd_off((status[5:3] == 3'd0) && !forced_scandoubler),
	.rgb_in(rgb),
	.hblank_in(hblank),
	.vblank_in(vblank),
	.hsync_in(hsync),
	.vsync_in(vsync),
	.vb_next_in(vb_next),
	.ce_out(av_ce),
	.rgb_out(av_rgb),
	.hblank_out(av_hb),
	.vblank_out(av_vb),
	.hsync_out(av_hs),
	.vsync_out(av_vs),
	.active()
);

arcade_video #(.WIDTH(320), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_vid),
	.ce_pix(av_ce),
	.RGB_in(av_rgb),
	.HBlank(av_hb),
	.VBlank(av_vb),
	.HSync(av_hs),
	.VSync(av_vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// ROT90 / ROT270 sets (Play Girls, American Horseshoes, Fighting Hawk, Evil Stone ...: the ROM image carries MAME's rotation)
// are turned in a DDR3 frame buffer (Sorgelig's screen_rotate: it takes arcade_video's output; MAME's ROT270 = the picture turned 90 degrees
// counter-clockwise, ROT90 = clockwise). Direct Video bypasses it (no frame buffer: the stream goes out as it is, and the display turns it),
// so a display that turns the picture the other way is served by the game's own Flip Screen DIP switch (an exact 180 degree turn).
wire rotate_ccw = (cfg_rot == 2'd3);
wire no_rotate  = ~cfg_rot[0] | status[13] | direct_video;
wire flip       = (cfg_rot == 2'd2);
screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw), .no_rotate(no_rotate), .flip(flip), .video_rotated(video_rotated),
	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE), .DDRAM_RD(DDRAM_RD)
);

///////////////////////   LED   ///////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = mc_rst ? act_cnt[24] : dbg_ovr ? act_cnt[22] : ~dbg_irq | act_cnt[26];

endmodule
