// The Palamedes family's input chip, an 8255 (TMP8255AP-5; Cachat and the later games: an NEC D70155C, the same): mode 0 only,
// as MAME's i8255 does it for these boards (the three ports are IN0, IN1, IN2; the output callbacks are not connected).
//   reset: control 9B (all ports inputs).  Control write with bit 7 set: sets the directions (and clears the output
//   latches); bit 7 clear: sets / resets one bit of the port C latch.  Reading an input port gives the pins, an output port
//   its latch (port C per nibble).
`default_nettype none
module taitol_i8255 (
    input  logic       clk,
    input  logic       rst,
    input  logic       wr,                    // the Z80's write strobe, a level
    input  logic       rd,                    // not needed: reads have no side effects
    input  logic [1:0] a,
    input  logic [7:0] d,
    output logic [7:0] q,
    input  logic [7:0] pa_in, pb_in, pc_in
);
    logic       a_in = 1'b1, b_in = 1'b1, cu_in = 1'b1, cl_in = 1'b1;    // direction: 1 = input
    logic [7:0] la = 8'h00, lb = 8'h00, lc = 8'h00;
    logic       wr_d;
    always_ff @(posedge clk) begin
        wr_d <= wr;
        if (rst) begin
            a_in <= 1'b1; b_in <= 1'b1; cu_in <= 1'b1; cl_in <= 1'b1; la <= 8'h00; lb <= 8'h00; lc <= 8'h00;
        end else if (wr && !wr_d) begin
            case (a)
                2'd0: la <= d;
                2'd1: lb <= d;
                2'd2: lc <= d;
                2'd3: begin
                    if (d[7]) begin
                        a_in <= d[4]; b_in <= d[1]; cu_in <= d[3]; cl_in <= d[0];
                        la <= 8'h00; lb <= 8'h00; lc <= 8'h00;
                    end else begin
                        lc[d[3:1]] <= d[0];
                    end
                end
            endcase
        end
    end
    always_comb begin
        case (a)
            2'd0: q = a_in ? pa_in : la;
            2'd1: q = b_in ? pb_in : lb;
            2'd2: q = {cu_in ? pc_in[7:4] : lc[7:4], cl_in ? pc_in[3:0] : lc[3:0]};
            default: q = 8'hFF;
        endcase
    end
    wire unused = rd;
endmodule
`default_nettype wire
