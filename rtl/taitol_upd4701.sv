// The NEC uPD4701A trackball counter as American Horseshoes wires it (MAME: src/devices/machine/upd4701.cpp, and
// horshoes_map in taito_l.cpp): the chip is read through the bus,
//   A800 / A804   X counter, low byte / high nibble        A808 / A80C   Y counter, low byte / high nibble
//   A802 read     resets the X counter                     A803 read     resets the Y counter
// Every read of the first four addresses latches both counters (relative to their last reset) and returns a byte of the
// latched value; the switch inputs (bits 15-12 of the 16-bit read) are not wired, so the high nibble reads 0.
// The counters are 12 bits and wrap. Movement arrives as signed deltas (the mouse; MAME adds the analog port once a frame).
`default_nettype none
module taitol_upd4701 (
    input  logic        clk,
    input  logic        rst,
    input  logic        add_x,                // strobe: x += dx
    input  logic signed [8:0] dx,
    input  logic        add_y,
    input  logic signed [8:0] dy,

    input  logic        rd,                   // a bus read of A800-A803 (strobe level; the first clock is used)
    input  logic [3:0]  a,                    // A[3:0]
    output logic [7:0]  q
);
    logic [11:0] x, y, sx, sy;
    logic        rd_d;
    wire         rd_now = rd & ~rd_d;
    wire  [11:0] rx = x - sx, ry = y - sy;    // what the latch takes on a read

    always_ff @(posedge clk) begin
        rd_d <= rd;
        if (rst) begin
            x <= 12'd0; y <= 12'd0; sx <= 12'd0; sy <= 12'd0;
        end else begin
            if (add_x) x <= x + {{3{dx[8]}}, dx};
            if (add_y) y <= y + {{3{dy[8]}}, dy};
            if (rd_now && a == 4'h2) sx <= x;
            if (rd_now && a == 4'h3) sy <= y;
        end
    end

    // the byte a read returns is the value latched by that very read (cs falls, d_r(), cs rises: upd4701_device::read_xy)
    always_comb begin
        case (a[3:2])
            2'd0:    q = rx[7:0];
            2'd1:    q = {4'h0, rx[11:8]};
            2'd2:    q = ry[7:0];
            default: q = {4'h0, ry[11:8]};
        endcase
        if (a[1:0] != 2'b00) q = 8'h00;       // A802/A803: the reset reads return the open bus (0)
    end
endmodule
`default_nettype wire
