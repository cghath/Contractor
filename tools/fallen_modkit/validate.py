#!/usr/bin/env python3
"""Checks a Contractor: Fallen mod folder against the mod kit's schema (dry: no Godot).

    python3 tools/fallen_modkit/validate.py path/to/mods/my_mod     # one mod
    python3 tools/fallen_modkit/validate.py --shipped                # the game's own data files

The schema is data/fallen_mod_schema.json (the same one ModKit reads in game); docs/fallen_modding.md
explains every file. Exit 0 when it passes, 1 with the problems listed. Unknown fields are warnings.
"""
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCHEMA_PATH = os.path.join(ROOT, "data", "fallen_mod_schema.json")


def res_path(p):
    return os.path.join(ROOT, p[len("res://"):]) if p.startswith("res://") else p


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def type_ok(value, t):
    if t == "any":
        return True
    if t == "string":
        return isinstance(value, str)
    if t == "int":
        if isinstance(value, bool):
            return False
        return isinstance(value, int) or (isinstance(value, float) and value.is_integer())
    if t == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if t == "bool":
        return isinstance(value, bool)
    if t == "array":
        return isinstance(value, list)
    if t == "dict":
        return isinstance(value, dict)
    return False


class Checker:
    def __init__(self, schema):
        self.schema = schema
        self.problems = []
        self.warnings = []
        self.item_ids = set()
        base_items = res_path(schema["kinds"]["items"]["base"])
        if os.path.exists(base_items):
            self.item_ids = {i["id"] for i in load_json(base_items).get("items", []) if isinstance(i, dict) and "id" in i}
        self._base_ids = {}

    def base_ids(self, kind, coll):
        key = (kind, coll)
        if key not in self._base_ids:
            ids = set()
            base = self.schema["kinds"][kind].get("base", "")
            if base.startswith("res://") and os.path.exists(res_path(base)):
                data = load_json(res_path(base)).get(coll, {})
                if isinstance(data, dict):
                    ids = set(data.keys())
                elif isinstance(data, list):
                    ids = {e.get("id") for e in data if isinstance(e, dict)}
            self._base_ids[key] = ids
        return self._base_ids[key]

    def check_fields(self, where, rec, rule, patch):
        if not isinstance(rec, dict):
            self.problems.append("%s: should be an object" % where)
            return
        req = rule.get("required", {})
        opt = rule.get("optional", {})
        for k, t in req.items():
            if k not in rec:
                if not patch:
                    self.problems.append("%s: missing '%s' (%s)" % (where, k, t))
            elif rec[k] is not None and not type_ok(rec[k], t):
                self.problems.append("%s: '%s' should be %s" % (where, k, t))
        for k, v in rec.items():
            if k in req or k.startswith("_"):
                continue
            if k in opt:
                if v is not None and not type_ok(v, opt[k]):
                    self.problems.append("%s: '%s' should be %s" % (where, k, opt[k]))
            else:
                self.warnings.append("%s: unknown field '%s'" % (where, k))
        for k, how in rule.get("refs", {}).items():
            if k in rec and rec[k] is not None:
                for iid in self.ref_ids(rec[k], how):
                    if iid not in self.item_ids:
                        self.problems.append("%s: '%s' names an unknown item '%s'" % (where, k, iid))

    @staticmethod
    def ref_ids(v, how):
        out = []
        try:
            if how == "id":
                out = [v]
            elif how == "pair":
                out = [v[0]] if v else []
            elif how in ("pairs", "rows"):
                out = [row[0] for row in v]
            elif how == "bundles":
                out = [row[0] for bundle in v for row in bundle]
        except (TypeError, IndexError, KeyError):
            return ["<malformed>"]
        bad = ["<malformed>"] if any(not isinstance(x, str) for x in out) else []
        return [x for x in out if isinstance(x, str)] + bad

    def check_record(self, where, rec, rule_name, patch):
        rule = self.schema["records"][rule_name]
        if "list_of" in rule:
            if not isinstance(rec, list):
                self.problems.append("%s: should be a list" % where)
                return
            for i, e in enumerate(rec):
                self.check_fields("%s[%d]" % (where, i), e, rule["list_of"], False)
            return
        self.check_fields(where, rec, rule, patch)

    def check_file(self, kind, data, label, shipped=False):
        spec = self.schema["kinds"].get(kind)
        if spec is None:
            self.problems.append("%s: no data file of kind '%s' (known: %s)" % (label, kind, ", ".join(sorted(self.schema["kinds"]))))
            return
        if not isinstance(data, dict):
            self.problems.append("%s: the file should hold an object" % label)
            return
        for coll, cspec in spec["collections"].items():
            if coll not in data:
                continue
            v = data[coll]
            if cspec["as"] == "list":
                if not isinstance(v, list):
                    self.problems.append("%s: '%s' should be a list" % (label, coll))
                    continue
                for i, rec in enumerate(v):
                    rid = rec.get("id") if isinstance(rec, dict) else None
                    if not isinstance(rid, str) or rid == "":
                        self.problems.append("%s: %s[%d] has no 'id'" % (label, coll, i))
                        continue
                    patch = (not shipped) and rid in self.base_ids(kind, coll)
                    self.check_record("%s: %s '%s'" % (label, coll, rid), rec, cspec["record"], patch)
            else:
                if not isinstance(v, dict):
                    self.problems.append("%s: '%s' should be an object of id -> record" % (label, coll))
                    continue
                for rid, rec in v.items():
                    if rid.startswith("_") or rec is None:
                        continue
                    patch = (not shipped) and rid in self.base_ids(kind, coll)
                    self.check_record("%s: %s '%s'" % (label, coll, rid), rec, cspec["record"], patch)


def check_mod(folder, checker):
    man_path = os.path.join(folder, "mod.json")
    if not os.path.exists(man_path):
        checker.problems.append("%s: no mod.json" % folder)
        return
    try:
        man = load_json(man_path)
    except (ValueError, OSError) as e:
        checker.problems.append("mod.json: not valid JSON (%s)" % e)
        return
    checker.check_fields("mod.json", man, checker.schema["manifest"], False)
    files = man.get("files", []) if isinstance(man.get("files"), list) else []
    datas = []
    for f in files:
        if not isinstance(f, str) or not f.endswith(".json") or "/" in f or "\\" in f or f == "mod.json":
            checker.problems.append("mod.json: files: '%s' should be a data file's name (<kind>.json, beside mod.json)" % f)
            continue
        path = os.path.join(folder, f)
        if not os.path.exists(path):
            checker.problems.append("mod.json: files: '%s' is missing" % f)
            continue
        try:
            datas.append((f[:-5], load_json(path), f))
        except ValueError as e:
            checker.problems.append("%s: not valid JSON (%s)" % (f, e))
    for kind, data, f in datas:  # the mod's own items first: its recipes and loot may name them
        if kind == "items" and isinstance(data, dict) and isinstance(data.get("items"), list):
            checker.item_ids |= {i.get("id") for i in data["items"] if isinstance(i, dict) and isinstance(i.get("id"), str)}
    for kind, data, f in datas:
        checker.check_file(kind, data, f)


def check_shipped(checker):
    for kind, spec in checker.schema["kinds"].items():
        base = spec.get("base", "")
        if base.startswith("res://"):
            checker.check_file(kind, load_json(res_path(base)), base, shipped=True)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 2
    checker = Checker(load_json(SCHEMA_PATH))
    if argv[1] == "--shipped":
        check_shipped(checker)
        label = "shipped data"
    else:
        check_mod(argv[1], checker)
        label = argv[1]
    if "--quiet" not in argv:
        for w in checker.warnings:
            print("warning: " + w)
    for p in checker.problems:
        print("problem: " + p)
    print("%s: %s (%d problems, %d warnings)" % (label, "PASS" if not checker.problems else "FAIL", len(checker.problems), len(checker.warnings)))
    return 0 if not checker.problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
