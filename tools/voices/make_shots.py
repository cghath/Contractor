"""Cuts the CC0 Free Firearm Sound Library recordings into the game's shot sounds.

usage: python -I make_shots.py <library dir> <out dir>
Each slot: the near take -> shot_<family>.wav, the mid-distance take -> shot_<family>_far.wav.
Mono, 16-bit, from just before the shot, trimmed and faded, peak-normalised. "heavy" slots are
pitched down and driven harder (the M2 and DShK from the rifle recordings, per the Captain).
"""
import math
import struct
import sys
import wave
from pathlib import Path

LIB = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

# family -> (folder, near file, far file, heavy)
SLOTS = {
    "ar": ("AR-15", "D_32P.wav", "D_24P.wav", False),
    "saw": ("AR-15", "D_32P.wav", "D_24P.wav", False),
    "akm": ("AK-47", "C_28P.wav", "C_31P.wav", False),
    "ak74": ("AK-47", "C_28P.wav", "C_31P.wav", False),
    "rpk": ("AK-47", "C_28P.wav", "C_31P.wav", False),
    "svd": ("Mosin Nagant", "M_21P.wav", "M_26P.wav", False),
    "pkm": ("Mosin Nagant", "M_21P.wav", "M_26P.wav", False),
    "nato762": ("1917", "B_24P.wav", "B_16P.wav", False),
    "m240": ("Arisaka", "E_25P.wav", "E_18P.wav", False),
    "pistol": ("Walther PPQ", "X_39P.wav", "X_31P.wav", False),
    "m2": ("1917", "B_24P.wav", "B_16P.wav", True),
    "dshk": ("Mosin Nagant", "M_21P.wav", "M_26P.wav", True),
    # Bolt-action snipers (2026-10-16): the Mosin-Nagant 91/30 reuses its own folder's near/far
    # take (the same one svd/pkm already use is fine for a placeholder; swap in a different take
    # from this folder once there's a reason to want it distinct from those two). The Springfield
    # Heatseeker is a modern 6.5 Creedmoor chassis rifle, not the WWII 1917 Enfield the folder
    # name suggests, but its heavy bolt-gun crack is the closest match the library has; replace
    # with a real Tikka take (the Captain says the library has one) when its filenames are known.
    "mosin": ("Mosin Nagant", "M_21P.wav", "M_26P.wav", False),
    "springfield_hs": ("1917", "B_24P.wav", "B_16P.wav", False),
}
NEAR_S, FAR_S = 1.6, 3.0
PRE_S = 0.008
HEAVY_PITCH = 0.8   # play at 80% speed: lower and longer
HEAVY_DRIVE = 1.8   # tanh drive: louder, more bang


def read(path):
    with wave.open(str(path), "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    total = len(raw) // width
    if width == 2:
        vals = struct.unpack("<%dh" % total, raw)
        scale = 32768.0
    elif width == 3:
        vals = [int.from_bytes(raw[i:i + 3], "little", signed=True) for i in range(0, len(raw), 3)]
        scale = 8388608.0
    elif width == 4:
        vals = struct.unpack("<%di" % total, raw)
        scale = 2147483648.0
    else:
        raise ValueError("unsupported width %d" % width)
    mono = [sum(vals[i:i + ch]) / (ch * scale) for i in range(0, total, ch)]
    return mono, rate


def onset(x):
    peak = max(abs(v) for v in x) or 1.0
    for i, v in enumerate(x):
        if abs(v) > 0.25 * peak:
            return i
    return 0


def resample(x, factor):
    """Slower by `factor` (<1: lower pitch, longer), linear interpolation."""
    n = int(len(x) / factor)
    out = []
    for i in range(n):
        p = i * factor
        j = int(p)
        f = p - j
        a = x[j] if j < len(x) else 0.0
        b = x[j + 1] if j + 1 < len(x) else 0.0
        out.append(a + (b - a) * f)
    return out


def shape(x, rate, seconds, heavy):
    start = max(onset(x) - int(PRE_S * rate), 0)
    x = x[start:]
    if heavy:
        x = resample(x[: int(seconds * HEAVY_PITCH * rate) + 2], HEAVY_PITCH)
    x = x[: int(seconds * rate)]
    n = len(x)
    fade_from = int(n * 0.55)
    for i in range(fade_from, n):
        t = (i - fade_from) / max(n - fade_from, 1)
        x[i] *= (1.0 - t) ** 2
    if heavy:
        x = [math.tanh(v * HEAVY_DRIVE * 3.0) / math.tanh(HEAVY_DRIVE * 3.0) for v in x]
    peak = max(abs(v) for v in x) or 1.0
    gain = 0.89 / peak  # -1 dBFS
    return [v * gain for v in x]


def write(path, x, rate):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(x), *[max(-32767, min(32767, int(v * 32767))) for v in x]))


def files_in(folder):
    return sorted(p for p in (LIB / folder).iterdir() if p.suffix.lower() == ".wav")


for family, (folder, near, far, heavy) in SLOTS.items():
    found = files_in(folder)
    if near is None:  # by the master sheet's order: the later take is near, the earlier mid
        near, far = found[-1].name, found[0].name
    for name, suffix, seconds in ((near, "", NEAR_S), (far, "_far", FAR_S)):
        x, rate = read(LIB / folder / name)
        y = shape(x, rate, seconds, heavy)
        out = OUT / ("shot_%s%s.wav" % (family, suffix))
        write(out, y, rate)
        print("%-24s <- %s/%s (%d Hz, %.2f s%s)" % (out.name, folder, name, rate, len(y) / rate, ", heavy" if heavy else ""))
