// Frozen-state video bench: taitol_vcore with the state of a MAME frame (tools/tb_prep.py writes the files) loaded
// through the chip's own CPU port, and a behavioural graphics ROM. The sprite buffer gets the previous frame's
// sprite RAM (MAME draws a frame from the copy made at the end of the one before), then the live RAM is loaded.
//   +vram=<hex, 65536 bytes> +sprprev=<hex, 1024> +pal=<hex, 512> +vregs=<hex, 5> +gfx=<hex words> +gfxn=<8x8 tiles>
`default_nettype none
module tb_video_top (
    input  logic        clk,
    input  logic        clk_vid,
    input  logic        rst,
    output logic        ready,
    output logic        ce_pix, hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic        ovr_bg0, ovr_bg1, ovr_tx, ovr_spr,
    output logic        busy_bg0, busy_bg1, busy_tx, busy_spr
);
    logic [7:0] vram_img [0:65535];
    logic [7:0] spr_img  [0:1023];
    logic [7:0] pal_img  [0:511];
    logic [7:0] vregs_img [0:7];
    integer gfxn;
    integer p2;
    logic [17:0] pmask;
    string  p;
    initial begin
        if ($value$plusargs("vram=%s", p))    $readmemh(p, vram_img);
        if ($value$plusargs("sprprev=%s", p)) $readmemh(p, spr_img);
        if ($value$plusargs("pal=%s", p))     $readmemh(p, pal_img);
        if ($value$plusargs("vregs=%s", p))   $readmemh(p, vregs_img);
        if (!$value$plusargs("gfxn=%d", gfxn)) gfxn = 4096;
        // the tile count is not a power of two for every game: mask with the next power of two, then subtract once
        p2 = 1;
        while (p2 < gfxn) p2 = p2 * 2;
        pmask = 18'(p2 - 1);
    end

    // ---- loader: sprite RAM (previous frame) -> copy -> full VRAM -> palette
    typedef enum logic [2:0] { L_SPR, L_COPY, L_WAIT, L_VRAM, L_PAL, L_DONE } lst_t;
    lst_t        ls = L_SPR;
    logic [16:0] li = 17'd0;
    logic [19:0] v_addr;
    logic        v_we;
    logic [7:0]  v_wdata;
    logic        copy;
    always_ff @(posedge clk) begin
        v_we <= 1'b0; copy <= 1'b0;
        if (rst) begin ls <= L_SPR; li <= 17'd0; ready <= 1'b0; end
        else case (ls)
            L_SPR:  begin v_addr <= 20'h1B000 + li[9:0]; v_wdata <= spr_img[li[9:0]]; v_we <= 1'b1;
                          li <= li + 17'd1; if (li == 17'd1023) ls <= L_COPY; end
            L_COPY: begin copy <= 1'b1; li <= 17'd0; ls <= L_WAIT; end
            L_WAIT: begin li <= li + 17'd1; if (li == 17'd300) begin li <= 17'h04000; ls <= L_VRAM; end end
            L_VRAM: begin v_addr <= 20'h10000 + {3'b000, li[15:0]}; v_wdata <= vram_img[li[15:0]]; v_we <= 1'b1;
                          li <= li + 17'd1; if (li == 17'h0FFFF) begin li <= 17'd0; ls <= L_PAL; end end
            L_PAL:  begin v_addr <= 20'h80000 + {11'd0, li[8:0]}; v_wdata <= pal_img[li[8:0]]; v_we <= 1'b1;
                          li <= li + 17'd1; if (li == 17'd511) ls <= L_DONE; end
            L_DONE: ready <= 1'b1;
            default: ;
        endcase
    end

    wire [7:0]  vreg4 = vregs_img[4];
    wire [31:0] tbank = {vregs_img[3], vregs_img[2], vregs_img[1], vregs_img[0]};
    // the tile count is not a power of two for every game: mask with the next power of two, then subtract once

    logic        g0_req, g1_req, gs_req;
    logic [24:1] g0_addr, g1_addr, gs_addr;
    logic        g0_wr, g1_wr, gs_wr, g0_done, g1_done, gs_done;
    logic [1:0]  g0_idx, g1_idx, gs_idx;
    logic [15:0] g0_data, g1_data, gs_data;
    logic [7:0]  v_rdata;
    logic        ls_pulse, frame_pulse;
    logic [8:0]  ln_new;

    taitol_vcore u_vc (
        .clk(clk), .clk_vid(clk_vid), .rst(rst),
        .v_addr(v_addr), .v_we(v_we), .v_wdata(v_wdata), .v_rdata(v_rdata),
        .vreg4(vreg4), .tbank(tbank), .copy(copy), .scr_latch(1'b0),
        .gfx_pmask(pmask), .gfx_n(gfxn[16:0]), .gbank(8'd0),
        .g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
        .g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
        .gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .ls_pulse(ls_pulse), .frame_pulse(frame_pulse), .ln_new(ln_new),
        .dbg_ovr_bg0(ovr_bg0), .dbg_ovr_bg1(ovr_bg1), .dbg_ovr_tx(ovr_tx), .dbg_ovr_spr(ovr_spr),
        .busy_bg0(busy_bg0), .busy_bg1(busy_bg1), .busy_tx(busy_tx), .busy_spr(busy_spr)
    );

    tb_gfx_rom rom (
        .clk(clk), .rst(rst),
        .g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
        .g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
        .gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done)
    );
endmodule
`default_nettype wire
