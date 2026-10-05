// The TC0090LVC's sprites, drawn a line at a time from the vblank-buffered sprite RAM.
//
// 125 entries of 8 bytes (MAME: tc0090lvc_device::draw_sprites):
//   0-1 code   2 [3:0] colour   3 [0] flip x [1] flip y   4 x[7:0]   5 [0] x[8]   6 y   7 unused
// 16 x 16 pixels, built of four 8x8 tiles in the gfx ROM: top left, top right, bottom left, bottom right
// (128 bytes a sprite); a pixel is {colour, 4-bit pen}, pen 0 transparent.
//   x >= 319 wraps to x - 512, y >= 239 to y - 256;  with the global flip x = 304 - x, y = 240 - y and both flips toggle.
//
// MAME draws the entries in order, and a sprite pixel claims its screen pixel *whether or not it is visible*
// (the priority bitmap goes to 31, which every later sprite's mask rejects): the first sprite wins. A sprite whose
// colour has bit 3 set is not drawn where BG0 has priority class 1 (BG0 opaque and the "BG0 priority" bit clear) --
// that is decided by the mixer, so the line buffer entry is {claimed, hide, colour, pen}.
`default_nettype none
module taitol_spr #(
    parameter [24:1] GFX_BASE = 24'h080000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [8:0]  line,
    input  logic        bank,
    output logic        busy,
    output logic        overrun,
    input  logic        flip,

    input  logic [15:0] gfx_pmask16,               // sprite codes wrap modulo gfx_n16 (= tiles / 4)
    input  logic [15:0] gfx_n16,
    input  logic [7:0]  gbank,                     // American Horseshoes' graphics bank: sprite code |= gbank << 10

    output logic [6:0]  sp_addr,
    input  logic [63:0] sp_q,                      // valid the cycle after sp_addr

    output logic        m_req,
    output logic [24:1] m_addr,
    input  logic        m_wr,
    input  logic [1:0]  m_idx,
    input  logic [15:0] m_data,
    input  logic        m_done,

    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [9:0]  lb_data                    // {claimed, hide, colour[3:0], pen[3:0]}
);
    typedef enum logic [3:0] { S_IDLE, S_CLR, S_SCAN, S_EVAL, S_F0, S_F1, S_DRAW } st_t;
    st_t st = S_IDLE;

    logic        fl, bk;
    logic [8:0]  ln;
    logic [8:0]  cl;                               // clear counter
    logic [6:0]  e;
    logic [319:0] claimed;

    // entry fields
    logic signed [10:0] xs;
    logic [3:0]  col;
    logic        fx;
    logic [15:0] blk;
    logic [15:0] l0, l1, r0, r1;
    logic [4:0]  c;

    assign sp_addr = e;

    // ---- entry decode (valid in S_EVAL)
    wire [15:0] s_code = sp_q[15:0];
    wire [3:0]  s_col  = sp_q[19:16];
    wire        s_fx   = sp_q[24];
    wire        s_fy   = sp_q[25];
    wire [8:0]  s_x9   = {sp_q[40], sp_q[39:32]};
    wire [7:0]  s_y8   = sp_q[55:48];
    wire signed [10:0] x_w  = (s_x9 >= 9'd319) ? ($signed({2'b00, s_x9}) - 11'sd512) : $signed({2'b00, s_x9});
    wire signed [10:0] y_w  = (s_y8 >= 8'd239) ? ($signed({3'b000, s_y8}) - 11'sd256) : $signed({3'b000, s_y8});
    wire signed [10:0] x_f  = fl ? (11'sd304 - x_w) : x_w;
    wire signed [10:0] y_f  = fl ? (11'sd240 - y_w) : y_w;
    wire               fx_f = fl ? ~s_fx : s_fx;
    wire               fy_f = fl ? ~s_fy : s_fy;
    wire signed [10:0] dy   = $signed({2'b00, ln}) - y_f;
    wire               hit  = (dy >= 0) && (dy < 16) && (x_f > -16) && (x_f < 320);
    wire [3:0]  rr     = fy_f ? ~dy[3:0] : dy[3:0];
    wire [15:0] cmask  = (s_code | {gbank[5:0], 10'd0}) & gfx_pmask16;
    wire [15:0] cwrap  = (cmask >= gfx_n16) ? (cmask - gfx_n16) : cmask;
    wire [24:1] a_left = GFX_BASE + {2'b00, cwrap, 6'b000000} + {rr[3], 5'b00000} + {rr[2:0], 1'b0};

    // ---- one row of 8 pixels from 4 bytes
    function automatic [3:0] pix8(input [15:0] w0, input [15:0] w1, input [2:0] i);
        reg [7:0] b0, b1;
        begin
            b0 = i[2] ? w1[7:0]  : w0[7:0];
            b1 = i[2] ? w1[15:8] : w0[15:8];
            b0 = b0 >> i[1:0];
            b1 = b1 >> i[1:0];
            pix8 = {b1[4], b1[0], b0[4], b0[0]};
        end
    endfunction

    // ---- the pixel being drawn: screen x = xs + c
    wire signed [10:0] px  = xs + $signed({6'b0, c});
    wire        px_ok = (px >= 0) && (px < 320);
    wire [3:0]  sc    = fx ? ~c[3:0] : c[3:0];                    // source pixel 0..15 in the unflipped sprite
    wire [3:0]  pen   = sc[3] ? pix8(r0, r1, sc[2:0]) : pix8(l0, l1, sc[2:0]);

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
                    fl <= flip; bk <= bank; ln <= line; cl <= 9'd0; st <= S_CLR;
                end
                S_CLR: begin                              // empty the line, 1 pixel a clock
                    lb_we <= 1'b1; lb_addr <= {bk, cl}; lb_data <= 10'd0;
                    claimed <= 320'd0;
                    cl <= cl + 9'd1;
                    if (cl == 9'd319) begin e <= 7'd0; st <= S_SCAN; end
                end
                S_SCAN: st <= S_EVAL;                      // sp_addr = e is presented
                S_EVAL: begin
                    if (hit) begin
                        xs <= x_f; col <= s_col; fx <= fx_f;
                        m_addr <= a_left; m_req <= 1'b1; st <= S_F0;
                    end else if (e == 7'd124) st <= S_IDLE;
                    else begin e <= e + 7'd1; st <= S_SCAN; end
                end
                S_F0: begin
                    if (m_wr) begin if (m_idx[0]) l1 <= m_data; else l0 <= m_data; end
                    if (m_done) begin m_req <= 1'b0; m_addr <= m_addr + 24'd16; st <= S_F1; end
                end
                S_F1: begin
                    if (!m_req && !m_done) m_req <= 1'b1;   // the right half, 32 bytes on
                    if (m_wr) begin if (m_idx[0]) r1 <= m_data; else r0 <= m_data; end
                    if (m_done) begin m_req <= 1'b0; c <= 5'd0; st <= S_DRAW; end
                end
                S_DRAW: begin
                    if (px_ok && pen != 4'd0 && !claimed[px[8:0]]) begin
                        lb_we <= 1'b1; lb_addr <= {bk, px[8:0]};
                        lb_data <= {1'b1, col[3], col, pen};
                        claimed[px[8:0]] <= 1'b1;
                    end
                    c <= c + 5'd1;
                    if (c == 5'd15) begin
                        if (e == 7'd124) st <= S_IDLE;
                        else begin e <= e + 7'd1; st <= S_SCAN; end
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
