// Clock enables from the 96 MHz machine clock, as a fractional divider.
//
// The TC0090LVC runs from the board's 13.33056 MHz oscillator / 2 = 6.66528 MHz (MAME: "verified freq on
// pin122"), the 1-CPU boards' YM2203 from the same oscillator / 4 = 3.33264 MHz. 6.66528 / 96 = 6943 / 100000
// exactly, so a phase accumulator gives the exact average rate; successive enables are 14 or 15 clocks apart.
//
// The 2- and 3-CPU boards have a second oscillator (12 MHz): the Z80s at 12 / 3 = 4 MHz and the YM2203 at
// 12 / 4 = 3 MHz (the YM2610 of Raimais has its own 8 MHz). 4 / 96 = 1 / 24 and 3 / 96 = 1 / 32 are integer.
`default_nettype none
module taitol_cen (
    input  logic clk,                // 96 MHz
    output logic cen_cpu,            // 6.66528 MHz: the TC0090LVC's Z80
    output logic cen_ym1,            // 3.33264 MHz: the YM2203 of the 1-CPU boards (every other cen_cpu)
    output logic cen_z80b,           // 4 MHz: the second and third Z80 of the bigger boards
    output logic cen_ym2,            // 3 MHz: the YM2203 of the bigger boards
    output logic cen_ym2610,         // 8 MHz: Raimais' YM2610
    output logic cen_mcu             // 3.579545 MHz: Puzznic's MC68705 crystal
);
    localparam [16:0] N = 17'd6943, D = 17'd100000;
    logic [16:0] acc = 17'd0;
    logic        half = 1'b0;
    logic [4:0]  c24 = 5'd0;
    logic [4:0]  c32 = 5'd0;
    logic [3:0]  c12 = 4'd0;
    // 3.579545 MHz / 96 MHz = 715909 / 19200000
    localparam [24:0] NM = 25'd715909, DM = 25'd19200000;
    logic [24:0] accm = 25'd0;
    wire  [24:0] summ = accm + NM;

    wire [16:0] sum = acc + N;
    always_ff @(posedge clk) begin
        cen_cpu <= 1'b0;
        cen_ym1 <= 1'b0;
        if (sum >= D) begin
            acc     <= sum - D;
            cen_cpu <= 1'b1;
            half    <= ~half;
            cen_ym1 <= half;
        end else acc <= sum;

        c24 <= (c24 == 5'd23) ? 5'd0 : c24 + 5'd1;
        cen_z80b <= (c24 == 5'd23);
        c32 <= (c32 == 5'd31) ? 5'd0 : c32 + 5'd1;
        cen_ym2 <= (c32 == 5'd31);
        c12 <= (c12 == 4'd11) ? 4'd0 : c12 + 4'd1;
        cen_ym2610 <= (c12 == 4'd11);

        cen_mcu <= 1'b0;
        if (summ >= DM) begin accm <= summ - DM; cen_mcu <= 1'b1; end
        else accm <= summ;
    end
endmodule
`default_nettype wire
