// MCU bench: taitol_mcu (jt6805 + the MC68705P3's ports and the Taito host interface) alone, driven like Puzznic's Z80
// drives it. The C++ side loads the 2 KB program, plays the host side of the handshake and logs the MCU's port accesses.
`default_nettype none
module tb_mcu_top (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen,
    input  logic        rom_we,
    input  logic [10:0] rom_waddr,
    input  logic [7:0]  rom_wdata,
    input  logic        host_wr,
    input  logic [7:0]  host_wdata,
    input  logic        host_rd,
    output logic [7:0]  host_rdata,
    output logic [12:0] dbg_a,
    output logic        dbg_wr,
    output logic [7:0]  dbg_din,
    output logic [7:0]  dbg_dout,
    output logic        dbg_host_flag,
    output logic        dbg_mcu_flag,
    output logic [7:0]  dbg_host_latch,
    output logic [7:0]  dbg_mcu_latch,
    output logic [7:0]  dbg_pa_pins
);
    taitol_mcu u_mcu (
        .clk(clk), .rst(rst), .cen(cen), .rom_we(rom_we), .rom_waddr(rom_waddr), .rom_wdata(rom_wdata),
        .host_wr(host_wr), .host_wdata(host_wdata), .host_rd(host_rd), .host_rdata(host_rdata)
    );
    assign dbg_a = u_mcu.a13;
    assign dbg_wr = u_mcu.cpu_wr;
    assign dbg_din = u_mcu.cpu_din;
    assign dbg_dout = u_mcu.cpu_dout;
    assign dbg_host_flag = u_mcu.host_flag;
    assign dbg_mcu_flag = u_mcu.mcu_flag;
    assign dbg_host_latch = u_mcu.host_latch;
    assign dbg_mcu_latch = u_mcu.mcu_latch;
    assign dbg_pa_pins = u_mcu.pa_pins;
endmodule
`default_nettype wire
