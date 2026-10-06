// Whole-machine bench driver.
//   tb_system <game.rom> <frames> <out-prefix> [+load=rtl] [+coin=<frame>] [+start=<frame>] [+every=N] [+state=f1,f2,...]
// Writes <out>.fNNN.ppm (every N-th frame after the first), <out>.wav, and a status line a frame.
//   +load=rtl  push the image through the RTL loader instead of preloading the SDRAM
//   +state=..  at those frames dump the machine's video state (same file names as tools/lua/dump.lua) for tools/taitol_ref.py
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <set>
#include "Vtb_system_top.h"
#include "Vtb_system_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"

static std::vector<uint8_t> load_file(const char* p) {
    std::vector<uint8_t> v;
    FILE* f = fopen(p, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    return v;
}

static void write_ppm(const char* path, const uint8_t* rgb, int w, int h) {
    FILE* f = fopen(path, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb, 1, (size_t)w * h * 3, f);
    fclose(f);
}

static const long IMAGE_END = 0x3A0830;

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_system game.rom frames out-prefix [+load=rtl] [+coin=F] [+start=F] [+b1=F] [+every=N] [+state=f1,f2]\n"); return 2; }
    const char* rom = argv[1];
    int frames = atoi(argv[2]);
    std::string outp = argv[3];
    bool load_rtl = false;
    int coin_frame = -1, start_frame = -1, b1_frame = -1, every = 1, dswa = 0xFF, dswb = 0xFF;
    std::set<int> state_frames;
    std::vector<std::pair<int,int>> trk_x, trk_y;                 // +tbx=F:D,F:D  +tby=...  trackball counter steps at frame F
    const char* ymlog_path = nullptr;
    const char* trace_path = nullptr; long trace_max = 200000; int trace_from = 0, trace_to = 1 << 30;
    for (int i = 4; i < argc; i++) {
        if (!strncmp(argv[i], "+trace=", 7)) trace_path = argv[i] + 7;
        if (!strncmp(argv[i], "+ymlog=", 7)) ymlog_path = argv[i] + 7;                  // every write to the sound chip: frame, address bit, data
        if (!strncmp(argv[i], "+tracemax=", 10)) trace_max = atol(argv[i] + 10);
        if (!strncmp(argv[i], "+tracefrom=", 11)) trace_from = atoi(argv[i] + 11);       // only log while trace_from <= frame < trace_to
        if (!strncmp(argv[i], "+traceto=", 9)) trace_to = atoi(argv[i] + 9);
        if (!strcmp(argv[i], "+load=rtl")) load_rtl = true;
        if (!strncmp(argv[i], "+coin=", 6)) coin_frame = atoi(argv[i] + 6);
        if (!strncmp(argv[i], "+start=", 7)) start_frame = atoi(argv[i] + 7);
        if (!strncmp(argv[i], "+b1=", 4)) b1_frame = atoi(argv[i] + 4);
        if (!strncmp(argv[i], "+every=", 7)) every = atoi(argv[i] + 7);
        if (!strncmp(argv[i], "+dswa=", 6)) dswa = strtol(argv[i] + 6, nullptr, 16);
        if (!strncmp(argv[i], "+dswb=", 6)) dswb = strtol(argv[i] + 6, nullptr, 16);
        if (!strncmp(argv[i], "+tbx=", 5) || !strncmp(argv[i], "+tby=", 5)) {
            auto& v = argv[i][3] == 'x' ? trk_x : trk_y;
            char* s = strdup(argv[i] + 5);
            for (char* t = strtok(s, ","); t; t = strtok(nullptr, ",")) { int f, d; if (sscanf(t, "%d:%d", &f, &d) == 2) v.push_back({f, d}); }
        }
        if (!strncmp(argv[i], "+state=", 7)) {
            char* s = strdup(argv[i] + 7);
            for (char* t = strtok(s, ","); t; t = strtok(nullptr, ",")) state_frames.insert(atoi(t));
        }
    }
    auto img = load_file(rom);
    Vtb_system_top* t = new Vtb_system_top;
    svSetScope(svGetScopeFromName("TOP.tb_system_top"));

    t->clk = 0; t->clk_vid = 0; t->clk_ym = 0;
    tb_set_ctl(1, 1, 1);                     // rst, vid_rst, init
    tb_set_in(dswa, dswb, 0);
    tb_set_dl(0, 0, 0);

    // two unrelated clocks: 96 MHz (half period 5208.333 ps) and 26.66112 MHz (half period 18754.2 ps)
    const double hs = 1e6 / 96.0 / 2.0;
    const double hv = 1e6 / 26.66112 / 2.0;
    double ts = hs, tv = hv;
    uint64_t nsys = 0;
    auto step = [&]() {
        // clk_ym: 48 MHz, rising with every second rising edge of clk (the PLL's third output, in phase)
        if (ts <= tv) { t->clk = !t->clk; ts += hs; if (t->clk) { nsys++; t->clk_ym = nsys & 1; } } else { t->clk_vid = !t->clk_vid; tv += hv; }
        t->eval();
    };
    auto run_sys_cycles = [&](int n) { uint64_t e = nsys + n; while (nsys < e) step(); };

    // reset the controller
    run_sys_cycles(200);
    tb_set_ctl(1, 1, 0);
    while (!t->mem_ready) step();
    run_sys_cycles(100);

    long words = IMAGE_END / 2;
    if ((long)img.size() < IMAGE_END) { fprintf(stderr, "image too small (%zu bytes)\n", img.size()); return 2; }
    if (!load_rtl) {
        for (long wa = 0; wa < words; wa++) tb_sdram_write((int)wa, img[2 * wa] | (img[2 * wa + 1] << 8));
        const uint8_t* cfg = img.data() + 0x3A0800;
        tb_cfg(cfg[0], cfg[1] | cfg[2] << 8, cfg[3] | cfg[4] << 8 | cfg[5] << 16, cfg[6] | cfg[7] << 8 | cfg[8] << 16, cfg[9], cfg[10]);
        for (int i = 0; i < 24; i++) tb_cfg_in(i, cfg[16 + i]);
        for (int i = 0; i < 3; i++) tb_cfg_in(24 + i, cfg[40 + i]);
        for (int i = 0; i < 0x800; i++) tb_mcu_rom(i, img[0x3A0000 + i]);
        for (int i = 0; i < 0x10000; i++) tb_sub_rom(i, img[0x280000 + i]);
        fprintf(stderr, "image preloaded (%zu bytes)\n", img.size());
    } else {
        size_t n = IMAGE_END;
        for (size_t i = 0; i < n; ) {
            if (!t->dl_wait) { tb_set_dl(1, (int)i, img[i]); i++; }
            else tb_set_dl(0, 0, 0);
            run_sys_cycles(1);
            tb_set_dl(0, 0, 0);
            run_sys_cycles(2);
        }
        while (t->dl_busy) run_sys_cycles(1);
        run_sys_cycles(100);
        long bad = 0;
        for (long wa = 0; wa < words; wa++) {
            uint16_t w = img[2 * wa] | (img[2 * wa + 1] << 8);
            if ((uint16_t)tb_sdram_read((int)wa) != w) { if (bad < 10) fprintf(stderr, "mismatch at word %lx: %04x vs %04x\n", wa, (uint16_t)tb_sdram_read((int)wa), w); bad++; }
        }
        fprintf(stderr, "image loaded through the RTL loader; loader check: %ld of %ld words differ\n", bad, words);
    }

    tb_set_ctl(0, 0, 0);
    run_sys_cycles(10);

    std::vector<uint8_t> fb(320 * 224 * 3, 0);
    std::vector<int16_t> audio;
    int col = 0, row = 0, nframe = 0, saved = 0;
    bool prev_vb = true, vis_in_row = false, pvid = t->clk_vid, pclk = t->clk;
    long irq = 0, ovr = 0, ymw = 0, snd_nz = 0, ovrb[4] = {0, 0, 0, 0}; unsigned povb = 0;
    bool pirq = false, pov = false, pym = false, pw = false, pm1 = false, prd = false, psv = false;
    FILE* tf = trace_path ? fopen(trace_path, "w") : nullptr;
    FILE* yf = ymlog_path ? fopen(ymlog_path, "w") : nullptr;
    const char* scrlog_path = nullptr; FILE* sf = nullptr; int ps[8] = {-1, -1, -1, -1, -1, -1, -1, -1};
    for (int i = 4; i < argc; i++) if (!strncmp(argv[i], "+scrlog=", 8)) scrlog_path = argv[i] + 8;     // log every change of a scroll register with the raster line it lands on
    if (scrlog_path) sf = fopen(scrlog_path, "w");
    long busy_run[4] = {0, 0, 0, 0}, busy_max[4] = {0, 0, 0, 0}; long busy_hist[4][8] = {};
    bool ymparts = false; std::vector<int> psg_v, fm_v;
    for (int i = 4; i < argc; i++) if (!strcmp(argv[i], "+ymparts")) ymparts = true;      // report the SSG and FM sections' levels per half second
    long ntrace = 0;
    auto write_wav = [&]() {
        if (audio.empty()) return;
        FILE* f = fopen((outp + ".wav").c_str(), "wb");
        uint32_t n = audio.size() * 2, rate = 46286, br = rate * 2;      // 3.33264 MHz / 72: the YM2203 core's (jt03) sample rate
        uint16_t one = 1, bits = 16, ba = 2, fmt = 1; uint32_t sixteen = 16, riff = 36 + n;
        fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&sixteen, 4, 1, f);
        fwrite(&fmt, 2, 1, f); fwrite(&one, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f); fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f);
        fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(audio.data(), 2, audio.size(), f);
        fclose(f);
    };
    auto dump_state = [&](int f) {
        char p[512];
        auto wr = [&](const char* ext, const std::vector<uint8_t>& d) {
            snprintf(p, sizeof p, "%s.f%05d.%s.bin", outp.c_str(), f, ext);
            FILE* fp = fopen(p, "wb"); fwrite(d.data(), 1, d.size(), fp); fclose(fp);
        };
        std::vector<uint8_t> v(65536), pal(512), vr(256, 0), sp(1024);
        for (int i = 0; i < 65536; i++) v[i] = tb_vram(i);
        for (int i = 0; i < 512; i++) pal[i] = tb_pal(i);
        for (int i = 0; i < 8; i++) vr[i] = tb_vreg(i);
        for (int e = 0; e < 128; e++) for (int b = 0; b < 8; b++) sp[e * 8 + b] = tb_sprbuf(e, b);
        wr("vram", v); wr("pal", pal); wr("vregs", vr); wr("spr_prev", sp);
        if ((vr[4] & 7) == 7) { std::vector<uint8_t> bm(131072); for (int i = 0; i < 131072; i++) bm[i] = tb_bitmap(i); wr("bitmap", bm); }      // the 8 bit bitmap mode
        std::vector<uint8_t> cur(v.begin() + 0xB000, v.begin() + 0xB400); wr("spr_cur", cur);
    };

    uint64_t guard = (uint64_t)(frames + 4) * 2400000ULL;      // clk_sys cycles
    while (nframe < frames + 1 && nsys < guard) {
        {   // scripted coin and start, as signals (15 coin 1, 17 start 1), whatever the game's port layout
            static uint32_t last_sig = 0xFFFFFFFF;
            uint32_t sg = 0;
            if (coin_frame >= 0 && nframe >= coin_frame && nframe < coin_frame + 4) sg |= 1u << 15;
            if (start_frame >= 0 && nframe >= start_frame && nframe < start_frame + 4) sg |= 1u << 17;
            if (b1_frame >= 0 && nframe >= b1_frame && nframe < b1_frame + 4) sg |= 1u << 5;          // player 1 button 1
            if (sg != last_sig) { tb_set_in(dswa, dswb, sg); last_sig = sg; }
            // trackball steps: one strobe of a few clocks at the first clock of the frame
            static int last_trk_frame = -1; static uint64_t trk_off = 0;
            if (nframe != last_trk_frame) {
                last_trk_frame = nframe;
                int ax = 0, dx = 0, ay = 0, dy = 0;
                for (auto& e : trk_x) if (e.first == nframe) { ax = 1; dx = e.second; }
                for (auto& e : trk_y) if (e.first == nframe) { ay = 1; dy = e.second; }
                if (ax || ay) { tb_trk(ax, dx, ay, dy); trk_off = nsys + 4; }
            }
            if (trk_off && nsys >= trk_off) { tb_trk(0, 0, 0, 0); trk_off = 0; }
        }
        step();
        if (t->clk && !pclk) {
            if (t->dbg_irq && !pirq) irq++;        pirq = t->dbg_irq;
            if (t->dbg_ovr && !pov) ovr++;         pov = t->dbg_ovr;
            { unsigned ob = t->dbg_ovr_bits; for (int i = 0; i < 4; i++) if (((ob >> i) & 1) && !((povb >> i) & 1)) ovrb[i]++; povb = ob; }
            if (sf && (nsys & 15) == 0) {
                int v[8]; for (int k = 0; k < 8; k++) v[k] = tb_scroll(k);
                for (int k = 0; k < 4; k++) if (v[k] != ps[k] && ps[k] >= 0) fprintf(sf, "%d %d reg%d %d -> %d\n", nframe, v[4], k, ps[k], v[k]);
                if (v[5] != ps[5] && ps[5] >= 0) fprintf(sf, "%d %d vreg4 %02x -> %02x\n", nframe, v[4], ps[5], v[5]);
                if (v[6] != ps[6] && ps[6] >= 0) fprintf(sf, "%d %d tbank %08x -> %08x\n", nframe, v[4], (unsigned)ps[6], (unsigned)v[6]);
                if (v[7] != ps[7] && ps[7] >= 0) fprintf(sf, "%d %d irq_en %02x -> %02x\n", nframe, v[4], ps[7], v[7]);
                for (int k = 0; k < 8; k++) ps[k] = v[k];
            }
            for (int k = 0; k < 4; k++) {                      // how long each renderer is busy per line (clk_sys cycles)
                if ((t->dbg_busy >> k) & 1) busy_run[k]++;
                else if (busy_run[k]) { if (busy_run[k] > busy_max[k]) busy_max[k] = busy_run[k]; busy_hist[k][busy_run[k] >= 6000 ? 7 : busy_run[k] / 1000]++; busy_run[k] = 0; }
            }
            if (t->dbg_ym_wr && !pym) { ymw++; if (yf) fprintf(yf, "%d %d %02x\n", nframe, (int)t->dbg_ym_a0 | ((int)t->dbg_ym_a1 << 1), (unsigned)t->dbg_ym_d); }
            pym = t->dbg_ym_wr;
            if (t->snd_valid && !psv) { audio.push_back(t->snd_l); if (t->snd_l) snd_nz++; if (ymparts) { psg_v.push_back(tb_ym_psg(0)); fm_v.push_back(tb_ym_fm(0)); } }
            psv = t->snd_valid;
            if (tf && ntrace < trace_max && nframe >= trace_from && nframe < trace_to) {
                if (t->cpu_wr && !pw)  { fprintf(tf, "W %04x %02x  (frame %d)\n", (unsigned)t->cpu_a, (unsigned)t->cpu_dout, nframe); ntrace++; }
                if (t->cpu_m1 && !pm1) { fprintf(tf, "F %04x\n", (unsigned)t->cpu_a); ntrace++; }
                if (t->cpu_rd && !prd && !t->cpu_m1) { fprintf(tf, "R %04x %02x\n", (unsigned)t->cpu_a, (unsigned)t->cpu_di); ntrace++; }
            }
            pw = t->cpu_wr; pm1 = t->cpu_m1; prd = t->cpu_rd;
        }
        pclk = t->clk;
        if (!t->clk_vid && pvid) {
            if (t->ce_pix) {
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
                if (vb && !prev_vb) {                                  // a frame has been drawn
                    if (nframe > 0 && row >= 224 && (nframe % every) == 0) {
                        char p[512]; snprintf(p, sizeof p, "%s.f%03d.ppm", outp.c_str(), nframe);
                        write_ppm(p, fb.data(), 320, 224); saved++;
                    }
                    if (state_frames.count(nframe)) dump_state(nframe);
                    if (nframe % 20 == 0 || nframe < 5)
                        fprintf(stderr, "frame %d: rows %d, irqs %ld, line overruns %ld [bg0 %ld bg1 %ld tx %ld spr %ld], YM writes %ld, sound samples %zu (%ld non-zero), CPU @%04x\n",
                                nframe, row, irq, ovr, ovrb[0], ovrb[1], ovrb[2], ovrb[3], ymw, audio.size(), snd_nz, (unsigned)t->cpu_a);
                    nframe++;
                    if (nframe % 30 == 0) write_wav();
                    row = 0; col = 0;
                }
                if (vb) { row = 0; col = 0; vis_in_row = false; }
                prev_vb = vb;
            }
        }
        pvid = t->clk_vid;
    }
    write_wav();
    if (tf) fclose(tf);
    if (yf) fclose(yf);
    if (sf) fclose(sf);
    fprintf(stderr, "ADPCM-A read: the longest wait for the cache line %d machine clocks (the chip allows 144)\n", (int)t->dbg_pcm_max);
    { const char* nm[4] = {"bg0", "bg1", "text", "sprites"}; fprintf(stderr, "busiest line, clk_sys cycles of a ~6100 cycle line:"); for (int k = 0; k < 4; k++) fprintf(stderr, " %s %ld", nm[k], busy_max[k]); fprintf(stderr, "\n"); }
    if (ymparts) for (size_t w = 0; w + 23143 <= psg_v.size(); w += 23143) {
        double ps = 0, pm = 0, fs = 0, fmn = 0; int pmx = 0, fmx = 0;
        for (size_t i = w; i < w + 23143; i++) { ps += psg_v[i]; pm += (double)psg_v[i] * psg_v[i]; fs += fm_v[i]; fmn += (double)fm_v[i] * fm_v[i]; if (psg_v[i] > pmx) pmx = psg_v[i]; if (abs(fm_v[i]) > fmx) fmx = abs(fm_v[i]); }
        fprintf(stderr, "t=%.1fs  psg mean %.0f max %d rms %.0f | fm mean %.0f max %d rms %.0f\n", w / 46286.0, ps / 23143, pmx, sqrt(pm / 23143), fs / 23143, fmx, sqrt(fmn / 23143));
    }
    fprintf(stderr, "%d frames saved, %zu audio samples (%ld non-zero)\n", saved, audio.size(), snd_nz);
    delete t;
    return 0;
}
