"""Generates one line per LibriTTS-R speaker with Piper and picks low (male) voices by pitch.

usage: python -I pick_voices.py <piper.exe> <model.onnx> <work dir> <how many speakers to try> <how many to keep>
"""
import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

PIPER, MODEL, WORK = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
TRY, KEEP = int(sys.argv[4]), int(sys.argv[5])
LO_HZ, HI_HZ = (float(sys.argv[6]), float(sys.argv[7])) if len(sys.argv) > 7 else (75.0, 150.0)
WORK.mkdir(parents=True, exist_ok=True)
LINE = "Contact front! Moving up, cover me."


def f0(path):
    with wave.open(str(path), "rb") as w:
        rate, n = w.getframerate(), w.getnframes()
        x = struct.unpack("<%dh" % n, w.readframes(n))
    # voiced frames by energy, pitch by autocorrelation in 70-300 Hz
    win = int(rate * 0.04)
    lo, hi = int(rate / 300), int(rate / 70)
    pitches = []
    for start in range(0, len(x) - win - hi, win):
        seg = x[start:start + win + hi]
        energy = sum(v * v for v in seg[:win]) / win
        if energy < 4e5:
            continue
        best, best_lag = 0.0, 0
        for lag in range(lo, hi, 2):
            c = sum(seg[i] * seg[i + lag] for i in range(0, win, 3))
            if c > best:
                best, best_lag = c, lag
        if best_lag:
            pitches.append(rate / best_lag)
    pitches.sort()
    return pitches[len(pitches) // 2] if pitches else 0.0


results = []
for spk in range(TRY):
    out = WORK / ("spk_%03d.wav" % spk)
    if not out.exists():
        subprocess.run([str(PIPER), "-m", str(MODEL), "--speaker", str(spk), "-f", str(out)],
                       input=LINE.encode(), capture_output=True, check=False)
    if out.exists():
        results.append((f0(out), spk))
male = sorted(r for r in results if LO_HZ < r[0] < HI_HZ)
print("tried %d, male-range %d" % (len(results), len(male)))
# spread the picks across the male pitch range so they sound different
picks = [male[round(i * (len(male) - 1) / max(KEEP - 1, 1))] for i in range(KEEP)] if len(male) >= KEEP else male
for hz, spk in picks:
    print("speaker %d  %.0f Hz" % (spk, hz))
