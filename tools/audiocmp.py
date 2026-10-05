#!/usr/bin/env python3
"""Compare two mono 16-bit WAVs (different rates are fine): RMS and the energy in log-spaced frequency bands per time
window, side by side, and the overall level ratio.  Pure Python (no numpy).

  python tools/audiocmp.py mame.wav rtl.wav [--win 0.5] [--from 5.0] [--to 10.0] [--rate-b 46287]
(--rate-a / --rate-b override a file's header rate: the RTL bench's WAV is labelled with a nominal rate)
"""
import cmath
import math
import struct
import sys
import wave

BANDS = [(60, 200), (200, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 8000), (8000, 12000)]
N = 4096          # FFT size at the common analysis rate
RATE = 24000      # common analysis rate (Nyquist 12 kHz)


def load(path):
    w = wave.open(path, 'rb')
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    d = struct.unpack('<%dh' % (n * ch), w.readframes(n))
    return list(d[::ch]), rate


def resample(x, rate, out_rate):
    if rate == out_rate:
        return x
    r = rate / out_rate
    n = int(len(x) / r)
    out = []
    for i in range(n):
        p = i * r
        j = int(p)
        f = p - j
        out.append(x[j] * (1 - f) + (x[j + 1] if j + 1 < len(x) else x[j]) * f)
    return out


def fft(a):
    n = len(a)
    if n == 1:
        return a
    e, o = fft(a[0::2]), fft(a[1::2])
    t = [cmath.exp(-2j * math.pi * k / n) * o[k] for k in range(n // 2)]
    return [e[k] + t[k] for k in range(n // 2)] + [e[k] - t[k] for k in range(n // 2)]


def bands(seg):
    seg = seg[:N] + [0.0] * (N - len(seg[:N]))
    win = [seg[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / N)) for i in range(N)]
    s = fft(win)
    out = []
    for lo, hi in BANDS:
        a, b = int(lo * N / RATE), int(hi * N / RATE)
        out.append(sum(abs(s[k]) ** 2 for k in range(a, b)) / N)
    return out


def rms(x):
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    win = float(argv[argv.index('--win') + 1]) if '--win' in argv else 0.5
    t0 = float(argv[argv.index('--from') + 1]) if '--from' in argv else 0.0
    t1 = float(argv[argv.index('--to') + 1]) if '--to' in argv else 1e9
    a, ra = load(argv[0])
    b, rb = load(argv[1])
    if '--rate-a' in argv:
        ra = int(argv[argv.index('--rate-a') + 1])
    if '--rate-b' in argv:
        rb = int(argv[argv.index('--rate-b') + 1])
    A, B = resample(a, ra, RATE), resample(b, rb, RATE)
    step = int(RATE * win)
    print('window %.2fs   %-9s %-9s %-6s   band energy ratio rtl/mame (dB): %s' % (
        win, 'rms mame', 'rms rtl', 'ratio', ' '.join('%5s' % ('%d-%d' % (lo, hi) if hi < 1000 else '%gk-%gk' % (lo / 1000, hi / 1000)) for lo, hi in BANDS)))
    tot_a = tot_b = 0.0
    for i in range(0, min(len(A), len(B)) - step + 1, step):
        t = i / RATE
        if t < t0 or t >= t1:
            continue
        sa, sb = A[i:i + step], B[i:i + step]
        ra_, rb_ = rms(sa), rms(sb)
        tot_a += ra_ * ra_
        tot_b += rb_ * rb_
        if ra_ < 1 and rb_ < 1:
            print('t=%5.2fs  silent in both' % t)
            continue
        ea, eb = bands(sa), bands(sb)
        db = ['%5.1f' % (10 * math.log10((y + 1e-9) / (x + 1e-9))) for x, y in zip(ea, eb)]
        print('t=%5.2fs   %9.1f %9.1f %6.2f   %s' % (t, ra_, rb_, rb_ / ra_ if ra_ else float('nan'), ' '.join(db)))
    if tot_a:
        print('overall level ratio rtl/mame: %.3f (%.1f dB)' % (math.sqrt(tot_b / tot_a), 10 * math.log10(tot_b / tot_a) if tot_b else float('-inf')))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
