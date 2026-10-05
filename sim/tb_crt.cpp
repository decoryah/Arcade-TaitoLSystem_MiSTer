// tb_crt: for a set of (on, hsize, hpos, vshift) settings, run a few frames and report the adjusted stream against the native one.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include "Vtb_crt_top.h"
#include "verilated.h"

static Vtb_crt_top* t;
static uint64_t nv = 0;
static void tick() { t->clk_vid = 0; t->eval(); t->clk_vid = 1; t->eval(); nv++; }

struct R { long hs_period, vs_period; long hs_shift_px; long vs_shift_lines; long av_ce_per_line; long hb_width; };

static R run(int on, int hsize, int hpos, int vshift) {
    t->osd_on = on; t->osd_hsize = hsize; t->osd_hpos = hpos; t->osd_vshift = vshift;
    t->clk_sys = 0;
    for (int i = 0; i < 4 * 424 * 262 * 3; i++) tick();                 // settle: the controls are sampled in vertical blanking
    // measure over 2 frames: native pixel index of each native / adjusted hsync rise, vsync rise
    long pix = 0, line = 0;
    int phs = 0, pavhs = 0, pvs = 0, pavs = 0, pce = 0;
    long nat_hs = -1, adj_hs = -1, nat_vs = -1, adj_vs = -1;
    long hs_p = 0, vs_p = 0, last_nhs = -1, last_nvs = -1;
    long ce_count = 0, ce_lines = 0, hbw = 0, hbmax = 0;
    long nat_hs_line_start = 0;
    std::vector<long> shifts, vshifts;
    long frame_pix = 0;
    for (int i = 0; i < 4 * 424 * 262 * 2 + 4 * 424 * 262; i++) {
        tick();
        if (t->ce_pix) {
            pix++;
            if (t->hsync && !phs) { if (last_nhs >= 0) hs_p = pix - last_nhs; last_nhs = pix; nat_hs = pix; line++; if (ce_lines) {} }
            phs = t->hsync;
            if (t->vsync && !pvs) { if (last_nvs >= 0) vs_p = line - last_nvs; last_nvs = line; nat_vs = line; }
            pvs = t->vsync;
        }
        if (t->av_ce) {
            if (t->av_hs && !pavhs) {
                // adjusted hsync rise: distance in native pixels from the last native rise (modulo the line)
                long d = pix - nat_hs; if (d < 0) d += 424; shifts.push_back(d % 424);
                ce_lines++; ce_count = 0;
            }
            pavhs = t->av_hs;
            if (t->av_vs && !pavs) { long d = line - nat_vs; vshifts.push_back(d); }
            pavs = t->av_vs;
            ce_count++;
        }
    }
    R r; r.hs_period = hs_p; r.vs_period = vs_p;
    long sh = shifts.empty() ? -1 : shifts.back(); r.hs_shift_px = sh;
    r.vs_shift_lines = vshifts.empty() ? -99 : vshifts.back();
    r.av_ce_per_line = 0; r.hb_width = 0;
    return r;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    t = new Vtb_crt_top;
    struct S { int on, hs, hp, vs; const char* name; } sets[] = {
        {0, 0, 0, 0, "off"}, {1, 0, 0, 0, "on, all 0"}, {1, 0, 1, 0, "H-Pos +6"}, {1, 0, 8, 0, "H-Pos -48 (clamped)"}, {1, 0, 0, 3, "V-Shift +3"}, {1, 0, 0, 60, "V-Shift -4"}, {1, 0, 0, 20, "V-Shift +20"}, {1, 0, 0, 31, "V-Shift +31"}, {1, 0, 0, 48, "V-Shift -16"}, {1, 0, 0, 32, "V-Shift -32"},
        {1, 5, 0, 0, "H-Size +5"}, {1, 11, 0, 0, "H-Size -12"}, {1, 10, 7, 7, "H-Size +10, H-Pos +42, V +7"},
    };
    for (auto& s : sets) {
        R r = run(s.on, s.hs, s.hp, s.vs);
        // the native line is 424 pixels, 262 lines
        printf("%-30s native hsync period %ld px, vsync period %ld lines | adjusted hsync is %ld px after the native one, vsync %ld lines after\n",
               s.name, r.hs_period, r.vs_period, r.hs_shift_px, r.vs_shift_lines);
    }
    delete t;
    return 0;
}
