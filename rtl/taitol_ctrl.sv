// Generic controls: builds the board's input ports IN0..IN2 from the player's controls using the per-game wiring in the ROM
// image's configuration block (tools/inputmap.py reads it from MAME). Nothing here is game specific.
//
//   sig[n] is signal n pressed (1 = pressed):
//     1-4 P1 up/down/left/right  5-7 P1 buttons 1-3  8-11 P2 up/down/left/right  12-14 P2 buttons 1-3
//     15 coin 1  16 coin 2  17 start 1  18 start 2  19 service  20 tilt
//   id_flat: 24 signal ids of 5 bits, port-major (IN0 bit 0 first);  idle: the value each port reads with nothing pressed.
// A mapped bit reads the complement of its idle bit while its signal is pressed; an unmapped bit reads its idle bit
// (MAME gives bits without a declared field whatever its port default is: e.g. 0 on some of Evil Stone's).
`default_nettype none
module taitol_ctrl (
    input  logic [119:0] id_flat,
    input  logic [23:0]  idle,
    input  logic [31:0]  sig,
    output logic [7:0]   in0, in1, in2
);
    logic [23:0] v;
    always_comb begin
        for (int i = 0; i < 24; i++) begin
            logic [4:0] id;
            id = id_flat[i*5 +: 5];
            v[i] = (id != 5'd0 && sig[id]) ? ~idle[i] : idle[i];
        end
    end
    assign in0 = v[7:0];
    assign in1 = v[15:8];
    assign in2 = v[23:16];
endmodule
`default_nettype wire
