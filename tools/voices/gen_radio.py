"""Renders RadioVoice's clips with Piper: audio/radio/v<k>/<word>.wav, one per word in
data/radio_voice.json ("words", plus the digits zero-nine), per voice.

usage: python -I gen_radio.py <piper.exe> <model.onnx> <repo root> <speaker ids, comma list>
One speaker id per voice (v0, v1, ...); data/radio_voice.json "voices" should match how many.
"""
import json
import subprocess
import sys
from pathlib import Path

PIPER, MODEL, ROOT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
SPEAKERS = [int(s) for s in sys.argv[4].split(",") if s != ""]
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
# How a word is spoken where its spelling would read wrong.
SAY = {"casevac": "cas evac", "sitrep": "sit rep", "were": "we're", "metres": "meters", "dustoff": "dust off",
       "nine": "niner", "a": "uh", "m": "meters", "d": "'d", "s": "'s", "t": "'t", "lz": "L Z", "hhour": "H hour"}

words = json.loads((ROOT / "data" / "radio_voice.json").read_text(encoding="utf-8"))["words"] + DIGITS
for k, speaker in enumerate(SPEAKERS):
    out = ROOT / "audio" / "radio" / f"v{k}"
    out.mkdir(parents=True, exist_ok=True)
    for w in words:
        path = out / f"{w}.wav"
        if path.exists():
            continue
        subprocess.run([str(PIPER), "--model", str(MODEL), "--speaker", str(speaker), "--output_file", str(path)],
                       input=SAY.get(w, w).encode("utf-8"), check=True)
        print(path)
