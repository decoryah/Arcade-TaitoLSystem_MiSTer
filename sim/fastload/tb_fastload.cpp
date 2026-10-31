// Bench for target/mister/taitol_fastload.sv: an image in a DDR3 model (random wait states, 64-bit beats, bursts), the loader's clock
// (96 MHz) and the DDR3 port's clock (the video clock, 26.66 MHz) at their real ratio, random dl_wait from the loader; every byte the
// module hands over must be the image's byte at its address, in order, once, and `done` must come after the last one.
//   run.sh <image length>
#include "Vtaitol_fastload.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <deque>
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const uint32_t len = argc > 1 ? strtoul(argv[1], 0, 0) : 0x3A0830;
    const uint64_t BASE = 0x6400000;                         // beat address of byte 0x32000000
    std::vector<uint8_t> img(len + 64);
    srand(12345);
    for (auto& b : img) b = rand() & 0xFF;
    Vtaitol_fastload* t = new Vtaitol_fastload;
    // time in picoseconds: clk 96 MHz (10417 ps), clk_ddr 26.66112 MHz (37508 ps)
    const uint64_t P_SYS = 10417, P_VID = 37508;
    uint64_t now = 0, n_sys = 0, n_vid = 0;
    uint32_t next = 0, errors = 0; bool done = false; int busy_cnt = 0;
    std::deque<std::pair<uint64_t,int>> rq;                  // pending read bursts: beat address, beats left
    std::deque<uint64_t> outq;
    t->clk = 0; t->clk_ddr = 0; t->rst = 1; t->go = 0; t->cancel = 0; t->len = len; t->dl_wait = 0;
    t->DDRAM_BUSY = 0; t->DDRAM_DOUT_READY = 0; t->DDRAM_DOUT = 0;
    t->eval();
    uint64_t sys_cycles = 0, go_at = 200, done_cycle = 0;
    while (sys_cycles < 40000000ULL) {
        uint64_t ts = (n_sys + 1) * P_SYS / 2, tv = (n_vid + 1) * P_VID / 2;
        if (ts <= tv) {                                      // a half period of clk
            n_sys++; t->clk = !t->clk;
            if (t->clk) {                                    // rising edge: drive inputs set before it
                sys_cycles++;
                t->rst = sys_cycles < 20;
                t->go = (sys_cycles == go_at);
                t->eval();
                if (t->dl_we) {
                    uint32_t a = t->dl_addr;
                    if (a != next || t->dl_data != img[a]) { if (errors++ < 10) printf("byte %06x: got addr %06x data %02x, want %02x\n", next, a, t->dl_data, img[next]); }
                    next = a + 1;
                }
                if (t->done) { done = true; done_cycle = sys_cycles; }
                t->dl_wait = (rand() % 7) == 0;              // the loader's FIFO backing up now and then
                if (done && sys_cycles > done_cycle + 1000) break;
            } else t->eval();
        } else {                                             // a half period of clk_ddr
            n_vid++; t->clk_ddr = !t->clk_ddr;
            if (t->clk_ddr) {
                // the DDR3 model: a read request is taken on a clock where BUSY is low; data comes back a beat a clock after a delay
                if (t->DDRAM_RD && !t->DDRAM_BUSY) rq.push_back({t->DDRAM_ADDR, t->DDRAM_BURSTCNT});   // what the port sees at this edge
                t->eval();
                t->DDRAM_DOUT_READY = 0;
                if (!rq.empty() && (rand() % 3)) {
                    auto& r = rq.front();
                    uint64_t byte = (r.first - BASE) * 8;
                    uint64_t v = 0;
                    for (int k = 0; k < 8; k++) v |= (uint64_t)(byte + k < img.size() ? img[byte + k] : 0) << (8 * k);
                    t->DDRAM_DOUT = v; t->DDRAM_DOUT_READY = 1;
                    r.first++; if (--r.second == 0) rq.pop_front();
                }
                t->DDRAM_BUSY = (rand() % 4) == 0;
                if (t->own == 0 && !rq.empty()) { if (errors++ < 10) printf("own dropped with reads pending\n"); }
                t->eval();
            } else t->eval();
        }
    }
    printf("len %u: %u bytes handed over, %s, %u errors, done at %llu sys clocks (%.3f s)\n", len, next,
           done ? "done" : "NOT done", errors, (unsigned long long)done_cycle, done_cycle / 96e6);
    return (errors || !done || next != len) ? 1 : 0;
}
