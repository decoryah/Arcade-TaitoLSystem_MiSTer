// Raster, line buffers, priority mix and palette lookup (the display side of the TC0090LVC).
//
// Pixel clock = clk_vid / 4 = 26.66112 / 4 = 6.66528 MHz, the board's 13.33056 MHz oscillator / 2.
// MAME does not model the blanking (its screen is "60 Hz, 320 x 256, visible 320 x 224 from line 16"), so the totals
// are a choice: 424 x 262 is exactly 60.000 Hz at this pixel clock. The raster line counter is MAME's bitmap line:
// 0..261, visible lines 16..239; the CPU's interrupt levels are tied to those numbers (taitol_main).
//
// The renderers (clk_sys) fill one bank of the line buffers a line ahead of the display, which reads the other.
// Line buffer entries (8 bit {colour, pen}; sprites 10 bit {claimed, hide, colour, pen}); the mix is
// tc0090lvc_device::screen_update:  text > sprite > BG0 > BG1, where a sprite whose colour has bit 3 set is hidden
// by an opaque BG0 pixel unless the "BG0 priority" bit of video register 4 is set; pen 0 of BG0/text is transparent.
`default_nettype none
module taitol_video (
    input  logic        clk_vid,
    input  logic        clk_sys,

    // raster out (clk_vid)
    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,

    // raster events in the machine clock domain: one-cycle pulses
    output logic        ls_pulse,         // a raster line starts
    output logic        frame_pulse,      // line 0 starts (together with ls_pulse)
    output logic [8:0]  ln_out,           // the number of the line that starts: valid with ls_pulse, held until the next one
    output logic        vb_next,          // (clk_vid) the next raster line is in the vertical blank (CRT Adjust)

    // renderer write ports (clk_sys); bit 9 of the address selects the bank
    input  logic        bg1_we, input logic [9:0] bg1_waddr, input logic [7:0] bg1_wdata,
    input  logic        bg0_we, input logic [9:0] bg0_waddr, input logic [7:0] bg0_wdata,
    input  logic        tx_we,  input logic [9:0] tx_waddr,  input logic [7:0] tx_wdata,
    input  logic        sp_we,  input logic [9:0] sp_waddr,  input logic [9:0] sp_wdata,

    // control bits (video register 4), any clock
    input  logic        scr_en,
    input  logic        bg0_pri,
    input  logic        bm_mode,          // 8 bit bitmap mode: only the BG1 line buffer (the bitmap) is shown

    // palette RAM read port (clk_vid)
    output logic [7:0]  pal_raddr,
    input  logic [15:0] pal_rdata
);
    localparam H_ACT = 320, H_TOT = 424, V_TOT = 262, V_FIRST = 16, V_LAST = 239;
    localparam H_SYNC0 = 344, H_SYNC1 = 376;           // 32 pixels, 24 after the picture, 48 before the next
    localparam V_SYNC0 = 244, V_SYNC1 = 247;           // 3 lines, 4 after the picture, 15 before the next

    // ------------------------------------------------------------ raster
    logic [1:0] ph = 2'd0;
    logic [8:0] hc = 9'd0, vc = 9'd0;
    always_ff @(posedge clk_vid) begin
        ph <= ph + 2'd1;
        ce_pix <= (ph == 2'd3);
        if (ph == 2'd3) begin
            if (hc == H_TOT - 1) begin
                hc <= 9'd0;
                vc <= (vc == V_TOT - 1) ? 9'd0 : vc + 9'd1;
            end else hc <= hc + 9'd1;
        end
    end

    wire [8:0] vcn = (vc == V_TOT - 1) ? 9'd0 : vc + 9'd1;
    assign vb_next = (vcn < V_FIRST) || (vcn > V_LAST);

    // sync and blanking, registered with the pixel
    logic [8:0] hn, vn;                                // the counters at the next pixel
    always_comb begin
        hn = (hc == H_TOT - 1) ? 9'd0 : hc + 9'd1;
        vn = (hc == H_TOT - 1) ? ((vc == V_TOT - 1) ? 9'd0 : vc + 9'd1) : vc;
    end
    always_ff @(posedge clk_vid) if (ph == 2'd3) begin
        hblank <= (hn >= H_ACT);
        vblank <= (vn < V_FIRST) || (vn > V_LAST);
        hsync  <= (hn >= H_SYNC0) && (hn < H_SYNC1);
        vsync  <= (vn >= V_SYNC0) && (vn < V_SYNC1);
    end

    // The raster line starts, to the machine clock: a toggle per line, and the NUMBER of the line that starts, held beside it (it
    // changes with the toggle and then stays for a whole line, so the machine side reads it after the toggle has come through the
    // synchroniser). The first versions sent a second toggle for line 0 and counted lines on this side; the two toggles change on the
    // same video clock edge but could be seen one machine clock apart, and then the counter ran away (line 0 is never seen together
    // with a line pulse) for as long as that phase relation lasted. A frame is exactly 1,600,000 machine clocks, so the relation is
    // fixed until the PLLs are locked again: on a real MiSTer the picture shook and flickered for the whole session, with a random
    // chance (the lock phase) on every start. The number sent is exact: nothing is counted on this side any more.
    logic tg_ls = 1'b0;
    logic [8:0] ln_hold = 9'd0;
    always_ff @(posedge clk_vid) if (ph == 2'd3 && hn == 9'd0) begin
        tg_ls   <= ~tg_ls;
        ln_hold <= vn;
    end
    logic [3:0] s_ls;
    logic [8:0] ln_q1, ln_q2;
    always_ff @(posedge clk_sys) begin
        s_ls  <= {s_ls[2:0], tg_ls};
        ln_q1 <= ln_hold;
        ln_q2 <= ln_q1;
        ls_pulse    <= s_ls[3] ^ s_ls[2];
        frame_pulse <= (s_ls[3] ^ s_ls[2]) && (ln_q2 == 9'd0);
    end
    assign ln_out = ln_q2;

    // control bits into the video clock
    logic [1:0] s_en, s_pri, s_bm;
    always_ff @(posedge clk_vid) begin
        s_en  <= {s_en[0],  scr_en};
        s_pri <= {s_pri[0], bg0_pri};
        s_bm  <= {s_bm[0],  bm_mode};
    end

    // ------------------------------------------------------------ line buffers
    logic [9:0]  rd_addr;                              // {bank, x}
    logic [7:0]  q_bg1, q_bg0, q_tx;
    logic [9:0]  q_sp;
    taitol_sdp2 #(.AW(10), .DW(8))  u_bg1 (.wclk(clk_sys), .we(bg1_we), .waddr(bg1_waddr), .wdata(bg1_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_bg1));
    taitol_sdp2 #(.AW(10), .DW(8))  u_bg0 (.wclk(clk_sys), .we(bg0_we), .waddr(bg0_waddr), .wdata(bg0_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_bg0));
    taitol_sdp2 #(.AW(10), .DW(8))  u_tx  (.wclk(clk_sys), .we(tx_we),  .waddr(tx_waddr),  .wdata(tx_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_tx));
    taitol_sdp2 #(.AW(10), .DW(10)) u_sp  (.wclk(clk_sys), .we(sp_we),  .waddr(sp_waddr),  .wdata(sp_wdata),
                                           .rclk(clk_vid), .raddr(rd_addr), .rdata(q_sp));

    // ------------------------------------------------------------ display pipeline
    // Pixel P is registered into rgb at the edge that makes it the current pixel (end of phase 3 of the period
    // before it), so its line buffer address is set two edges earlier: at the end of phase 3 of the period before
    // that. Phase 0: the address is visible; end of 0: the line buffers capture it; phase 1: mix, palette address
    // registered; end of 2: the palette captures it; phase 3: its data.
    wire        wrap = (hn == H_TOT - 1);
    wire [8:0]  hn2  = wrap ? 9'd0 : hn + 9'd1;               // the pixel after the next
    always_ff @(posedge clk_vid) begin
        if (ph == 2'd3) rd_addr <= {wrap ? ~vn[0] : vn[0], hn2};
    end

    wire        bg0_op    = |q_bg0[3:0];
    wire        tx_op     = |q_tx[3:0];
    wire        bg0_front = bg0_op & ~s_pri[1];                // BG0 priority class 1: hides "hideable" sprites
    wire        spr_show  = q_sp[9] & ~(q_sp[8] & bg0_front);
    wire [7:0]  mix_pen   = s_bm[1] ? q_bg1 : tx_op ? q_tx : spr_show ? q_sp[7:0] : bg0_op ? q_bg0 : q_bg1;

    always_ff @(posedge clk_vid) if (ph == 2'd1) pal_raddr <= mix_pen;

    // palette entry: xBGRBBBBGGGGRRRR, 5 bits a channel with the low bits in bits 12..14 (MAME's xBGRBBBBGGGGRRRR_bit0)
    wire [4:0] cr = {pal_rdata[3:0],  pal_rdata[12]};
    wire [4:0] cg = {pal_rdata[7:4],  pal_rdata[13]};
    wire [4:0] cb = {pal_rdata[11:8], pal_rdata[14]};
    always_ff @(posedge clk_vid) if (ph == 2'd3) begin
        rgb <= s_en[1] ? {cr, cr[4:2], cg, cg[4:2], cb, cb[4:2]} : 24'd0;
    end
endmodule
`default_nettype wire
