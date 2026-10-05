// The TC0090LVC's video memories and the CPU's window onto them (MAME: tc0090lvc_device::vram_map).
//
//   v_addr is the 20-bit address in the chip's VRAM space (the CPU's C000-FDFF window, bank-translated):
//     010000-01FFFF  VRAM, 64 KB (writes below 014000 are ignored, as in MAME: the first tiles stay blank)
//     080000-080FFF  palette RAM, 256 entries of 16 bits (the 512 bytes mirrored 8 times in the window)
//     040000-05FFFF  bitmap RAM, 128 KB (the 8 bit bitmap mode, Cachat's intro: taitol_bm reads it through the second port)
//
// VRAM layout (index = address - 010000):  8000 BG0 map, 9000 BG1 map, A000 text map, B000 sprite RAM and
// scroll registers (B3F4-B3F6 BG0 x lo, x hi, y;  B3FC-B3FE BG1), the rest character RAM for the text layer.
//
// The renderers get their own read ports: every write to the BG maps and to sprite RAM is duplicated into
// small private RAMs (a BG map as 2K x 16, sprite RAM as 128 entries x 8 byte lanes); the text layer reads
// the main array through its own port. Sprite RAM is drawn from a buffer that is a copy made at the start of
// vblank (`copy`): the real chip's sprite buffer.
`default_nettype none
module taitol_vmem (
    input  logic        clk,

    // CPU side
    input  logic [19:0] v_addr,
    input  logic        v_we,
    input  logic [7:0]  v_wdata,
    output logic [7:0]  v_rdata,

    // scroll registers: live as the CPU writes them, or (scr_latch) as they stood at the start of vblank, like the sprite buffer
    input  logic        scr_latch,
    output logic [15:0] bg0_sx, bg1_sx,
    output logic [7:0]  bg0_sy, bg1_sy,

    // bitmap RAM read port (renderer, one clock of latency)
    input  logic [16:0] bm_addr,
    output logic [7:0]  bm_q,

    // palette read port (video clock)
    input  logic        pal_clk,
    input  logic [7:0]  pal_addr,
    output logic [15:0] pal_q,

    // text layer: read port of the main array
    input  logic [15:0] tx_addr,
    output logic [7:0]  tx_q,

    // BG map read ports (16 bits: {attribute, code})
    input  logic [10:0] bg0_addr,
    output logic [15:0] bg0_q,
    input  logic [10:0] bg1_addr,
    output logic [15:0] bg1_q,

    // sprite buffer
    input  logic        copy,                 // pulse: latch the live sprite RAM
    input  logic [6:0]  sp_addr,
    output logic [63:0] sp_q
);
    // ------------------------------------------------------------ decode
    wire        in_vram = (v_addr[19:16] == 4'h1);
    wire        in_pal  = (v_addr[19:12] == 8'h80);
    wire        in_bm   = (v_addr[19:17] == 3'b010);
    wire [15:0] idx     = v_addr[15:0];
    wire        vwe     = v_we & in_vram & (idx[15:14] != 2'b00);
    wire        pwe     = v_we & in_pal;

    // ------------------------------------------------------------ VRAM main array
    logic [7:0] vram_qa;
    taitol_dpram8 #(.AW(16)) u_vram (
        .clka(clk), .wea(vwe), .addra(idx), .da(v_wdata), .qa(vram_qa),
        .clkb(clk), .addrb(tx_addr), .qb(tx_q)
    );

    // ------------------------------------------------------------ bitmap RAM
    logic [7:0] bm_qa;
    taitol_dpram8 #(.AW(17)) u_bm (
        .clka(clk), .wea(v_we & in_bm), .addra(v_addr[16:0]), .da(v_wdata), .qa(bm_qa),
        .clkb(clk), .addrb(bm_addr), .qb(bm_q)
    );

    // ------------------------------------------------------------ BG maps (private copies)
    wire bg0_sel = vwe & (idx[15:12] == 4'h8);
    wire bg1_sel = vwe & (idx[15:12] == 4'h9);
    logic [7:0] bg0_lo_q, bg0_hi_q, bg1_lo_q, bg1_hi_q;
    taitol_sdp #(.AW(11), .DW(8)) u_bg0_l (.clk(clk), .we(bg0_sel & ~idx[0]), .waddr(idx[11:1]), .wdata(v_wdata), .raddr(bg0_addr), .rdata(bg0_lo_q));
    taitol_sdp #(.AW(11), .DW(8)) u_bg0_h (.clk(clk), .we(bg0_sel &  idx[0]), .waddr(idx[11:1]), .wdata(v_wdata), .raddr(bg0_addr), .rdata(bg0_hi_q));
    taitol_sdp #(.AW(11), .DW(8)) u_bg1_l (.clk(clk), .we(bg1_sel & ~idx[0]), .waddr(idx[11:1]), .wdata(v_wdata), .raddr(bg1_addr), .rdata(bg1_lo_q));
    taitol_sdp #(.AW(11), .DW(8)) u_bg1_h (.clk(clk), .we(bg1_sel &  idx[0]), .waddr(idx[11:1]), .wdata(v_wdata), .raddr(bg1_addr), .rdata(bg1_hi_q));
    assign bg0_q = {bg0_hi_q, bg0_lo_q};
    assign bg1_q = {bg1_hi_q, bg1_lo_q};

    // ------------------------------------------------------------ scroll registers (live)
    logic [15:0] l_bg0_sx = 16'd0, l_bg1_sx = 16'd0, s_bg0_sx = 16'd0, s_bg1_sx = 16'd0;
    logic [7:0]  l_bg0_sy = 8'd0,  l_bg1_sy = 8'd0,  s_bg0_sy = 8'd0,  s_bg1_sy = 8'd0;
    always_ff @(posedge clk) begin
        if (vwe) begin
            case (idx)
                16'hB3F4: l_bg0_sx[7:0]  <= v_wdata;
                16'hB3F5: l_bg0_sx[15:8] <= v_wdata;
                16'hB3F6: l_bg0_sy       <= v_wdata;
                16'hB3FC: l_bg1_sx[7:0]  <= v_wdata;
                16'hB3FD: l_bg1_sx[15:8] <= v_wdata;
                16'hB3FE: l_bg1_sy       <= v_wdata;
                default: ;
            endcase
        end
        if (copy) begin s_bg0_sx <= l_bg0_sx; s_bg0_sy <= l_bg0_sy; s_bg1_sx <= l_bg1_sx; s_bg1_sy <= l_bg1_sy; end
    end
    assign bg0_sx = scr_latch ? s_bg0_sx : l_bg0_sx;
    assign bg0_sy = scr_latch ? s_bg0_sy : l_bg0_sy;
    assign bg1_sx = scr_latch ? s_bg1_sx : l_bg1_sx;
    assign bg1_sy = scr_latch ? s_bg1_sy : l_bg1_sy;

    // ------------------------------------------------------------ sprite RAM: live copy and the vblank buffer
    wire spr_sel = vwe & (idx[15:10] == 6'b101100);               // B000-B3FF
    logic [7:0] sl_q [8];
    logic [6:0] cp_i;
    logic       cp_run, cp_wr;
    logic [6:0] cp_wa;
    genvar g;
    generate for (g = 0; g < 8; g++) begin : lane
        taitol_sdp #(.AW(7), .DW(8)) u_l (.clk(clk), .we(spr_sel & (idx[2:0] == g[2:0])), .waddr(idx[9:3]), .wdata(v_wdata),
                                          .raddr(cp_i), .rdata(sl_q[g]));
    end endgenerate

    initial begin cp_run = 1'b0; cp_wr = 1'b0; cp_i = 7'd0; end
    always_ff @(posedge clk) begin
        cp_wr <= 1'b0;
        if (copy) begin cp_run <= 1'b1; cp_i <= 7'd0; end
        else if (cp_run) begin
            cp_wa <= cp_i; cp_wr <= 1'b1;
            cp_i <= cp_i + 7'd1;
            if (cp_i == 7'd127) cp_run <= 1'b0;
        end
    end
    taitol_sdp #(.AW(7), .DW(64)) u_sbuf (
        .clk(clk), .we(cp_wr), .waddr(cp_wa),
        .wdata({sl_q[7], sl_q[6], sl_q[5], sl_q[4], sl_q[3], sl_q[2], sl_q[1], sl_q[0]}),
        .raddr(sp_addr), .rdata(sp_q)
    );

    // ------------------------------------------------------------ palette
    logic [7:0] pal_lo_qa, pal_hi_qa;
    taitol_dpram8 #(.AW(8)) u_pal_l (.clka(clk), .wea(pwe & ~v_addr[0]), .addra(v_addr[8:1]), .da(v_wdata), .qa(pal_lo_qa),
                                     .clkb(pal_clk), .addrb(pal_addr), .qb(pal_q[7:0]));
    taitol_dpram8 #(.AW(8)) u_pal_h (.clka(clk), .wea(pwe &  v_addr[0]), .addra(v_addr[8:1]), .da(v_wdata), .qa(pal_hi_qa),
                                     .clkb(pal_clk), .addrb(pal_addr), .qb(pal_q[15:8]));

    // ------------------------------------------------------------ CPU read data (registered like the RAMs)
    logic rs_vram, rs_pal, rs_pal_hi, rs_bm;
    always_ff @(posedge clk) begin
        rs_vram   <= in_vram;
        rs_pal    <= in_pal;
        rs_pal_hi <= v_addr[0];
        rs_bm     <= in_bm;
    end
    always_comb begin
        v_rdata = 8'h00;
        if (rs_vram)      v_rdata = vram_qa;
        else if (rs_pal)  v_rdata = rs_pal_hi ? pal_hi_qa : pal_lo_qa;
        else if (rs_bm)   v_rdata = bm_qa;
    end
endmodule
`default_nettype wire
