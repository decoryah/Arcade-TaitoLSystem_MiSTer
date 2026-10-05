// The chip's 8 bit bitmap mode (video register 4 [2:0] == 7): the screen is the bitmap RAM (512 bytes a row, 256 rows),
// each byte a palette index, and nothing else is drawn: no tiles, no text, no sprites (MAME: tc0090lvc_device::screen_update).
// This renderer fills one line of the BG1 line buffer: pixel x of screen line y is bitmap[(y & 255) * 512 + (x & 511)]; with the
// flip bit the row is (256 - y) and the column (320 - x). It reads the bitmap RAM's second port, one byte a clock.
`default_nettype none
module taitol_bm (
    input  logic        clk,
    input  logic        start,                // draw `line` into line buffer bank `bank`
    input  logic [8:0]  line,
    input  logic        bank,
    input  logic        flip,

    output logic [16:0] rd_addr,              // bitmap RAM read port (one clock of latency)
    input  logic [7:0]  rd_q,

    output logic        lb_we,
    output logic [9:0]  lb_addr,
    output logic [7:0]  lb_data
);
    logic        run = 1'b0;
    logic [8:0]  i = 9'd0;
    logic [7:0]  yp;
    logic        bk;
    logic        fl;
    wire  [8:0]  xp = fl ? (9'd320 - i) : i;
    assign rd_addr = {yp, xp};

    logic        v_d = 1'b0;
    logic [8:0]  x_d;
    always_ff @(posedge clk) begin
        v_d  <= run;
        x_d  <= i;
        if (start) begin
            run <= 1'b1; i <= 9'd0; bk <= bank; fl <= flip;
            yp  <= flip ? (8'd0 - line[7:0]) : line[7:0];            // (256 - y) & 255
        end else if (run) begin
            if (i == 9'd319) run <= 1'b0;
            i <= i + 9'd1;
        end
    end
    assign lb_we   = v_d;
    assign lb_addr = {bk, x_d};
    assign lb_data = rd_q;
endmodule
`default_nettype wire
