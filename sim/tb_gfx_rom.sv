// Behavioural graphics ROM with the three burst clients of taitol_vcore (2-word bursts), for the video bench.
// Request protocol (as the real memory system's): level req + word address; one word per wr strobe with its index;
// a done pulse in the cycle after the last word, in which the client drops its request.
`default_nettype none
module tb_gfx_rom #(
    parameter [24:1] BASE = 24'h080000,
    parameter        AW   = 21,
    parameter        LAT  = 6
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        g0_req, input logic [24:1] g0_addr,
    output logic        g0_wr,  output logic [1:0] g0_idx, output logic [15:0] g0_data, output logic g0_done,
    input  logic        g1_req, input logic [24:1] g1_addr,
    output logic        g1_wr,  output logic [1:0] g1_idx, output logic [15:0] g1_data, output logic g1_done,
    input  logic        gs_req, input logic [24:1] gs_addr,
    output logic        gs_wr,  output logic [1:0] gs_idx, output logic [15:0] gs_data, output logic gs_done
);
    logic [15:0] rom [0:(1<<AW)-1];
    string path;
    initial begin
        if ($value$plusargs("gfx=%s", path)) $readmemh(path, rom);
        else $display("tb_gfx_rom: no +gfx=<hex file>");
    end

    typedef enum logic [2:0] { S_IDLE, S_LAT, S_W0, S_W1, S_ACK } st_t;
    st_t st = S_IDLE;
    logic [1:0]  sel;
    logic [24:1] a;
    logic [4:0]  cnt;
    wire  [AW-1:0] ra = AW'(a - BASE);
    logic wr;
    logic [15:0] data;
    logic idx;
    always_ff @(posedge clk) begin
        wr <= 1'b0;
        if (rst) st <= S_IDLE;
        else case (st)
            S_IDLE: begin
                if (g0_req)      begin sel <= 2'd0; a <= g0_addr; cnt <= LAT; st <= S_LAT; end
                else if (g1_req) begin sel <= 2'd1; a <= g1_addr; cnt <= LAT; st <= S_LAT; end
                else if (gs_req) begin sel <= 2'd2; a <= gs_addr; cnt <= LAT; st <= S_LAT; end
            end
            S_LAT: begin cnt <= cnt - 5'd1; if (cnt == 5'd1) st <= S_W0; end
            S_W0:  begin wr <= 1'b1; idx <= 1'b0; data <= rom[ra];        st <= S_W1; end
            S_W1:  begin wr <= 1'b1; idx <= 1'b1; data <= rom[ra + 1'b1]; st <= S_ACK; end
            S_ACK: st <= S_IDLE;
            default: st <= S_IDLE;
        endcase
    end
    wire ack = (st == S_ACK);
    assign g0_wr = wr && sel == 2'd0;  assign g0_idx = {1'b0, idx}; assign g0_data = data; assign g0_done = ack && sel == 2'd0;
    assign g1_wr = wr && sel == 2'd1;  assign g1_idx = {1'b0, idx}; assign g1_data = data; assign g1_done = ack && sel == 2'd1;
    assign gs_wr = wr && sel == 2'd2;  assign gs_idx = {1'b0, idx}; assign gs_data = data; assign gs_done = ack && sel == 2'd2;
endmodule
`default_nettype wire
