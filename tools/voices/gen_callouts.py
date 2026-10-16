"""Generates the squad's voiced callouts with Piper: audio/callouts/v<k>/<id>_<n>.wav per voice.

usage: python -I gen_callouts.py <piper.exe> <model.onnx> <out dir> <lang tag> <speaker ids, comma list>
lang tag picks the line set (en for now).
"""
import subprocess
import sys
from pathlib import Path

PIPER, MODEL, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
LANG = sys.argv[4]
SPEAKERS = [int(s) for s in sys.argv[5].split(",") if s != ""]
START = int(sys.argv[6]) if len(sys.argv) > 6 else 0  # first voice folder index

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

lines = LINES[LANG]
for k, spk in enumerate(SPEAKERS):
    folder = OUT / ("v%d" % (START + k))
    folder.mkdir(parents=True, exist_ok=True)
    for cid, variants in lines.items():
        for n, text in enumerate(variants, 1):
            out = folder / ("%s_%d.wav" % (cid, n))
            args = [str(PIPER), "-m", str(MODEL), "-f", str(out), "--length_scale", "0.85"]
            if spk >= 0:
                args += ["--speaker", str(spk)]
            subprocess.run(args, input=text.encode(), capture_output=True, check=False)
    print("voice v%d (speaker %d): %d files" % (START + k, spk, len(list(folder.glob("*.wav")))))
