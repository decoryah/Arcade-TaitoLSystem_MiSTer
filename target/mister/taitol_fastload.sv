// Fast load: with address="0x32000000" on the MRA's index-0 <rom>, a recent Main_MiSTer copies the whole assembled image into the DDR3
// at that byte address in one memcpy, bracketed by a download without a data byte that starts with ioctl_addr = the image's length
// (an ordinary download starts at 0: TaitoL.sv tells them apart). This reads the image back and hands it to taitol_mem's loader a byte
// at a time, in order, as the HPS would (dl_we / dl_addr / dl_data, held off by dl_wait), so the loader, its layout and its capture of the
// configuration bytes are unchanged. An older Main_MiSTer ignores address= and sends the image the ordinary way.
//
// After the owner's Crospang core (cp_fastload.sv), with one difference: here the DDR3 port is also the rotated frame buffer's
// (screen_rotate, on the video clock), so the DDR3 side runs on clk_ddr (the video clock) and owns the port (`own`) while it reads; the
// top level drops screen_rotate's writes meanwhile (they are single fire-and-forget beats; the machine is held during a load anyway).
// The words cross to the loader's clock one 64-bit beat at a time with a toggle handshake (the beat is held until it is acknowledged).
//
// DDRAM_ADDR is the beat address in the HPS's whole space (byte = 8 x beat): the image at byte 0x32000000 starts at beat 0x6400000,
// clear of sys/arcade_video.v's frame buffer at byte 0x24000000. Bursts of 32 beats (256 bytes); byte n of a beat is bits 8n+7..8n.
`default_nettype none
module taitol_fastload #(
    parameter [28:0] BASE = 29'h6400000
) (
    // the loader's clock
    input  logic        clk,
    input  logic        rst,
    input  logic        go,                    // one clock: the empty download has ended, the image is in the DDR3
    input  logic        cancel,                 // an ordinary download is going on: hand over nothing
    input  logic [24:0] len,                   // the image's length in bytes (stable from the download's start)
    output logic        done,                  // one clock: the last byte has been handed over
    output logic        dl_we,
    output logic [24:0] dl_addr,
    output logic  [7:0] dl_data,
    input  logic        dl_wait,

    // the DDR3 port's clock (the video clock)
    input  logic        clk_ddr,
    output logic        own,                   // the port is ours: drop the frame buffer's writes
    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD
);
    localparam int BEATS = 32;

    // ------------------------------------------------------------------ toggles across the two clocks
    logic start_t = 1'b0;                      // clk:     a load is to start
    logic req_t   = 1'b0;                      // clk_ddr: xfer_* holds a new beat
    logic ack_t   = 1'b0;                      // clk:     that beat has been handed over
    logic done_t  = 1'b0;                      // clk_ddr: the whole image has been read

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] start_s = '0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] ack_s   = '0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] req_s   = '0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] done_s  = '0;

    logic [63:0] xfer_data;                    // clk_ddr, held from req_t until ack_t
    logic [24:0] xfer_off;

    // ------------------------------------------------------------------ the DDR3 side (clk_ddr)
    logic [63:0] blk [BEATS];
    logic [63:0] blk_q;
    logic  [4:0] wi, ri;
    logic [24:0] off, len_v;
    logic        vbusy = 1'b0;
    logic        seen_start = 1'b0;

    typedef enum logic [2:0] { V_IDLE, V_REQ, V_RX, V_RD, V_RD2, V_WAIT } vst_t;
    vst_t vst = V_IDLE;

    always_ff @(posedge clk_ddr) blk_q <= blk[ri];

    always_ff @(posedge clk_ddr) begin
        start_s <= {start_s[1:0], start_t};
        ack_s   <= {ack_s[1:0], ack_t};
        if (DDRAM_RD && !DDRAM_BUSY) DDRAM_RD <= 1'b0;             // taken
        case (vst)
            V_IDLE: if (start_s[2] != seen_start) begin
                seen_start <= start_s[2];
                len_v <= len;                                    // stable for the whole load
                off <= '0; vbusy <= 1'b1; vst <= V_REQ;
            end
            V_REQ: if (off >= len_v) begin
                vbusy <= 1'b0; done_t <= ~done_t; vst <= V_IDLE;
            end else begin
                DDRAM_RD <= 1'b1; DDRAM_ADDR <= BASE + 29'(off[24:3]); DDRAM_BURSTCNT <= 8'(BEATS); wi <= '0; vst <= V_RX;
            end
            V_RX: if (DDRAM_DOUT_READY) begin
                blk[wi] <= DDRAM_DOUT;
                wi <= wi + 5'd1;
                if (wi == 5'(BEATS - 1)) begin ri <= '0; vst <= V_RD; end
            end
            V_RD:  vst <= V_RD2;                                  // blk_q follows ri a clock later
            V_RD2: begin xfer_data <= blk_q; xfer_off <= off; req_t <= ~req_t; vst <= V_WAIT; end
            V_WAIT: if (ack_s[2] == req_t) begin
                off <= off + 25'd8;
                if (off + 25'd8 >= len_v || ri == 5'(BEATS - 1)) vst <= V_REQ;
                else begin ri <= ri + 5'd1; vst <= V_RD; end
            end
            default: vst <= V_IDLE;
        endcase
    end
    assign own = vbusy | DDRAM_RD;

    // ------------------------------------------------------------------ the loader side (clk)
    logic [63:0] cur;
    logic [24:0] o;
    logic  [2:0] bi;
    logic        sbusy = 1'b0;
    logic        live  = 1'b0;                 // a fast load is being handed over (not aborted)

    always_ff @(posedge clk) begin
        req_s  <= {req_s[1:0], req_t};
        done_s <= {done_s[1:0], done_t};
        dl_we  <= 1'b0;
        done   <= 1'b0;
        if (go) begin start_t <= ~start_t; live <= 1'b1; end
        if (cancel) live <= 1'b0;
        if (done_s[2] != done_s[1]) begin done <= live; live <= 1'b0; end
        if (rst) begin
            sbusy <= 1'b0; live <= 1'b0;
        end else if (!sbusy) begin
            if (req_s[2] != ack_t) begin                         // a beat is waiting (xfer_* has been stable for 2+ clocks)
                cur <= xfer_data; o <= xfer_off; bi <= '0; sbusy <= 1'b1;
            end
        end else if (!live) begin
            ack_t <= req_s[2]; sbusy <= 1'b0;                    // aborted: take the beat and drop it
        end else if (!dl_wait) begin
            if (o >= len) begin
                ack_t <= req_s[2]; sbusy <= 1'b0;                // past the image's end
            end else begin
                dl_we <= 1'b1; dl_addr <= o; dl_data <= cur[7:0];
                cur <= cur >> 8; o <= o + 25'd1; bi <= bi + 3'd1;
                if (bi == 3'd7) begin ack_t <= req_s[2]; sbusy <= 1'b0; end
            end
        end
    end
endmodule
`default_nettype wire
