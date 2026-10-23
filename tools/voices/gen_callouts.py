"""Generates the squad's voiced callouts with Piper: audio/callouts/v<k>/<id>_<n>.wav per voice.

usage: python -I gen_callouts.py <piper.exe> <model.onnx> <out dir> <lang tag> <speaker ids, comma list> [first voice index]
       python -I gen_callouts.py --list <callouts dir>   (the lines with no clip yet, per language)
lang tag picks the line set (en, ru, fa). A clip already on disk is kept (only missing ones are
rendered), so running it again after new lines are added renders just those.

2026-10-22 (claude/voice-economy): the context-aware barks and the voice orders' confirmations
(NEW_LINES below) have no clips yet: Piper isn't on the dev PC. The game shows them as subtitles
until their clips are in audio/callouts (Callouts.voiced_path falls back to the bare category, then
to silence). docs/voice.md lists the voices and speakers used for the first batch.
"""
import subprocess
import sys
from pathlib import Path

LINES = {
    "en": {
        "contact": ["Contact!", "Contact, contact!"],
        "reloading": ["Reloading!", "Changing mags!"],
        "frag_out": ["Frag out!", "Grenade out!"],
        "smoke_out": ["Smoke out!", "Popping smoke!"],
        "flash_out": ["Flashbang out!", "Flash out!"],
        "moving": ["Moving!", "Moving up!"],
        "covering": ["Covering!", "I got you covered!"],
        "no_shot": ["No shot!", "I've got no shot!"],
        "medic": ["Medic!", "Medic! I'm hit!"],
        "man_down": ["Man down!", "Man down, man down!"],
        "moving_to": ["Moving to him!", "I'm going to him!"],
        "treating": ["Treating him!", "Working on him!"],
        "need_medic": ["Need a medic here!", "Get a medic over here!"],
        "carrying": ["I've got him, carrying!", "Carrying him out!"],
        "clear": ["Clear!", "Room clear!"],
        "hit": ["Agh! I'm hit!", "Argh!"],
        "scream": ["Aaaaaagh!", "Aaaargh! God!"],
    },
    "ru": {
        "contact": ["Контакт!", "Противник!"],
        "reloading": ["Перезаряжаюсь!", "Меняю магазин!"],
        "frag_out": ["Граната!", "Бросаю гранату!"],
        "smoke_out": ["Дым!", "Ставлю дым!"],
        "flash_out": ["Светошумовая!", "Вспышка!"],
        "moving": ["Двигаюсь!", "Вперёд!"],
        "covering": ["Прикрываю!", "Прикрою!"],
        "no_shot": ["Не вижу цель!", "Нет выстрела!"],
        "medic": ["Санитар!", "Ранен! Санитар!"],
        "man_down": ["Трёхсотый!", "Наш ранен!"],
        "moving_to": ["Иду к нему!", "Бегу к нему!"],
        "treating": ["Перевязываю!", "Оказываю помощь!"],
        "need_medic": ["Нужен санитар!", "Санитара сюда!"],
        "carrying": ["Тащу его!", "Выношу его!"],
        "clear": ["Чисто!", "Помещение чисто!"],
        "hit": ["А-а! Ранен!", "Аргх!"],
        "scream": ["А-а-а-а!", "А-а-а! Чёрт!"],
    },
    "fa": {
        "contact": ["دشمن!", "تماس!"],
        "reloading": ["خشاب عوض می‌کنم!", "پر می‌کنم!"],
        "frag_out": ["نارنجک!", "نارنجک انداختم!"],
        "smoke_out": ["دود!", "دود می‌زنم!"],
        "flash_out": ["نارنجک صوتی!", "فلش!"],
        "moving": ["حرکت می‌کنم!", "جلو می‌رم!"],
        "covering": ["پوشش می‌دم!", "پوششت می‌دم!"],
        "no_shot": ["دید ندارم!", "شلیک ندارم!"],
        "medic": ["امدادگر!", "زخمی شدم! امدادگر!"],
        "man_down": ["یکی زخمی شد!", "افتاد!"],
        "moving_to": ["دارم میرم پیشش!", "میرم سراغش!"],
        "treating": ["دارم پانسمانش می‌کنم!", "دارم درمانش می‌کنم!"],
        "need_medic": ["امدادگر لازم داریم!", "امدادگر بیاد اینجا!"],
        "carrying": ["دارم می‌برمش!", "گرفتمش!"],
        "clear": ["پاکه!", "اتاق پاکه!"],
        "hit": ["آخ! خوردم!", "آه!"],
        "scream": ["آآآآآخ!", "آآآه! خدایا!"],
    },
}

# Context-aware template slots (Captain, 2026-10-16: "nothing insane" -- a bounded pass, not a
# full rewrite): each combo below is a discrete, fully pre-rendered line (not live TTS), so the
# game just picks the id that matches what it knows (direction, site type, weapon class) and
# falls back to the bare category (voiced_path in scripts/ui/callouts.gd) if a combo isn't
# rendered yet. English only: enemies' contact lines fall back to their plain "contact" line in
# ru/fa rather than doubling the translation work for a bounded pass.
CLOCK = ["twelve", "two", "three", "five", "six", "eight", "nine", "eleven"]
for _clock in CLOCK:
    LINES["en"]["contact_%s" % _clock] = ["Contact, %s o'clock!" % _clock]
    LINES["en"]["contact_%s_close" % _clock] = ["Contact, %s o'clock, close!" % _clock]

INTEL_SITES = {
    "hq": "the HQ",
    "qrf_base": "a QRF base",
    "aa": "an AA site",
    "outpost": "an outpost",
    "checkpoint": "a checkpoint",
}
for _site, _label in INTEL_SITES.items():
    LINES["en"]["intel_%s" % _site] = ["Got %s marked!" % _label]

AMMO_CLASSES = {"rifle": "rifle", "mg": "gun", "pistol": "pistol"}
for _cls, _label in AMMO_CLASSES.items():
    LINES["en"]["reloading_last_%s" % _cls] = ["Last mag for the %s!" % _label]

# Context-aware barks and order confirmations (2026-10-22, claude/voice-economy; scripts/ui/
# callouts.gd LINES, PRIORITY and VoiceCommands.ACKS). Enemies say the barks in their own tongue.
NEW_LINES = {
    "en": {
        "set": ["Set!", "I'm set!"],
        "grenade": ["Grenade!", "Grenade, get down!"],
        "out_of_ammo": ["I'm out! Need ammo!", "Out of ammo!"],
        "check_fire": ["Check fire! Check fire!", "Cease fire, friendlies!"],
        "enemy_down": ["Enemy down!", "Got him!"],
        "enemy_down_mg": ["Gunner down!"],
        "enemy_down_at": ["RPG's down!"],
        "enemy_down_sniper": ["Sniper down!"],
        "suppressed": ["I'm pinned!", "Pinned down!"],
        "ack_follow": ["On you."],
        "ack_move": ["Moving."],
        "ack_hold": ["Holding."],
        "ack_bound": ["Bounding."],
        "ack_cover": ["Taking cover."],
        "ack_fall_back": ["Falling back!"],
        "ack_garrison": ["Moving to garrison."],
        "ack_clear": ["Stacking up."],
        "ack_attack": ["Moving."],
        "ack_target": ["Target."],
        "ack_suppress": ["Suppressing!"],
        "ack_watch": ["Watching."],
        "ack_fire": ["Weapons free."],
        "ack_hold_fire": ["Holding fire."],
        "ack_mount": ["Mounting up."],
        "ack_dismount": ["Getting out."],
        "ack_smoke": ["Smoke, wilco."],
        "ack_frag": ["Frag, wilco."],
    },
    "ru": {
        "set": ["На месте!", "Готов, прикрываю!"],
        "grenade": ["Граната!", "Ложись, граната!"],
        "out_of_ammo": ["Патроны кончились!", "Пустой!"],
        "check_fire": ["Не стрелять, свои!", "Свои!"],
        "enemy_down": ["Готов!", "Минус один!"],
        "suppressed": ["Прижали!", "Голову не поднять!"],
    },
    "fa": {
        "set": ["مستقرم!", "آماده‌ام!"],
        "grenade": ["نارنجک!", "بخواب، نارنجک!"],
        "out_of_ammo": ["مهماتم تموم شد!", "فشنگ ندارم!"],
        "check_fire": ["نزنید، خودی!", "خودی!"],
        "enemy_down": ["زدمش!", "یکی افتاد!"],
        "suppressed": ["زیر آتشم!", "نمی‌تونم سر بلند کنم!"],
    },
}
for _lang, _lines in NEW_LINES.items():
    LINES[_lang].update(_lines)

# Where each language's voices live under audio/callouts (Callouts.voiced_path).
LANG_DIRS = {"en": ["v%d" % k for k in range(8)] + ["female/v%d" % k for k in range(4)], "ru": ["ru/v0", "ru/v1"], "fa": ["fa/v0"]}


def missing(root):
    """(lang, voice dir, id, n, text) for every line with no clip under `root` (audio/callouts)."""
    out = []
    for lang, dirs in LANG_DIRS.items():
        for d in dirs:
            for cid, variants in LINES[lang].items():
                for n, text in enumerate(variants, 1):
                    if not (Path(root) / d / ("%s_%d.wav" % (cid, n))).exists():
                        out.append((lang, d, cid, n, text))
    return out


if __name__ == "__main__":
    if sys.argv[1] == "--list":
        sys.stdout.reconfigure(encoding="utf-8")
        todo = missing(sys.argv[2])
        seen = set()
        for lang, d, cid, n, text in todo:
            if (lang, cid, n) not in seen:
                seen.add((lang, cid, n))
                print("%s\t%s_%d\t%s" % (lang, cid, n, text))
        print("%d clips missing (%d lines x their voices)" % (len(todo), len(seen)))
        sys.exit(0)
    PIPER, MODEL, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    LANG = sys.argv[4]
    SPEAKERS = [int(x) for x in sys.argv[5].split(",") if x != ""]
    START = int(sys.argv[6]) if len(sys.argv) > 6 else 0  # first voice folder index
    lines = LINES[LANG]
    for k, spk in enumerate(SPEAKERS):
        folder = OUT / ("v%d" % (START + k))
        folder.mkdir(parents=True, exist_ok=True)
        made = 0
        for cid, variants in lines.items():
            for n, text in enumerate(variants, 1):
                out = folder / ("%s_%d.wav" % (cid, n))
                if out.exists():
                    continue  # rendered before: only the new lines
                args = [str(PIPER), "-m", str(MODEL), "-f", str(out), "--length_scale", "0.85"]
                if spk >= 0:
                    args += ["--speaker", str(spk)]
                subprocess.run(args, input=text.encode(), capture_output=True, check=False)
                made += 1
        print("voice v%d (speaker %d): %d new, %d files" % (START + k, spk, made, len(list(folder.glob("*.wav")))))
