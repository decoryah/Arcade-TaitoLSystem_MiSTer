// Whole-machine bench: taitol_core behind taitol_mem and a behavioural SDRAM chip. The C++ side preloads the chip (DPI)
// with the ROM image, or pushes it through the loader (dl_*).
`default_nettype none
module tb_system_top (
    input  logic        clk,
    input  logic        clk_vid,

    output logic        dl_wait,
    output logic        dl_busy,
    output logic        mem_ready,

    output logic        ce_pix,
    output logic        hblank, vblank, hsync, vsync,
    output logic [23:0] rgb,
    output logic signed [15:0] snd_l, snd_r,
    output logic        snd_valid,

    output logic        dbg_ovr, dbg_irq, dbg_m1, dbg_ym_wr, dbg_ym_a0,
    output logic [7:0]  dbg_ym_d,
    output logic [3:0]  dbg_busy,
    output logic [3:0]  dbg_ovr_bits,
    output logic [15:0] cpu_a,
    output logic [7:0]  cpu_dout, cpu_di,
    output logic        cpu_rd, cpu_wr, cpu_m1
);
    // The inputs other than the two clocks are registers set through DPI (tb_set_*): with only the clocks as top-level
    // inputs Verilator's input-combinational region stays small (it ran the whole Z80's logic on every clock edge
    // when reset, the controls and the loader were ports: half of the run time).
    logic        rst = 1'b1;                // the machine (CPU, sound)
    logic        vid_rst = 1'b1;            // the renderers
    logic        init = 1'b1;               // the SDRAM controller
    logic        dl_we = 1'b0;
    logic [24:0] dl_addr = '0;
    logic [7:0]  dl_data = '0;
    logic [7:0]  dswa = 8'hFF, dswb = 8'hFF;
    logic [31:0] sig = 32'd0;
    logic [119:0] cfg_in_id;
    logic [23:0] cfg_in_idle;
    logic [7:0]  in0, in1, in2;
    logic        mcu_we;
    logic [10:0] mcu_waddr;
    logic [7:0]  mcu_wdata;
    logic        sub_we;
    logic [15:0] sub_waddr;
    logic [7:0]  sub_wdata;
    taitol_ctrl u_ctrl (.id_flat(cfg_in_id), .idle(cfg_in_idle), .sig(sig), .in0(in0), .in1(in1), .in2(in2));
    export "DPI-C" function tb_set_ctl;
    function void tb_set_ctl(input int r, input int vr, input int i);
        rst = r[0]; vid_rst = vr[0]; init = i[0];
    endfunction
    // the trackball: counter steps (strobes held by the C++ side for a few clocks)
    logic tb_ax = 1'b0, tb_ay = 1'b0;
    logic signed [8:0] tb_ddx = 9'sd0, tb_ddy = 9'sd0;
    export "DPI-C" function tb_trk;
    function void tb_trk(input int ax, input int dx, input int ay, input int dy);
        tb_ax = ax[0]; tb_ddx = dx[8:0]; tb_ay = ay[0]; tb_ddy = dy[8:0];
    endfunction
    export "DPI-C" function tb_set_in;
    function void tb_set_in(input int a, input int b, input int signals);
        dswa = a[7:0]; dswb = b[7:0]; sig = signals;
    endfunction
    export "DPI-C" function tb_set_dl;
    function void tb_set_dl(input int we, input int addr, input int data);
        dl_we = we[0]; dl_addr = addr[24:0]; dl_data = data[7:0];
    endfunction

    wire  [15:0] dram_dq;
    wire  [12:0] dram_a;
    wire  [1:0]  dram_ba;
    wire         dram_dqml, dram_dqmh, dram_ncs, dram_nras, dram_ncas, dram_nwe, dram_cke, dram_clk;

    logic        p_req, g0_req, g1_req, gs_req, s_req, a_req, m_req;
    logic [16:4] m_addr;
    logic        m_wr, m_done;
    logic  [2:0] m_idx;
    logic [15:0] m_data;
    logic [16:4] s_addr;
    logic [15:4] a_addr;
    logic        s_wr, a_wr, s_done, a_done;
    logic  [2:0] s_idx, a_idx;
    logic [15:0] s_data, a_data;
    logic [19:4] p_addr;
    logic [24:1] g0_addr, g1_addr, gs_addr;
    logic        p_wr, g0_wr, g1_wr, gs_wr, p_done, g0_done, g1_done, gs_done;
    logic [2:0]  p_idx;
    logic [1:0]  g0_idx, g1_idx, gs_idx;
    logic [15:0] p_data, g0_data, g1_data, gs_data;
    logic [3:0]  cfg_board;
    logic [15:0] cfg_n8;
    logic [17:0] cfg_pmask;
    logic [19:0] cfg_rmask;
    logic [1:0]  cfg_rot;
    logic [7:0]  cfg_flags;

    taitol_mem u_mem (
        .clk(clk), .clk_sdram(clk), .init(init), .rd_late(1'b0), .ready(mem_ready),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .dl_wait(dl_wait), .dl_busy(dl_busy),
        .cfg_board(cfg_board), .cfg_n8(cfg_n8), .cfg_pmask(cfg_pmask), .cfg_rmask(cfg_rmask), .cfg_rot(cfg_rot), .cfg_flags(cfg_flags),
        .cfg_in_id(cfg_in_id), .cfg_in_idle(cfg_in_idle), .mcu_we(mcu_we), .mcu_waddr(mcu_waddr), .mcu_wdata(mcu_wdata),
        .sub_we(sub_we), .sub_waddr(sub_waddr), .sub_wdata(sub_wdata),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
        .m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done),
        .g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
        .g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
        .gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
        .SDRAM_DQ(dram_dq), .SDRAM_A(dram_a), .SDRAM_DQML(dram_dqml), .SDRAM_DQMH(dram_dqmh), .SDRAM_BA(dram_ba),
        .SDRAM_nCS(dram_ncs), .SDRAM_nWE(dram_nwe), .SDRAM_nRAS(dram_nras), .SDRAM_nCAS(dram_ncas),
        .SDRAM_CKE(dram_cke), .SDRAM_CLK(dram_clk)
    );

    sdram_model #(.PHASE_LAG(0), .AW(23)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqml), .dqmh(dram_dqmh),
        .cs_n(dram_ncs), .ras_n(dram_nras), .cas_n(dram_ncas), .we_n(dram_nwe), .cke(dram_cke)
    );

    taitol_core u_core (
        .clk(clk), .clk_vid(clk_vid), .rst(rst), .vid_rst(vid_rst), .cache_inval(init),
        .cfg_board(cfg_board), .cfg_pmask(cfg_pmask), .cfg_n8({1'b0, cfg_n8}), .cfg_rmask(cfg_rmask), .cfg_flags(cfg_flags), .opt_scr_latch(1'b0),
        .p_req(p_req), .p_addr(p_addr), .p_wr(p_wr), .p_idx(p_idx), .p_data(p_data), .p_done(p_done),
        .s_req(s_req), .s_addr(s_addr), .s_wr(s_wr), .s_idx(s_idx), .s_data(s_data), .s_done(s_done),
        .a_req(a_req), .a_addr(a_addr), .a_wr(a_wr), .a_idx(a_idx), .a_data(a_data), .a_done(a_done),
        .m_req(m_req), .m_addr(m_addr), .m_wr(m_wr), .m_idx(m_idx), .m_data(m_data), .m_done(m_done),
        .g0_req(g0_req), .g0_addr(g0_addr), .g0_wr(g0_wr), .g0_idx(g0_idx), .g0_data(g0_data), .g0_done(g0_done),
        .g1_req(g1_req), .g1_addr(g1_addr), .g1_wr(g1_wr), .g1_idx(g1_idx), .g1_data(g1_data), .g1_done(g1_done),
        .gs_req(gs_req), .gs_addr(gs_addr), .gs_wr(gs_wr), .gs_idx(gs_idx), .gs_data(gs_data), .gs_done(gs_done),
        .dswa(dswa), .dswb(dswb), .in0(in0), .in1(in1), .in2(in2),
        .mcu_we(mcu_we), .mcu_waddr(mcu_waddr), .mcu_wdata(mcu_wdata),
        .sub_we(sub_we), .sub_waddr(sub_waddr), .sub_wdata(sub_wdata),
        .tb_add_x(tb_ax), .tb_add_y(tb_ay), .tb_dx(tb_ddx), .tb_dy(tb_ddy),
        .ce_pix(ce_pix), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .rgb(rgb),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
        .dbg_ovr(dbg_ovr), .dbg_ovr_bits(dbg_ovr_bits), .dbg_busy(dbg_busy), .dbg_irq(dbg_irq), .dbg_m1(dbg_m1), .dbg_ym_wr(dbg_ym_wr), .dbg_ym_a0(dbg_ym_a0), .dbg_ym_d(dbg_ym_d)
    );
    assign cpu_a  = u_core.u_main.A;
    assign cpu_rd = u_core.u_main.mem_rd;
    assign cpu_wr = u_core.u_main.mem_wr;
    assign cpu_dout = u_core.u_main.dout;
    assign cpu_di   = u_core.u_main.di;
    assign cpu_m1   = u_core.u_main.dbg_m1;

    // ---------------------------------------------------------------- backdoors for the C++ side
    export "DPI-C" function tb_sdram_write;
    function void tb_sdram_write(input int idx, input int w);
        chip.mem[idx[22:0]] = w[15:0];
    endfunction
    export "DPI-C" function tb_sdram_read;
    function int tb_sdram_read(input int idx);
        return {16'd0, chip.mem[idx[22:0]]};
    endfunction
    // the configuration the loader would have captured (a preloaded image does not go through it)
    export "DPI-C" function tb_cfg;
    function void tb_cfg(input int board, input int n8, input int pmask, input int rmask, input int rot, input int flags);
        u_mem.cfg_board = board[3:0];
        u_mem.cfg_n8    = n8[15:0];
        u_mem.cfg_pmask = pmask[17:0];
        u_mem.cfg_rmask = rmask[19:0];
        u_mem.cfg_rot   = rot[1:0];
        u_mem.cfg_flags = flags[7:0];
    endfunction
    // the controls' wiring (what the loader would have captured)
    export "DPI-C" function tb_cfg_in;
    function void tb_cfg_in(input int idx, input int val);
        if (idx < 24) u_mem.cfg_in_id[idx * 5 +: 5] = val[4:0];
        else u_mem.cfg_in_idle[(idx - 24) * 8 +: 8] = val[7:0];
    endfunction
    // the MC68705's program (a preloaded image does not go through the loader's write port)
    export "DPI-C" function tb_mcu_rom;
    function void tb_mcu_rom(input int idx, input int val);
        u_core.u_board.u_mcu.u_rom.mem[idx[10:0]] = val[7:0];
    endfunction
    // the second Z80's program (the same)
    export "DPI-C" function tb_sub_rom;
    function void tb_sub_rom(input int idx, input int val);
        u_core.u_board.u_sub.u_rom.mem[idx[15:0]] = val[7:0];
    endfunction
    // the sound chip's two sections (not in the NOYM build)
    export "DPI-C" function tb_ym_psg;
    function int tb_ym_psg(input int dummy);
`ifdef NOYM
        return 0;
`else
        return {22'd0, u_core.u_board.u_ym.psg_snd};
`endif
    endfunction
    export "DPI-C" function tb_ym_fm;
    function int tb_ym_fm(input int dummy);
`ifdef NOYM
        return 0;
`else
        return int'(signed'(u_core.u_board.u_ym.fm_snd));
`endif
    endfunction
    // scroll registers and the raster line, for the bench's tearing log
    export "DPI-C" function tb_scroll;
    function int tb_scroll(input int which);
        case (which)
            0: return {16'd0, u_core.u_vcore.bg0_sx};
            1: return {24'd0, u_core.u_vcore.bg0_sy};
            2: return {16'd0, u_core.u_vcore.bg1_sx};
            3: return {24'd0, u_core.u_vcore.bg1_sy};
            4: return {23'd0, u_core.u_vcore.lk};
            6: return u_core.u_main.tbank;
            7: return {24'd0, u_core.u_main.irq_en};
            default: return {24'd0, u_core.u_main.vr[4]};
        endcase
    endfunction
    // a window onto the machine for the C++ side
    export "DPI-C" function tb_vram;
    function int tb_vram(input int i);
        return {24'd0, u_core.u_vcore.u_vmem.u_vram.mem[i[15:0]]};
    endfunction
    export "DPI-C" function tb_bitmap;
    function int tb_bitmap(input int i);
        return {24'd0, u_core.u_vcore.u_vmem.u_bm.mem[i[16:0]]};
    endfunction
    export "DPI-C" function tb_pal;
    function int tb_pal(input int i);
        return i[0] ? {24'd0, u_core.u_vcore.u_vmem.u_pal_h.mem[i[8:1]]} : {24'd0, u_core.u_vcore.u_vmem.u_pal_l.mem[i[8:1]]};
    endfunction
    export "DPI-C" function tb_vreg;
    function int tb_vreg(input int i);
        return {24'd0, u_core.u_main.vr[i[2:0]]};
    endfunction
    export "DPI-C" function tb_sprbuf;
    function int tb_sprbuf(input int e, input int b);
        logic [63:0] w;
        w = u_core.u_vcore.u_vmem.u_sbuf.mem[e[6:0]];
        return {24'd0, w[b[2:0]*8 +: 8]};
    endfunction
endmodule
`default_nettype wire
