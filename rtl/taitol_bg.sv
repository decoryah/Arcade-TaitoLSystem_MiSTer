// One scrolling BG layer of the TC0090LVC (64 x 32 tiles of 8 x 8, 4 bits per pixel), drawn a line at a time.
//
// MAME (tc0090lvc_device::screen_update + tilemap_t::effective_rowscroll), single scroll value per layer:
//   dx  = scroll register (16 bit), with the global flip:  ((dx & fffc) | ((dx - 3) & 3)) ^ f
//   x scroll = KN + dx (mod 512)                    KN = 28 (BG0), 38 (BG1)
//   flipped  = KF - dx (mod 512)                    KF = 320 - 512 - DXF = 331 (BG0, DXF = -11), 341 (BG1, DXF = -21)
//   y scroll = dy (mod 256), flipped: -dy
// Screen (x, y) shows map pixel ((x - xs) mod 512, (y - ys) mod 256); with the flip the map is mirrored
// (tile column 63 - c, row 31 - r, pixel row 7 - r, pixel order reversed).
//
// Per line: 41 tile slices. Each reads its map word from the private map RAM, fetches one row of the tile
// (4 bytes = 2 words of the gfx ROM) as a burst from the memory system, and writes 8 pixels {colour, pen} into
// the line buffer. A row of 4 bytes b0..b3 holds 8 pixels: pixels 0-3 from (b0, b1), 4-7 from (b2, b3), and
// pixel u of a half is {B1[4+u], B1[u], B0[4+u], B0[u]} (MAME's gfx_layout {8,12,0,4} / {3,2,1,0, 19..16}).
`default_nettype none
module taitol_bg #(
    parameter [8:0]  KN       = 9'd28,
    parameter [8:0]  KF       = 9'd331,
    parameter [24:1] GFX_BASE = 24'h080000          // word address of the gfx ROM in the SDRAM
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,                      // render `line` into bank `bank`
    input  logic [8:0]  line,
    input  logic        bank,
    output logic        busy,
    output logic        overrun,

    input  logic        flip,
    input  logic [15:0] sx,
    input  logic [7:0]  sy,
    input  logic [31:0] tbank,                      // video registers 3..0: tile code bits 17..10 per bank slot
    input  logic [17:0] gfx_pmask,                  // tile codes wrap modulo gfx_n (a power-of-two mask, then one subtract)
    input  logic [16:0] gfx_n,
    input  logic [7:0]  gbank,                      // American Horseshoes' graphics bank: tile code |= gbank << 12

    output logic [10:0] map_addr,
    input  logic [15:0] map_q,                      // valid the cycle after map_addr

    output logic        m_req,                      // gfx ROM burst of 2 words
    output logic [24:1] m_addr,
    input  logic        m_wr,
    input  logic [1:0]  m_idx,
    input  logic [15:0] m_data,
    input  logic        m_done,

    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [7:0]  lb_data
);
    typedef enum logic [2:0] { S_IDLE, S_MAP, S_CAP, S_WAIT, S_PIX, S_NEXT } st_t;
    st_t st = S_IDLE;

    logic        fl;                                // flip, latched for the line
    logic        bk;
    logic [4:0]  ty;
    logic [2:0]  r;
    logic [5:0]  tc0;
    logic [2:0]  fo;
    logic [5:0]  k;
    logic [2:0]  j;
    logic [3:0]  color;
    logic [15:0] w0, w1;

    // scroll set-up from the registers, at the start of a line
    wire [15:0] dxm = flip ? (((sx & 16'hfffc) | ((sx - 16'd3) & 16'h0003)) ^ 16'h000f) : sx;
    wire [8:0]  sxe = flip ? (KF - dxm[8:0]) : (KN + dxm[8:0]);
    wire [7:0]  sye = flip ? (8'd0 - sy) : sy;
    wire [7:0]  py  = line[7:0] - sye;
    wire [8:0]  q0  = 9'd0 - sxe;

    // the map entry of slice k
    wire [5:0]  tq  = tc0 + k;
    wire [5:0]  col = fl ? ~tq : tq;
    assign map_addr = {ty, col};

    // tile code of the entry just read
    wire [7:0]  tb   = tbank[{map_q[11:10], 3'b000} +: 8];
    wire [17:0] code = ({tb, map_q[9:8], map_q[7:0]} | {gbank[5:0], 12'd0}) & gfx_pmask;
    wire [17:0] codw = (code >= {1'b0, gfx_n}) ? (code - {1'b0, gfx_n}) : code;

    // pixel j of the row, left to right on the screen
    wire [2:0]  pj  = fl ? ~j : j;
    wire [7:0]  b0  = pj[2] ? w1[7:0]  : w0[7:0];
    wire [7:0]  b1  = pj[2] ? w1[15:8] : w0[15:8];
    wire [1:0]  u   = pj[1:0];
    wire [7:0]  b0s = b0 >> u, b1s = b1 >> u;
    wire [3:0]  pen = {b1s[4], b1s[0], b0s[4], b0s[0]};

    wire signed [10:0] x0 = $signed({2'b00, k, 3'b000}) - $signed({8'b0, fo});
    wire signed [10:0] px = x0 + $signed({8'b0, j});
    wire               px_ok = (px >= 0) && (px < 320);

    assign busy = (st != S_IDLE);
    always_ff @(posedge clk) begin
        overrun <= 1'b0;
        lb_we   <= 1'b0;
        if (rst) begin
            st <= S_IDLE; m_req <= 1'b0;
        end else begin
            if (start && st != S_IDLE) overrun <= 1'b1;
            case (st)
                S_IDLE: if (start) begin
                    fl  <= flip;  bk <= bank;
                    ty  <= flip ? ~py[7:3] : py[7:3];
                    r   <= flip ? ~py[2:0] : py[2:0];
                    tc0 <= q0[8:3];
                    fo  <= q0[2:0];
                    k   <= 6'd0;
                    st  <= S_MAP;
                end
                S_MAP: st <= S_CAP;                  // map_addr is presented; the RAM output follows
                S_CAP: begin
                    color <= map_q[15:12];
                    m_addr <= GFX_BASE + {codw[15:0], 4'b0000} + {r, 1'b0};
                    m_req <= 1'b1;
                    st <= S_WAIT;
                end
                S_WAIT: begin
                    if (m_wr) begin
                        if (m_idx[0]) w1 <= m_data; else w0 <= m_data;
                    end
                    if (m_done) begin m_req <= 1'b0; j <= 3'd0; st <= S_PIX; end
                end
                S_PIX: begin
                    if (px_ok) begin
                        lb_we   <= 1'b1;
                        lb_addr <= {bk, px[8:0]};
                        lb_data <= {color, pen};
                    end
                    j <= j + 3'd1;
                    if (j == 3'd7) st <= S_NEXT;
                end
                S_NEXT: begin
                    if (k == 6'd40) st <= S_IDLE;
                    else begin k <= k + 6'd1; st <= S_MAP; end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
