// Frozen-state video bench driver (tb_video_top): runs the raster and the renderers on the state the bench loaded,
// and writes frames to PPM.
//   tb_video <out-prefix> <frames> [+vram=.. +sprprev=.. +pal=.. +vregs=.. +gfx=.. +gfxn=..]
// Frames are counted after the image has been loaded; the first is a warm-up (the renderers draw a line ahead),
// the ones after it are written as <out>.fNNN.ppm.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vtb_video_top.h"
#include "verilated.h"

static void write_ppm(const char* path, const uint8_t* rgb, int w, int h) {
    FILE* f = fopen(path, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb, 1, (size_t)w * h * 3, f);
    fclose(f);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb_video out-prefix frames [+plusargs]\n"); return 2; }
    std::string outp = argv[1];
    int frames = atoi(argv[2]);
    Vtb_video_top* t = new Vtb_video_top;
    t->clk = 0; t->clk_vid = 0; t->rst = 1;

    // two unrelated clocks: 96 MHz (half period 5208.333 ps) and 26.66112 MHz (half period 18754.2 ps)
    const double hs = 1e6 / 96.0 / 2.0 * 1.0;                     // in fs-free units: ps * 1
    const double hv = 1e6 / 26.66112 / 2.0;
    double ts = 0, tv = 0;                                          // time of the next toggle
    ts = hs; tv = hv;
    auto step = [&]() {
        if (ts <= tv) { t->clk = !t->clk; ts += hs; } else { t->clk_vid = !t->clk_vid; tv += hv; }
        t->eval();
    };
    for (int i = 0; i < 400; i++) step();
    t->rst = 0;

    std::vector<uint8_t> fb(320 * 224 * 3, 0);
    int col = 0, row = 0, nframe = -1, saved = 0;
    bool prev_vb = true, prev_hb = true, vis_in_row = false, pvid = t->clk_vid;
    long ovr[4] = {0, 0, 0, 0}; bool po[4] = {false, false, false, false};
    long maxrun[4] = {0, 0, 0, 0}, run[4] = {0, 0, 0, 0};
    bool pclk = t->clk;
    bool loaded = false;
    uint64_t guard = 400000000ULL;
    uint64_t n = 0;
    while (saved < frames && n++ < guard) {
        step();
        if (t->clk && !pclk) {
            bool o[4] = {t->ovr_bg0, t->ovr_bg1, t->ovr_tx, t->ovr_spr};
            bool b[4] = {t->busy_bg0, t->busy_bg1, t->busy_tx, t->busy_spr};
            for (int i = 0; i < 4; i++) {
                if (o[i] && !po[i]) ovr[i]++;
                po[i] = o[i];
                run[i] = b[i] ? run[i] + 1 : 0; if (run[i] > maxrun[i]) maxrun[i] = run[i];
            }
        }
        pclk = t->clk;
        if (!t->clk_vid && pvid) {                                   // falling edge of the raster clock: sample
            if (t->ready && !loaded) { loaded = true; nframe = -1; prev_vb = true; fprintf(stderr, "image loaded\n"); }
            if (t->ce_pix && loaded) {
                bool hb = t->hblank, vb = t->vblank;
                if (!hb && !vb) {
                    if (col < 320 && row < 224) {
                        uint32_t c = t->rgb;
                        fb[(row * 320 + col) * 3 + 0] = (c >> 16) & 255;
                        fb[(row * 320 + col) * 3 + 1] = (c >> 8) & 255;
                        fb[(row * 320 + col) * 3 + 2] = c & 255;
                    }
                    col++; vis_in_row = true;
                }
                if (hb && vis_in_row) { row++; col = 0; vis_in_row = false; }
                if (vb && !prev_vb) {                                // a frame has been drawn
                    nframe++;
                    fprintf(stderr, "frame %d: rows %d, overruns bg0 %ld bg1 %ld tx %ld spr %ld, longest busy (clocks of ~4600/line): bg0 %ld bg1 %ld tx %ld spr %ld\n",
                            nframe, row, ovr[0], ovr[1], ovr[2], ovr[3], maxrun[0], maxrun[1], maxrun[2], maxrun[3]);
                    if (nframe >= 1 && row >= 224) {
                        char p[512]; snprintf(p, sizeof p, "%s.f%03d.ppm", outp.c_str(), nframe);
                        write_ppm(p, fb.data(), 320, 224); saved++;
                    }
                    for (int i = 0; i < 4; i++) maxrun[i] = 0;
                    row = 0; col = 0;
                }
                if (vb) { row = 0; col = 0; vis_in_row = false; }
                prev_hb = hb; prev_vb = vb;
            }
        }
        pvid = t->clk_vid;
    }
    fprintf(stderr, "%d frames saved\n", saved);
    delete t;
    return saved == frames ? 0 : 1;
}
