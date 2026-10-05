// Z80 program ROM cache: the ROM is in SDRAM; the Z80 reads it through this direct-mapped 8 KB cache of 16-byte lines
// (8 words). A read that misses holds the Z80 with WAIT until the line has come (the Z80 steps once in 14 machine
// clocks, a hit is ready within four). Generalised from the MCatAdv core's mcatadv_zcache: AB address bits.
//
// byte address a[AB-1:0]:  tag a[AB-1:13] | index a[12:4] (9) | byte in line a[3:0]
`default_nettype none
module taitol_cache #(
    parameter AB = 20
) (
    input  logic          clk,
    input  logic          inval,            // rising edge: sweep all lines invalid (a ROM load starts)

    input  logic          rd,               // the Z80 is reading the ROM
    input  logic [AB-1:0] addr,
    output logic          hit,              // `data` is the byte at `addr`
    output logic [7:0]    data,

    output logic          fill_req,         // level, until fill_done: one burst of 8 words
    output logic [AB-1:4] fill_addr,        // line address (16-byte units)
    input  logic          fill_wr,
    input  logic [2:0]    fill_idx,
    input  logic [15:0]   fill_data,
    input  logic          fill_done
);
    localparam TW = AB - 13;
    typedef enum logic [1:0] { S_SWEEP, S_RUN, S_FILL, S_WAIT } st_t;
    logic [1:0] wcnt;
    st_t st = S_SWEEP;
    logic [8:0] sweep = 9'd0;
    logic       inval_d;
    logic [AB-1:0] a_q;                    // the address the RAM outputs belong to
    logic [8:0]  fidx;                     // the index being filled
    logic [TW-1:0] ftag;

    // tag RAM {valid, tag}; written combinationally so that a filled line is visible at once
    wire         tag_we    = (st == S_SWEEP) || (st == S_FILL && fill_done);
    wire  [8:0]  tag_waddr = (st == S_SWEEP) ? sweep : fidx;
    wire  [TW:0] tag_wdata = (st == S_SWEEP) ? {(TW+1){1'b0}} : {1'b1, ftag};
    logic [TW:0] tag_q;
    taitol_sdp #(.AW(9), .DW(TW + 1)) u_tag (.clk(clk), .we(tag_we), .waddr(tag_waddr), .wdata(tag_wdata),
                                              .raddr(addr[12:4]), .rdata(tag_q));

    // data RAM: 4096 words
    logic [15:0] dat_q;
    taitol_sdp #(.AW(12), .DW(16)) u_dat (.clk(clk), .we(fill_wr), .waddr({fidx, fill_idx}), .wdata(fill_data),
                                           .raddr(addr[12:1]), .rdata(dat_q));

    always_ff @(posedge clk) a_q <= addr;
    wire stable = (a_q == addr);
    wire match  = tag_q[TW] && (tag_q[TW-1:0] == a_q[AB-1:13]);
    assign hit  = stable && match && (st == S_RUN);
    assign data = a_q[0] ? dat_q[15:8] : dat_q[7:0];
    assign fill_addr = {ftag, fidx};

    always_ff @(posedge clk) begin
        inval_d <= inval;
        if (inval && !inval_d) begin
            st <= S_SWEEP; sweep <= 9'd0; fill_req <= 1'b0;
        end else case (st)
            S_SWEEP: begin
                sweep <= sweep + 9'd1;
                if (sweep == 9'h1ff) st <= S_RUN;
            end
            S_RUN: if (rd && stable && !match) begin
                ftag <= a_q[AB-1:13]; fidx <= a_q[12:4];
                fill_req <= 1'b1; st <= S_FILL;
            end
            S_FILL: if (fill_done) begin fill_req <= 1'b0; wcnt <= 2'd2; st <= S_WAIT; end     // the new tag reaches the read port in two clocks
            S_WAIT: begin wcnt <= wcnt - 2'd1; if (wcnt == 2'd1) st <= S_RUN; end
            default: st <= S_RUN;
        endcase
    end
endmodule
`default_nettype wire
