// Taito's sound communication chip, PC060HA (Champion Wrestler, Fighting Hawk) and TC0140SYT (Raimais): one behaviour, after MAME's
// src/mame/shared/taitosnd.cpp (tc0140syt_device).
//
// Two ports on each side, a nibble wide: the "master" CPU (the one that has the chip mapped as a port register and a
// communication register) and the sound CPU (the "slave" side). The port register selects a "mode"; the communication register
// then reads / writes the nibble of that mode and (modes 0-3) advances the mode:
//   master  mode 0-3 write: slave_data[mode] = nibble;   mode 1 / 3 also set the "port 01 / 23 full" status bit and may raise the
//                                                        sound CPU's NMI;  mode 4 write: sound CPU reset line = (nibble != 0)
//   master  mode 0-3 read: master_data[mode]  (reading mode 1 / 3 clears "port 01 / 23 full (master)");  mode 4 read: status
//   slave   mode 0-3 write: master_data[mode] = nibble;  mode 1 / 3 set the master's full bits;  mode 5 / 6: NMI disable / enable
//   slave   mode 0-3 read: slave_data[mode]   (mode 1 / 3 clear the full bits and update the NMI);   mode 4 read: status
//   status  bit0 port 01 full (for the slave), bit1 port 23 full, bit2 port 01 full (for the master), bit3 port 23 full
//   NMI = (status[1:0] != 0) && nmi enabled
// Reads return the old mode's data and the mode advances when the read cycle ends; writes act on the rising edge of the strobe.
`default_nettype none
module taitol_syt (
    input  logic        clk,
    input  logic        rst,

    // master side
    input  logic        m_port_wr,
    input  logic        m_comm_wr,
    input  logic        m_comm_rd,
    input  logic [7:0]  m_wdata,
    output logic [7:0]  m_rdata,

    // slave side
    input  logic        s_port_wr,
    input  logic        s_comm_wr,
    input  logic        s_comm_rd,
    input  logic [7:0]  s_wdata,
    output logic [7:0]  s_rdata,

    output logic        nmi,
    output logic        sound_reset           // level: the sound CPU is held in reset
);
    logic [3:0] mmode, smode;
    logic [3:0] sdata [4];                    // master -> slave
    logic [3:0] mdata [4];                    // slave -> master
    logic [3:0] status;
    logic       nmi_en;

    logic m_pw_d, m_cw_d, m_cr_d, s_pw_d, s_cw_d, s_cr_d;
    always_ff @(posedge clk) begin
        m_pw_d <= m_port_wr; m_cw_d <= m_comm_wr; m_cr_d <= m_comm_rd;
        s_pw_d <= s_port_wr; s_cw_d <= s_comm_wr; s_cr_d <= s_comm_rd;
    end
    wire m_pw = m_port_wr & ~m_pw_d, m_cw = m_comm_wr & ~m_cw_d, m_cr_end = ~m_comm_rd & m_cr_d;
    wire s_pw = s_port_wr & ~s_pw_d, s_cw = s_comm_wr & ~s_cw_d, s_cr_end = ~s_comm_rd & s_cr_d;

    assign nmi = (|status[1:0]) & nmi_en;

    // what a read of the communication register returns now
    always_comb begin
        m_rdata = 8'h00;
        s_rdata = 8'h00;
        if (mmode < 4'd4)       m_rdata = {4'h0, mdata[mmode[1:0]]};
        else if (mmode == 4'd4) m_rdata = {4'h0, status};
        if (smode < 4'd4)       s_rdata = {4'h0, sdata[smode[1:0]]};
        else if (smode == 4'd4) s_rdata = {4'h0, status};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mmode <= 4'd0; smode <= 4'd0; status <= 4'd0; nmi_en <= 1'b0; sound_reset <= 1'b0;
            for (int i = 0; i < 4; i++) begin sdata[i] <= 4'd0; mdata[i] <= 4'd0; end
        end else begin
            // ---- master
            if (m_pw) mmode <= m_wdata[3:0];                                 // a mode above 4 is "unknown" and does nothing
            if (m_cw) begin
                case (mmode)
                    4'd0: begin sdata[0] <= m_wdata[3:0]; mmode <= 4'd1; end
                    4'd1: begin sdata[1] <= m_wdata[3:0]; mmode <= 4'd2; status[0] <= 1'b1; end
                    4'd2: begin sdata[2] <= m_wdata[3:0]; mmode <= 4'd3; end
                    4'd3: begin sdata[3] <= m_wdata[3:0]; mmode <= 4'd4; status[1] <= 1'b1; end
                    4'd4: sound_reset <= |m_wdata[3:0];
                    default: ;
                endcase
            end
            if (m_cr_end) begin
                case (mmode)
                    4'd0: mmode <= 4'd1;
                    4'd1: begin mmode <= 4'd2; status[2] <= 1'b0; end
                    4'd2: mmode <= 4'd3;
                    4'd3: begin mmode <= 4'd4; status[3] <= 1'b0; end
                    default: ;
                endcase
            end
            // ---- slave
            if (s_pw) smode <= s_wdata[3:0];
            if (s_cw) begin
                case (smode)
                    4'd0: begin mdata[0] <= s_wdata[3:0]; smode <= 4'd1; end
                    4'd1: begin mdata[1] <= s_wdata[3:0]; smode <= 4'd2; status[2] <= 1'b1; end
                    4'd2: begin mdata[2] <= s_wdata[3:0]; smode <= 4'd3; end
                    4'd3: begin mdata[3] <= s_wdata[3:0]; smode <= 4'd4; status[3] <= 1'b1; end
                    4'd5: nmi_en <= 1'b0;
                    4'd6: nmi_en <= 1'b1;
                    default: ;
                endcase
            end
            if (s_cr_end) begin
                case (smode)
                    4'd0: smode <= 4'd1;
                    4'd1: begin smode <= 4'd2; status[0] <= 1'b0; end
                    4'd2: smode <= 4'd3;
                    4'd3: begin smode <= 4'd4; status[1] <= 1'b0; end
                    default: ;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
