// Block RAM building blocks, written the way Quartus 17 infers M10K reliably (byte-wide arrays,
// whole-element writes, registered reads, no read-during-write check); the shapes are those of the
// MCatAdv core's mcatadv_ram.sv.
`default_nettype none

// single port, byte wide
module taitol_ram8 #(
    parameter AW = 13
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] addr,
    input  logic [7:0]    d,
    output logic [7:0]    q
);
    (* ramstyle = "no_rw_check" *) logic [7:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clk) begin
        if (we) mem[addr] <= d;
        q <= mem[addr];
    end
endmodule

// true dual port, byte wide: port A reads and writes, port B reads (its own clock)
module taitol_dpram8 #(
    parameter AW = 16
) (
    input  logic          clka,
    input  logic          wea,
    input  logic [AW-1:0] addra,
    input  logic [7:0]    da,
    output logic [7:0]    qa,
    input  logic          clkb,
    input  logic [AW-1:0] addrb,
    output logic [7:0]    qb
);
    (* ramstyle = "no_rw_check" *) logic [7:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clka) begin
        if (wea) mem[addra] <= da;
        qa <= mem[addra];
    end
    always_ff @(posedge clkb) qb <= mem[addrb];
endmodule

// simple dual port, one clock
module taitol_sdp #(
    parameter AW = 7,
    parameter DW = 64
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
);
    (* ramstyle = "no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

// simple dual port with separate write and read clocks (line buffers, palette)
module taitol_sdp2 #(
    parameter AW = 10,
    parameter DW = 8
) (
    input  logic          wclk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic          rclk,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
);
    (* ramstyle = "no_rw_check" *) logic [DW-1:0] mem [0:(1<<AW)-1];
    always_ff @(posedge wclk) if (we) mem[waddr] <= wdata;
    always_ff @(posedge rclk) rdata <= mem[raddr];
endmodule
// true dual port, byte wide, both ports read and write, one clock (the MB8421 dual-port RAM of the 2- and 3-CPU boards)
module taitol_tdp8 #(
    parameter AW = 11
) (
    input  logic          clk,
    input  logic          wea,
    input  logic [AW-1:0] addra,
    input  logic [7:0]    da,
    output logic [7:0]    qa,
    input  logic          web,
    input  logic [AW-1:0] addrb,
    input  logic [7:0]    db,
    output logic [7:0]    qb
);
    (* ramstyle = "no_rw_check" *) logic [7:0] mem [0:(1<<AW)-1];
    always_ff @(posedge clk) begin
        if (wea) mem[addra] <= da;
        qa <= mem[addra];
    end
    always_ff @(posedge clk) begin
        if (web) mem[addrb] <= db;
        qb <= mem[addrb];
    end
endmodule
`default_nettype wire
