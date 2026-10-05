// Board-level bench driver: programs an SSG tone through the YM2203 like the Z80 would, reads the DIP/input mux, and
// reports whether sound comes out.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vtb_board_top.h"
#include "Vtb_board_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"

static Vtb_board_top* t;
static long samples = 0, nonzero = 0, maxabs = 0;
static bool psmp = false;
static void clk(int n) {
    for (int i = 0; i < n; i++) {
        t->clk = 0; t->eval(); t->clk = 1; t->eval();
        if (t->snd_sample && !psmp) { samples++; int v = t->snd; if (v) nonzero++; if (abs(v) > maxabs) maxabs = abs(v); }
        psmp = t->snd_sample;
    }
}
static void write(int a, int d) { tb_bus(0, 1, a, d); clk(14); tb_bus(0, 0, a, d); clk(30); }       // a Z80 write: 14 clocks of strobe
static int read(int a) { tb_bus(1, 0, a, 0); clk(14); int v = t->rd_data; tb_bus(0, 0, a, 0); clk(30); return v; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    t = new Vtb_board_top;
    svSetScope(svGetScopeFromName("TOP.tb_board_top"));
    tb_rst(1); clk(100); tb_rst(0); clk(20000);          // the YM core is held ~8000 clocks beyond the board's reset
    // the I/O mux: select register 0E / 0F, read the data port through A001 (select 0) and A003 (select 1)
    write(0xA000, 0x0E); int a0 = read(0xA001);         // port A, select 0: DSWA   (A5)
    write(0xA000, 0x0F); int b0 = read(0xA001);         // port B, select 0: IN0    (3C)
    write(0xA000, 0x0E); int a1 = read(0xA003);         // port A, select 1: DSWB   (5A)
    write(0xA000, 0x0F); int b1 = read(0xA003);         // port B, select 1: IN1    (C3)
    printf("I/O mux reads: DSWA %02x (A5)  IN0 %02x (3C)  DSWB %02x (5A)  IN1 %02x (C3)\n", a0, b0, a1, b1);
    // SSG channel A: tone period 0x0020, volume 15, tone enabled (mixer bit 0 low)
    write(0xA000, 0x07); write(0xA001, 0x38);
    write(0xA000, 0x08); write(0xA001, 0x0F);
    write(0xA000, 0x00); write(0xA001, 0x20);
    write(0xA000, 0x01); write(0xA001, 0x00);
    long s0 = samples, n0 = nonzero; clk(400000);
    printf("SSG tone: %ld samples, %ld non-zero, peak %ld\n", samples - s0, nonzero - n0, maxabs);
    delete t;
    return nonzero - n0 > 100 ? 0 : 1;
}
