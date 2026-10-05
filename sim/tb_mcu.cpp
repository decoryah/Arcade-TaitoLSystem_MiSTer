// MCU bench driver: tb_mcu <mcu.bin (2 KB)> [max_ms]
// Plays the Z80 side of Puzznic's boot handshake (write 00, write 43, read the answer) and logs every access the MCU makes
// to its port registers (addresses 0-9) so the sequence can be compared with MAME's trace of the real program.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include "Vtb_mcu_top.h"
#include "verilated.h"

static Vtb_mcu_top* t;
static uint64_t acc = 0, nclk = 0;
static int cens = 0;
static uint16_t last_a = 0xFFFF;
static int quiet = 0;
static void tick() {
    acc += 3579545; bool c = acc >= 96000000; if (c) acc -= 96000000;
    t->cen = c;
    t->clk = 0; t->eval(); t->clk = 1; t->eval();
    nclk++;
    if (c) {
        cens++;
        // log port writes, port A reads, and a read of port C only when it changed
        static int last_c = -1; bool show = false;
        if (t->dbg_a < 0x10 && !quiet) {
            if (t->dbg_wr) show = true;
            else if (t->dbg_a == 0) show = true;
            else if (t->dbg_a == 2) { int v = t->dbg_din; if (v != last_c && v != 0xA4) { show = true; last_c = v; } }
            else show = true;
        }
        if (show) {
            // one line per cen the core sits on a port register
            printf("%9.4f ms  cen %-7d  %s %04x  %s=%02x   hf=%d mf=%d hl=%02x ml=%02x pa=%02x\n", nclk / 96000.0, cens,
                   t->dbg_wr ? "WR" : "rd", t->dbg_a, t->dbg_wr ? "dout" : "din ", t->dbg_wr ? t->dbg_dout : t->dbg_din,
                   t->dbg_host_flag, t->dbg_mcu_flag, t->dbg_host_latch, t->dbg_mcu_latch, t->dbg_pa_pins);
        }
    }
}
static void run_ms(double ms) { long n = (long)(ms * 96000); for (long i = 0; i < n; i++) tick(); }
static void hwrite(int d) { t->host_wr = 1; t->host_wdata = d; for (int i = 0; i < 14; i++) tick(); t->host_wr = 0; for (int i = 0; i < 30; i++) tick(); printf("--- host write %02x\n", d); }
static int hread() { t->host_rd = 1; for (int i = 0; i < 14; i++) tick(); int v = t->host_rdata; t->host_rd = 0; for (int i = 0; i < 30; i++) tick(); printf("--- host read -> %02x\n", v); return v; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    t = new Vtb_mcu_top;
    FILE* f = fopen(argv[1], "rb"); if (!f) { perror("rom"); return 2; }
    std::vector<uint8_t> rom(2048); size_t got = fread(rom.data(), 1, 2048, f); fclose(f); (void)got;
    t->rst = 1; t->host_wr = 0; t->host_rd = 0; t->rom_we = 0;
    for (int i = 0; i < 2048; i++) { t->rom_we = 1; t->rom_waddr = i; t->rom_wdata = rom[i]; tick(); }
    t->rom_we = 0;
    for (int i = 0; i < 200; i++) tick();
    t->rst = 0;
    quiet = 1; run_ms(2.5); quiet = 0;       // the startup RAM clear is long
    printf("=== host protocol starts\n");
    run_ms(0.2);
    hread();                                // the Z80's first LD A,(B800)
    run_ms(2.2);
    hwrite(0x00);
    run_ms(2.2);
    hwrite(0x43);
    run_ms(0.5);
    int v = hread();
    printf("=== answer %02x (expect 50)\n", v);
    run_ms(0.3);
    delete t;
    return v == 0x50 ? 0 : 1;
}
