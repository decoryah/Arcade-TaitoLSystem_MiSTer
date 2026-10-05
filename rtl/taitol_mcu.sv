// Puzznic's MC68705P3 and its interface to the main Z80, after MAME (src/devices/cpu/m6805/m68705.cpp: the P3 peripherals;
// src/mame/shared/taito68705.cpp: arkanoid_68705p3_device, the "Arkanoid MC68705P3 Interface"). The 6805 core is jt6805
// (Jose Tejada, GPL-3, in modules/jt680x); everything around it is here.
//
// MC68705P3 (28 pins, 11-bit address space), as far as Puzznic's program uses it (it clears the timer control register, never
// uses the timer or interrupts: all five vectors point at 0080, and it polls port C):
//   0000 port A data   0001 port B data   0002 port C data (only 4 bits: the top four read 1)
//   0004-0006 DDR A-C (write only)   0008 timer data   0009 timer control   0010-007F RAM (112 bytes)   0080-0784 and 07F8-07FF EPROM
// A port reads (latch & DDR) | (pins & ~DDR). Port A is open drain: what the outside sees is latch | ~DDR.
//
// The interface (all of the Z80 <-> MCU talk is through it):
//   Z80 writes B800  -> host flag set, host latch = data, MCU IRQ line high while the flag is set; while the latch is
//                       "driven" the data appears on port A's pins
//   Z80 reads  B800  -> the MCU latch; clears the MCU flag
//   MCU port C reads: bit 0 = host flag, bit 1 = NOT MCU flag, the rest 1
//   MCU port C writes (data = the PC latch, called when a PC latch bit that is an output, or DDR C, changes):
//       PC2 rising  : release the host latch (port A pins -> FF) and clear the host flag (and the IRQ)
//       PC2 low     : drive the host latch onto port A's pins
//       PC3 low     : set the MCU flag; on its falling edge the MCU latch takes what port A's pins hold
// (Z80's B801 reads 1 and ignores writes: the board, not this module.)
`default_nettype none
module taitol_mcu (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen,              // the crystal (3.579545 MHz); the 6805 spends 4 of them on a bus cycle

    // the program, as the ROM loader streams it
    input  logic        rom_we,
    input  logic [10:0] rom_waddr,
    input  logic [7:0]  rom_wdata,

    // the Z80's side (strobes are levels of a few T-states: the edges are used)
    input  logic        host_wr,
    input  logic [7:0]  host_wdata,
    input  logic        host_rd,
    output logic [7:0]  host_rdata
);
    // ---------------------------------------------------------------- the CPU
    logic        cpu_wr, tstop;
    logic [12:0] a13;
    logic [7:0]  cpu_din, cpu_dout;
    logic        host_flag;
    jt6805 u_cpu (
        .rst(rst), .clk(clk), .cen(cen), .irq(host_flag), .tirq(1'b0),
        .wr(cpu_wr), .tstop(tstop), .addr(a13), .din(cpu_din), .dout(cpu_dout)
    );
    wire [10:0] a = a13[10:0];
    wire        wr_now = cen & cpu_wr;                    // the write lands at the end of the micro-step, with the core

    // ---------------------------------------------------------------- memories
    logic [7:0] rom_q, ram_q;
    taitol_ram8 #(.AW(11)) u_rom (.clk(clk), .we(rom_we), .addr(rom_we ? rom_waddr : a), .d(rom_wdata), .q(rom_q));
    taitol_ram8 #(.AW(7))  u_ram (.clk(clk), .we(wr_now && a >= 11'h010 && a < 11'h080), .addr(a[6:0]), .d(cpu_dout), .q(ram_q));
    logic rom_sel_q;
    always_ff @(posedge clk) rom_sel_q <= (a >= 11'h080 && a < 11'h785) || (a >= 11'h7F8);

    // ---------------------------------------------------------------- ports and timer registers
    logic [7:0] latch_a = 8'hFF, latch_b = 8'hFF, latch_c = 8'hFF;
    logic [7:0] ddr_a = 8'h00, ddr_b = 8'h00, ddr_c = 8'h00;
    logic [7:0] tdr = 8'hFF, tcr = 8'h7F;
    logic [7:0] pa_output = 8'hFF;                         // what the interface sees of port A (open drain)
    logic [7:0] pa_pins = 8'hFF;                           // port A's pins as the MCU reads them
    logic [7:0] pc_output = 8'hFF;                         // the last data the interface got from port C
    logic       latch_driven = 1'b0;
    logic [7:0] host_latch = 8'hFF, mcu_latch = 8'hFF;
    logic       mcu_flag = 1'b0;

    wire [7:0] pc_pins = {6'b111111, ~mcu_flag, host_flag};
    wire [7:0] rd_a = (latch_a & ddr_a) | (pa_pins & ~ddr_a);
    wire [7:0] rd_b = (latch_b & ddr_b) | (8'hFF & ~ddr_b);
    wire [7:0] rd_c = 8'hF0 | ((latch_c & ddr_c) | (pc_pins & ~ddr_c));

    // what port A reads while the host latch is released or driven
    function automatic [7:0] pa_value(input [7:0] out, input drv, input [7:0] hl);
        pa_value = out & (drv ? hl : 8'hFF);
    endfunction

    // host strobes -> single events
    logic host_wr_d, host_rd_d;
    logic       pc_call;                                   // the interface's port C callback fires, with data pc_data
    logic [7:0] pc_data;
    logic [7:0] old_pa;
    always_ff @(posedge clk) begin
        host_wr_d <= host_wr;
        host_rd_d <= host_rd;
        pc_call = 1'b0;
        pc_data = 8'hFF;
        if (rst) begin
            latch_a <= 8'hFF; latch_b <= 8'hFF; latch_c <= 8'hFF;
            ddr_a <= 8'h00; ddr_b <= 8'h00; ddr_c <= 8'h00;
            tdr <= 8'hFF; tcr <= 8'h7F;
            pa_output <= 8'hFF; pa_pins <= 8'hFF; pc_output <= 8'hFF;
            latch_driven <= 1'b0; host_latch <= 8'hFF; mcu_latch <= 8'hFF;
            host_flag <= 1'b0; mcu_flag <= 1'b0;
        end else begin
            // the Z80 writes B800 (data_w)
            if (host_wr && !host_wr_d) begin
                host_flag <= 1'b1;
                host_latch <= host_wdata;
                if (latch_driven) pa_pins <= host_wdata;
            end
            // the Z80 reads B800 (data_r)
            if (host_rd && !host_rd_d) mcu_flag <= 1'b0;

            // the MCU's own register writes
            if (wr_now) begin
                case (a)
                    11'h000: begin                       // port A latch: the interface hears about it if an output bit changed
                        latch_a <= cpu_dout;
                        if ((cpu_dout ^ latch_a) & ddr_a) pa_output <= cpu_dout | ~ddr_a;
                    end
                    11'h001: latch_b <= cpu_dout;
                    11'h002: begin                       // port C latch (4 bits wide)
                        latch_c <= cpu_dout | 8'hF0;
                        if (((cpu_dout | 8'hF0) ^ latch_c) & ddr_c & 8'h0F) begin pc_call = 1'b1; pc_data = cpu_dout | 8'hF0; end
                    end
                    11'h004: begin
                        ddr_a <= cpu_dout;
                        if (cpu_dout != ddr_a) pa_output <= latch_a | ~cpu_dout;
                    end
                    11'h005: ddr_b <= cpu_dout;
                    11'h006: begin
                        ddr_c <= cpu_dout & 8'h0F;
                        if ((cpu_dout & 8'h0F) != ddr_c) begin pc_call = 1'b1; pc_data = latch_c; end
                    end
                    11'h008: tdr <= cpu_dout;
                    11'h009: tcr <= (tcr & cpu_dout & 8'h80) | (cpu_dout & 8'h77);
                    default: ;
                endcase
            end

            // taito68705_mcu_device_base::latch_control(pc_data, m_pc_output, host_bit = 2, mcu_bit = 3)
            if (pc_call) begin
                old_pa = pa_value(pa_output, latch_driven, host_latch);
                if (pc_data[2]) begin
                    latch_driven <= 1'b0;                  // rising edge on PC2 releases the latch and clears the host flag
                    pa_pins <= 8'hFF;
                    if (!pc_output[2]) host_flag <= 1'b0;
                end else begin
                    latch_driven <= 1'b1;
                    pa_pins <= host_latch;
                end
                if (!pc_data[3]) begin                       // PC3 low sets the MCU flag; the MCU latch is taken on its falling edge
                    mcu_flag <= 1'b1;
                    if (pc_output[3]) mcu_latch <= old_pa;
                end
                pc_output <= pc_data;
            end
        end
    end
    assign host_rdata = mcu_latch;

    // ---------------------------------------------------------------- what the CPU reads
    logic [10:0] a_q;
    always_ff @(posedge clk) a_q <= a;
    always_comb begin
        cpu_din = 8'hFF;
        if (a_q < 11'h010) begin
            case (a_q[3:0])
                4'h0: cpu_din = rd_a;
                4'h1: cpu_din = rd_b;
                4'h2: cpu_din = rd_c;
                4'h8: cpu_din = tdr;
                4'h9: cpu_din = tcr;
                default: cpu_din = 8'hFF;                // DDRs read FF; the rest is unused
            endcase
        end else if (a_q < 11'h080) cpu_din = ram_q;
        else if (rom_sel_q)        cpu_din = rom_q;
        else                       cpu_din = 8'h00;       // the bootstrap ROM (0785-07F7) is not modelled
    end
endmodule
`default_nettype wire
