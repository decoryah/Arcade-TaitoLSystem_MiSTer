// The text layer of the TC0090LVC: a fixed 64 x 32 map of 8 x 8 tiles whose graphics are RAM characters:
// MAME decodes the whole 64 KB VRAM as 8x8 4bpp tiles, tile code N reading bytes N*32 .. N*32+31, and the map
// (VRAM A000-AFFF, 2 bytes a tile: code[7:0]; {colour[7:4], 0, code[10:8]}) selects them.
//
// The text layer does not scroll: x scroll = -8 (non-flipped) so screen x 0 shows map pixel 8 (tile column 1);
// flipped, 320 - 512 + 8 = 328 (tile column 23 first, mirrored); y scroll 0.
// Everything it reads is in the main VRAM array, through that array's second port: no SDRAM traffic.
`default_nettype none
module taitol_tx (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [8:0]  line,
    input  logic        bank,
    output logic        busy,
    output logic        overrun,
    input  logic        flip,

    output logic [15:0] vr_addr,                   // VRAM read port; vr_q follows a cycle later
    input  logic [7:0]  vr_q,

    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [7:0]  lb_data
);
    typedef enum logic [2:0] { S_IDLE, S_MAP, S_CHR, S_PIX, S_NEXT } st_t;
    st_t st = S_IDLE;

    logic        fl, bk;
    logic [4:0]  ty;
    logic [2:0]  r;
    logic [5:0]  tc0;
    logic [5:0]  k;
    logic [2:0]  cnt;
    logic [2:0]  j;
    logic [7:0]  m_lo, m_hi, c0, c1, c2, c3;

    wire [7:0]  py  = line[7:0];
    wire [5:0]  tq  = tc0 + k;
    wire [5:0]  col = fl ? ~tq : tq;
    wire [10:0] mi  = {ty, col};
    wire [10:0] tcode = {m_hi[2:0], m_lo};

    always_comb begin
        vr_addr = 16'h0000;
        if (st == S_MAP)      vr_addr = 16'hA000 + {mi, 1'b0} + {15'd0, cnt[0]};
        else if (st == S_CHR) vr_addr = {tcode, 5'b00000} + {11'd0, r, 2'b00} + {13'd0, cnt[1:0]};
    end

    wire [2:0]  pj  = fl ? ~j : j;
    wire [15:0] w0  = {c1, c0}, w1 = {c3, c2};
    wire [7:0]  b0  = pj[2] ? w1[7:0]  : w0[7:0];
    wire [7:0]  b1  = pj[2] ? w1[15:8] : w0[15:8];
    wire [1:0]  u   = pj[1:0];
    wire [7:0]  b0s = b0 >> u, b1s = b1 >> u;
    wire [3:0]  pen = {b1s[4], b1s[0], b0s[4], b0s[0]};
    wire signed [10:0] px = $signed({2'b00, k, 3'b000}) + $signed({8'b0, j});   // fine scroll is 0
    wire        px_ok = (px >= 0) && (px < 320);

    assign busy = (st != S_IDLE);
    always_ff @(posedge clk) begin
        overrun <= 1'b0;
        lb_we   <= 1'b0;
        if (rst) st <= S_IDLE;
        else begin
            if (start && st != S_IDLE) overrun <= 1'b1;
            case (st)
                S_IDLE: if (start) begin
                    fl  <= flip;  bk <= bank;
                    ty  <= flip ? ~py[7:3] : py[7:3];
                    r   <= flip ? ~py[2:0] : py[2:0];
                    tc0 <= flip ? 6'd23 : 6'd1;
                    k   <= 6'd0;
                    cnt <= 3'd0;
                    st  <= S_MAP;
                end
                S_MAP: begin                           // cnt 0: address of the low byte; 1: high byte; 2: capture the high byte
                    cnt <= cnt + 3'd1;
                    if (cnt == 3'd1) m_lo <= vr_q;
                    if (cnt == 3'd2) begin m_hi <= vr_q; cnt <= 3'd0; st <= S_CHR; end
                end
                S_CHR: begin                           // cnt 0..3 present the row's four bytes; 1..4 capture them
                    cnt <= cnt + 3'd1;
                    if (cnt == 3'd1) c0 <= vr_q;
                    if (cnt == 3'd2) c1 <= vr_q;
                    if (cnt == 3'd3) c2 <= vr_q;
                    if (cnt == 3'd4) begin c3 <= vr_q; j <= 3'd0; st <= S_PIX; end
                end
                S_PIX: begin
                    if (px_ok) begin
                        lb_we   <= 1'b1;
                        lb_addr <= {bk, px[8:0]};
                        lb_data <= {m_hi[7:4], pen};
                    end
                    j <= j + 3'd1;
                    if (j == 3'd7) st <= S_NEXT;
                end
                S_NEXT: begin
                    cnt <= 3'd0;
                    if (k == 6'd40) st <= S_IDLE;
                    else begin k <= k + 6'd1; st <= S_MAP; end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
