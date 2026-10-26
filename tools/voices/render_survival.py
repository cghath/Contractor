"""Renders Contractor: Fallen's voiced lines (data/survival_lines.json) with a configurable TTS
engine into assets/voices/survival/<voice set>/<voice key>.wav (VoiceLines in the game).

usage (from the repo root):
  python -I tools/voices/render_survival.py --dry-run            list what it would render, write the manifest
  python -I tools/voices/render_survival.py                       render the missing clips with the config's engine
  python -I tools/voices/render_survival.py --engine kokoro --gpu render with Kokoro on the GPU
options:
  --config PATH     the config (default tools/voices/survival_tts.json)
  --engine NAME     piper | kokoro | xtts (default: the config's "engine")
  --gpu / --cpu     override the config's "gpu" flag (kokoro: onnxruntime-gpu; xtts: CUDA)
  --only TOPIC      just this topic's lines (repeatable)
  --voices A,B      just these voice sets
  --force           render clips that already exist again (a new engine replacing the old clips)
  --manifest PATH   where the manifest goes (default tools/voices/survival_manifest.json)

Which voices say a line: every voice set in the config whose sex and age band fit the line's
"speaker" ("any" fits all); a radio line (speaker kind "radio") only in the radio sets, and the
radio sets say only radio lines. A line with {first} or {name} in it is skipped unless it has a
"voice_text"; other fills are voiced with the config's stand-in words ("fills").

Engines (imported only when rendering, never for --dry-run):
  piper   the repo's existing pipeline (gen_callouts.py): piper.exe + an .onnx model, a speaker id
  kokoro  Kokoro-82M (pip install kokoro-onnx soundfile; the model and voices files from its release)
  xtts    Coqui XTTS-v2 (pip install TTS; ~2 GB model, wants a GPU; a 6-10 s reference wav per voice)
A clip already on disk is kept unless --force, so a run after new lines renders just those.
"""
import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINES = ROOT / "data" / "survival_lines.json"
NAME_FILLS = ("{first}", "{name}")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def spoken(line, fills):
    """What a line says aloud, or None (a name in it and no voice_text)."""
    if "voice_text" in line:
        return line["voice_text"]
    text = line.get("text", "")
    if any(f in text for f in NAME_FILLS):
        return None
    for k, v in fills.items():
        text = text.replace(k, v)
    return text


def fits(speaker, vset):
    radio_line = speaker.get("kind") == "radio"
    radio_set = vset.get("kind") == "radio"
    if radio_line != radio_set:
        return False
    for key in ("sex", "age"):
        want = speaker.get(key, "any")
        if want not in ("any", "", None) and want != vset.get(key):
            return False
    return True


def plan(cfg, only=None, voices=None, force=False):
    """Every clip to render: [{"voice", "key", "topic", "text", "path", "exists", "skip"}]."""
    out_dir = ROOT / cfg.get("out_dir", "assets/voices/survival")
    fills = cfg.get("fills", {})
    items = []
    topics = load_json(LINES)["topics"]
    for topic, lines in topics.items():
        if only and topic not in only:
            continue
        for i, line in enumerate(lines):
            key = line.get("voice") or "%s_%02d" % (topic, i + 1)
            text = spoken(line, fills)
            speaker = line.get("speaker", {})
            for name, vset in cfg["voices"].items():
                if voices and name not in voices:
                    continue
                if not fits(speaker, vset):
                    continue
                path = out_dir / name / ("%s.%s" % (key, cfg.get("format", "wav")))
                exists = path.exists()
                items.append({"voice": name, "key": key, "topic": topic, "text": text, "path": path.relative_to(ROOT).as_posix(),
                              "exists": exists, "skip": "name" if text is None else ("exists" if exists and not force else "")})
    return items


# --- Engines ----------------------------------------------------------------------------------

class Piper:
    def __init__(self, cfg, gpu):
        e = cfg["engines"]["piper"]
        self.exe, self.model = e["exe"], e["model"]
        self.length_scale = str(e.get("length_scale", 1.0))
        self.gpu = gpu

    def render(self, text, vset, path):
        args = [self.exe, "--model", self.model, "--output_file", str(path), "--length_scale", self.length_scale]
        speaker = vset.get("piper", {}).get("speaker")
        if speaker is not None:
            args += ["--speaker", str(speaker)]
        if self.gpu:
            args.append("--cuda")
        subprocess.run(args, input=text.encode("utf-8"), capture_output=True, check=True)


class Kokoro:
    def __init__(self, cfg, gpu):
        e = cfg["engines"]["kokoro"]
        if gpu:
            import os
            os.environ.setdefault("ONNX_PROVIDER", "CUDAExecutionProvider")
        from kokoro_onnx import Kokoro as K  # pip install kokoro-onnx
        self.k = K(e["model"], e["voices_file"])
        self.lang, self.speed = e.get("lang", "en-us"), float(e.get("speed", 1.0))
        self.rate = int(cfg.get("sample_rate", 22050))

    def render(self, text, vset, path):
        samples, rate = self.k.create(text, voice=vset["kokoro"], speed=self.speed, lang=self.lang)
        write_wav(path, samples, rate, self.rate)


class Xtts:
    def __init__(self, cfg, gpu):
        e = cfg["engines"]["xtts"]
        from TTS.api import TTS  # pip install TTS
        self.tts = TTS(model_path=e["model_dir"]) if e.get("model_dir") else TTS(e["model_name"])
        if gpu:
            self.tts = self.tts.to("cuda")
        self.lang = e.get("language", "en")
        self.refs = Path(e.get("refs_dir", "."))
        self.rate = int(cfg.get("sample_rate", 22050))

    def render(self, text, vset, path):
        ref = self.refs / vset["xtts"]["speaker_wav"]
        samples = self.tts.tts(text=text, speaker_wav=str(ref), language=self.lang)
        write_wav(path, samples, 24000, self.rate)


ENGINES = {"piper": Piper, "kokoro": Kokoro, "xtts": Xtts}


def write_wav(path, samples, rate, out_rate):
    """Float samples (-1..1) at `rate` to a 16-bit mono wav at `out_rate` (linear resample)."""
    samples = list(samples)
    if rate != out_rate and samples:
        n = int(len(samples) * out_rate / rate)
        step = rate / out_rate
        samples = [samples[min(int(i * step), len(samples) - 1)] for i in range(n)]
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(out_rate)
        w.writeframes(b"".join(int(max(-1.0, min(1.0, float(s))) * 32767).to_bytes(2, "little", signed=True) for s in samples))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(ROOT / "tools" / "voices" / "survival_tts.json"))
    ap.add_argument("--engine")
    ap.add_argument("--gpu", action="store_true")
    ap.add_argument("--cpu", action="store_true")
    ap.add_argument("--only", action="append")
    ap.add_argument("--voices")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--manifest", default=str(ROOT / "tools" / "voices" / "survival_manifest.json"))
    a = ap.parse_args(argv)
    cfg = load_json(a.config)
    engine = a.engine or cfg.get("engine", "piper")
    if engine not in ENGINES:
        sys.exit("no engine %r (piper, kokoro, xtts)" % engine)
    gpu = (cfg.get("gpu", False) or a.gpu) and not a.cpu
    items = plan(cfg, a.only, a.voices.split(",") if a.voices else None, a.force)
    todo = [it for it in items if not it["skip"]]
    manifest = {"engine": engine, "gpu": gpu, "clips": len(items), "to_render": len(todo),
                "skipped_names": sorted({"%s" % it["key"] for it in items if it["skip"] == "name"}),
                "items": [{k: it[k] for k in ("voice", "key", "text", "path", "skip")} for it in items]}
    with open(a.manifest, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")
    if a.dry_run:
        for it in todo:
            print("%s\t%s\t%s" % (it["path"], it["voice"], it["text"]))
        print("dry run: %d clips planned, %d to render with %s (gpu %s), %d lines left as subtitles (a name in them); manifest %s"
              % (len(items), len(todo), engine, gpu, len(manifest["skipped_names"]), a.manifest))
        return 0
    tts = ENGINES[engine](cfg, gpu)
    done = 0
    for it in todo:
        path = ROOT / it["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            tts.render(it["text"], cfg["voices"][it["voice"]], path)
            done += 1
        except Exception as e:  # one bad line shouldn't stop the batch
            print("FAILED %s: %s" % (it["path"], e), file=sys.stderr)
    print("rendered %d of %d with %s" % (done, len(todo), engine))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
