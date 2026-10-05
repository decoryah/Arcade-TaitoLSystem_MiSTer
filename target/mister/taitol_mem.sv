// Memory of the Taito L core on MiSTer: the SDRAM (through sdram_ctrl), the ROM loader and the arbiter of the clients of
// its burst port. Structure and the SDRAM controller are the MCatAdv core's.
//
// The MRA's image (tools/taitol_rom.py documents the layout) arrives a byte at a time; a pair is one 16-bit word of
// the SDRAM (first byte in the low half). The image offset maps straight through: SDRAM word = byte offset / 2.
//
//   000000-0FFFFF  program ROM             (the cache's 8-word line fills)
//   100000-27FFFF  tile and sprite ROM     (2-word bursts: one row of an 8x8 tile)
//   280000-39FFFF  sound Z80, slave Z80, ADPCM data (later)
//   3A0000-3A07FF  MC68705 ROM (later), 3A0800-3A080F configuration (captured here)
`default_nettype none
module taitol_mem (
    input  logic        clk,
    input  logic        clk_sdram,
    input  logic        init,             // reset / (re)initialise the chip
    input  logic        rd_late,
    output logic        ready,

    // loader
    input  logic        dl_we,
    input  logic [24:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_wait,
    output logic        dl_busy,          // words still being written
    output logic [3:0]  cfg_board,
    output logic [15:0] cfg_n8,           // 8x8 tiles in the graphics ROM
    output logic [17:0] cfg_pmask,        // power-of-two mask over the tile codes
    output logic [19:0] cfg_rmask,        // program ROM size - 1
    output logic [1:0]  cfg_rot,
    output logic [7:0]  cfg_flags,        // [0] the program ROM is bit-reversed (plottinga)
    output logic [119:0] cfg_in_id,       // controls: 24 signal ids of 5 bits (tools/inputmap.py) ...
    output logic [23:0] cfg_in_idle,      // ... and the idle values of IN0..IN2

    // the MC68705's 2 KB program (Puzznic) as it goes by in the image
    output logic        mcu_we,
    output logic [10:0] mcu_waddr,
    output logic [7:0]  mcu_wdata,

    // the second Z80's ROM (the first 64 KB of the image's audiocpu region, 280000-28FFFF)
    output logic        sub_we,
    output logic [15:0] sub_waddr,
    output logic [7:0]  sub_wdata,

    // burst clients: level request, a word per _wr with its index, a pulse at the end
    input  logic        p_req,            // program cache line fill (8 words)
    input  logic [19:4] p_addr,
    output logic        p_wr, output logic [2:0] p_idx, output logic [15:0] p_data, output logic p_done,

    input  logic        s_req,            // 3-CPU boards: slave Z80 ROM cache line fill (8 words), image 300000
    input  logic [16:4] s_addr,
    output logic        s_wr, output logic [2:0] s_idx, output logic [15:0] s_data, output logic s_done,

    input  logic        a_req,            // sound Z80 ROM cache line fill, image 280000
    input  logic [15:4] a_addr,
    output logic        a_wr, output logic [2:0] a_idx, output logic [15:0] a_data, output logic a_done,

    input  logic        m_req,            // ADPCM ROM cache line fill (Champion Wrestler), image 320000
    input  logic [16:4] m_addr,
    output logic        m_wr, output logic [2:0] m_idx, output logic [15:0] m_data, output logic m_done,

    input  logic        g0_req,           // BG0 tile row (2 words)
    input  logic [24:1] g0_addr,
    output logic        g0_wr, output logic [1:0] g0_idx, output logic [15:0] g0_data, output logic g0_done,

    input  logic        g1_req,           // BG1
    input  logic [24:1] g1_addr,
    output logic        g1_wr, output logic [1:0] g1_idx, output logic [15:0] g1_data, output logic g1_done,

    input  logic        gs_req,           // sprites
    input  logic [24:1] gs_addr,
    output logic        gs_wr, output logic [1:0] gs_idx, output logic [15:0] gs_data, output logic gs_done,

    // chip
    inout  wire  [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_A,
    output logic        SDRAM_DQML, SDRAM_DQMH,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS,
    output logic        SDRAM_CKE, SDRAM_CLK
);
    localparam [24:0] IMAGE_END = 25'h3A0830;     // bytes

    // ------------------------------------------------------------ the loader
    // bytes -> words (the image is sequential)
    logic        lo_v;
    logic [7:0]  lo_d;
    logic        wf_push;
    logic [39:0] wf_in;                           // {word index (24), data (16)}
    always_comb begin
        wf_push = 1'b0; wf_in = '0;
        if (dl_we && dl_addr[0] && lo_v) begin
            wf_push = 1'b1; wf_in = {dl_addr[24:1], dl_data, lo_d};
        end
    end
    always_ff @(posedge clk) begin
        if (dl_we) begin
            if (!dl_addr[0]) begin lo_v <= 1'b1; lo_d <= dl_data; end
            else lo_v <= 1'b0;
            // the configuration bytes at the end of the image (64-byte block 3A0800-3A083F)
            if (dl_addr[24:6] == 19'h0E820) begin
                case (dl_addr[5:0])
                    6'd0: cfg_board <= dl_data[3:0];
                    6'd1: cfg_n8[7:0]    <= dl_data;
                    6'd2: cfg_n8[15:8]   <= dl_data;
                    6'd3: cfg_pmask[7:0]  <= dl_data;
                    6'd4: cfg_pmask[15:8] <= dl_data;
                    6'd5: cfg_pmask[17:16] <= dl_data[1:0];
                    6'd6: cfg_rmask[7:0]  <= dl_data;
                    6'd7: cfg_rmask[15:8] <= dl_data;
                    6'd8: cfg_rmask[19:16] <= dl_data[3:0];
                    6'd9: cfg_rot <= dl_data[1:0];
                    6'd10: cfg_flags <= dl_data;
                    default: begin
                        if (dl_addr[5:0] >= 6'd16 && dl_addr[5:0] < 6'd40) cfg_in_id[(dl_addr[5:0] - 6'd16) * 5 +: 5] <= dl_data[4:0];
                        if (dl_addr[5:0] >= 6'd40 && dl_addr[5:0] < 6'd43) cfg_in_idle[(dl_addr[5:0] - 6'd40) * 8 +: 8] <= dl_data;
                    end
                endcase
            end
        end
    end
    assign mcu_we    = dl_we && (dl_addr[24:11] == 14'h740);      // 3A0000-3A07FF
    assign mcu_waddr = dl_addr[10:0];
    assign mcu_wdata = dl_data;
    assign sub_we    = dl_we && (dl_addr[24:16] == 9'h028);       // 280000-28FFFF
    assign sub_waddr = dl_addr[15:0];
    assign sub_wdata = dl_data;

    (* ramstyle = "no_rw_check" *) logic [39:0] wfifo [64];
    logic  [6:0] wf_wp, wf_rp;
    wire         wf_empty = (wf_wp == wf_rp);
    assign dl_wait = ((wf_wp - wf_rp) >= 7'd32);
    assign dl_busy = !wf_empty;

    logic [39:0] hd;
    wire  [24:1] wa = hd[39:16];                  // word index of the image
    wire  [15:0] wd = hd[15:0];

    typedef enum logic [1:0] { W_IDLE, W_DEC, W_SDRAM } wst_t;
    wst_t wst;
    logic        sd_wr_req;
    logic [24:1] sd_wr_addr;

    always_ff @(posedge clk) begin
        if (init) begin
            wf_wp <= '0; wf_rp <= '0; wst <= W_IDLE; sd_wr_req <= 1'b0;
        end else begin
            if (wf_push) begin wfifo[wf_wp[5:0]] <= wf_in; wf_wp <= wf_wp + 7'd1; end
            case (wst)
                W_IDLE: if (!wf_empty) begin hd <= wfifo[wf_rp[5:0]]; wst <= W_DEC; end
                W_DEC: begin
                    if ({wa, 1'b0} >= IMAGE_END) begin wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end   // past the image
                    else begin sd_wr_addr <= wa; sd_wr_req <= 1'b1; wst <= W_SDRAM; end
                end
                W_SDRAM: if (sd_wr_ack) begin sd_wr_req <= 1'b0; wf_rp <= wf_rp + 7'd1; wst <= W_IDLE; end
                default: wst <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------ SDRAM controller
    logic [24:1] c_addr  [2];
    logic        c_req   [2];
    logic        c_we    [2];
    logic [15:0] c_wdata [2];
    logic  [1:0] c_be    [2];
    logic        c_ack   [2];
    logic [15:0] sd_rdata;
    logic [24:1] b_addr;
    logic  [9:0] b_len, b_idx;
    logic        b_req, b_done, b_wr;
    logic [15:0] b_data;
    logic  [9:0] b_widx;
    logic        sd_ready;
    wire         sd_wr_ack = c_ack[1];

    // client 1: the loader
    assign c_addr[1] = sd_wr_addr;
    assign c_req[1]  = sd_wr_req;
    assign c_we[1]   = 1'b1;
    assign c_wdata[1] = wd;
    assign c_be[1]   = 2'b11;
    // client 0: unused here (the ADPCM sample reads of the bigger boards, later)
    assign c_addr[0] = '0;
    assign c_req[0]  = 1'b0;
    assign c_we[0]   = 1'b0;
    assign c_wdata[0] = '0;
    assign c_be[0]   = 2'b11;

    // ------------------------------------------------------------ burst arbiter
    typedef enum logic [1:0] { B_IDLE, B_RUN, B_ACK } bst_t;
    bst_t        bst;
    logic [2:0]  bsel;                            // 0 program, 1 BG0, 2 BG1, 3 sprites, 4 slave ROM, 5 sound ROM, 6 ADPCM ROM
    always_ff @(posedge clk) begin
        if (init) begin bst <= B_IDLE; b_req <= 1'b0; end
        else case (bst)
            B_IDLE: begin
                if (p_req)       begin bsel <= 3'd0; b_addr <= {5'd0, p_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (s_req)  begin bsel <= 3'd4; b_addr <= 24'h180000 | {8'd0, s_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (a_req)  begin bsel <= 3'd5; b_addr <= 24'h140000 | {9'd0, a_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (m_req)  begin bsel <= 3'd6; b_addr <= 24'h190000 | {8'd0, m_addr, 3'b000}; b_len <= 10'd8; b_req <= 1'b1; bst <= B_RUN; end
                else if (g0_req) begin bsel <= 3'd1; b_addr <= g0_addr; b_len <= 10'd2; b_req <= 1'b1; bst <= B_RUN; end
                else if (g1_req) begin bsel <= 3'd2; b_addr <= g1_addr; b_len <= 10'd2; b_req <= 1'b1; bst <= B_RUN; end
                else if (gs_req) begin bsel <= 3'd3; b_addr <= gs_addr; b_len <= 10'd2; b_req <= 1'b1; bst <= B_RUN; end
            end
            B_RUN: if (b_done) begin b_req <= 1'b0; bst <= B_ACK; end
            B_ACK: bst <= B_IDLE;                 // the client sees its done pulse and drops its request
            default: bst <= B_IDLE;
        endcase
    end
    wire run = (bst == B_RUN) && b_wr;
    assign p_wr  = run && bsel == 3'd0;  assign p_idx  = b_idx[2:0]; assign p_data  = b_data;
    assign g0_wr = run && bsel == 3'd1;  assign g0_idx = b_idx[1:0]; assign g0_data = b_data;
    assign g1_wr = run && bsel == 3'd2;  assign g1_idx = b_idx[1:0]; assign g1_data = b_data;
    assign gs_wr = run && bsel == 3'd3;  assign gs_idx = b_idx[1:0]; assign gs_data = b_data;
    assign s_wr  = run && bsel == 3'd4;  assign s_idx  = b_idx[2:0]; assign s_data  = b_data;
    assign a_wr  = run && bsel == 3'd5;  assign a_idx  = b_idx[2:0]; assign a_data  = b_data;
    assign m_wr  = run && bsel == 3'd6;  assign m_idx  = b_idx[2:0]; assign m_data  = b_data;
    assign m_done  = (bst == B_ACK) && bsel == 3'd6;
    assign p_done  = (bst == B_ACK) && bsel == 3'd0;
    assign g0_done = (bst == B_ACK) && bsel == 3'd1;
    assign g1_done = (bst == B_ACK) && bsel == 3'd2;
    assign gs_done = (bst == B_ACK) && bsel == 3'd3;
    assign s_done  = (bst == B_ACK) && bsel == 3'd4;
    assign a_done  = (bst == B_ACK) && bsel == 3'd5;

    sdram_ctrl #(.NCLI(2)) u_sdram (
        .clk(clk), .clk_pin(clk_sdram), .init(init), .rd_late(rd_late), .burst_slow(1'b0), .ready(sd_ready),
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
        .c_addr(c_addr), .c_req(c_req), .c_we(c_we), .c_wdata(c_wdata), .c_be(c_be), .c_ack(c_ack), .rdata(sd_rdata),
        .b_addr(b_addr), .b_len(b_len), .b_req(b_req), .b_abort(1'b0), .b_wr(b_wr), .b_idx(b_idx), .b_data(b_data), .b_done(b_done),
        .b_we(1'b0), .b_wdata(16'd0), .b_be(2'b00), .b_widx(b_widx)
    );
    assign ready = sd_ready;

    wire unused = ^{b_widx, b_idx[9:4], sd_rdata};
endmodule
`default_nettype wire
