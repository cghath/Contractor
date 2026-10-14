extends Node
## The campaign that carries across contracts and deployments: money, contracts, the roster,
## the base stash, the campaign clock (wave 4). The host owns it and saves it to
## user://saves/<campaign_id>.json; clients see what the host sends them.
##
## Each part of the campaign keeps its state in its own section (section(&"economy"),
## section(&"roster")...), a plain Dictionary of JSON-safe values, so the parts save together
## without knowing about each other. Call mark_changed(name) after changing a section.

signal changed(section_name: StringName)

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1

## What the last load_campaign found: no save at all, a save it loaded (the save itself or,
## failing that, an interrupted write or the backup), or only files it couldn't read (kept
## aside, see load_campaign).
enum Loaded { NONE, LOADED, UNREADABLE }

## What the game reads from each saved section, by field (audit A1-03): the TYPE_* the field
## must be (TYPE_FLOAT: any finite number), or [TYPE_ARRAY or TYPE_DICTIONARY, element type]
## for a list or map whose every element must be that. A field a save doesn't have is fine (an
## older save: the game fills it in), and so is a section not listed here (its owner checks
## it); every section must be a Dictionary.
const SHAPES := {
	"economy": {"cash": TYPE_FLOAT, "day": TYPE_FLOAT, "rep": [TYPE_DICTIONARY, TYPE_FLOAT], "locals": TYPE_FLOAT,
		"loans": [TYPE_ARRAY, TYPE_DICTIONARY], "ledger": [TYPE_ARRAY, TYPE_DICTIONARY], "unbanked": [TYPE_ARRAY, TYPE_DICTIONARY],
		"week": TYPE_FLOAT},
	"contracts": {"seed": TYPE_FLOAT, "tag": TYPE_FLOAT, "next_id": TYPE_FLOAT, "board": [TYPE_ARRAY, TYPE_DICTIONARY],
		"held": [TYPE_ARRAY, TYPE_DICTIONARY], "history": [TYPE_ARRAY, TYPE_DICTIONARY], "deployment": TYPE_DICTIONARY,
		"objectives": [TYPE_ARRAY, TYPE_DICTIONARY], "debrief": TYPE_DICTIONARY, "debriefs": TYPE_FLOAT},
	"base": {"started": TYPE_BOOL, "stash": [TYPE_ARRAY, TYPE_DICTIONARY], "prep": TYPE_DICTIONARY},
	"roster": {"members": [TYPE_DICTIONARY, TYPE_DICTIONARY], "players": [TYPE_DICTIONARY, TYPE_DICTIONARY],
		"next_id": TYPE_FLOAT, "deployment": TYPE_DICTIONARY},
	"hiring": {"seed": TYPE_FLOAT, "refresh": TYPE_FLOAT, "refreshed_day": TYPE_FLOAT, "pool": [TYPE_ARRAY, TYPE_DICTIONARY]},
	"people": {"deployment": TYPE_DICTIONARY, "archive": [TYPE_ARRAY, TYPE_DICTIONARY]},
	"motor_pool": {"vehicles": [TYPE_ARRAY, TYPE_DICTIONARY], "serial": TYPE_FLOAT},
}

## Which campaign save is in use. Tests set their own ("test_<suite>" + CONTRACTOR_TEST_TAG)
## so they never touch a real one.
var campaign_id := "campaign_01"
## What the last load_campaign found (Loaded).
var last_load := Loaded.NONE
## What the host should be told about the last load_campaign ("" when the save loaded as it
## was, or there was none): which copy it fell back to, or which unreadable files it kept aside.
var load_notice := ""
## Why the last save_campaign failed ("" when it worked).
var save_error := ""

var _sections: Dictionary = {}  # String -> Dictionary


## The state of one part of the campaign (created empty the first time it's asked for).
func section(section_name: StringName) -> Dictionary:
	var key := String(section_name)
	if not _sections.has(key):
		_sections[key] = {}
	return _sections[key]


## Host: a deep copy of every section, to put back later with restore().
func snapshot() -> Dictionary:
	return _sections.duplicate(true)


## Host: every section back as it was in `snap` (from snapshot()), in place, so whoever holds
## a section Dictionary sees the old state; sections made since are emptied.
func restore(snap: Dictionary) -> void:
	for key: String in _sections:
		if not snap.has(key):
			(_sections[key] as Dictionary).clear()
	for key: String in snap:
		var s := section(StringName(key))
		s.clear()
		s.merge((snap[key] as Dictionary).duplicate(true))
		changed.emit(StringName(key))


## Host: a section changed (it saves with the rest on save_campaign).
func mark_changed(section_name: StringName) -> void:
	changed.emit(section_name)


func save_path() -> String:
	return "%s/%s.json" % [SAVE_DIR, campaign_id]


## Whether there's anything for load_campaign to load: the save, an interrupted write of it or
## its backup (audit A1-02: a backup alone is still the campaign).
func has_save() -> bool:
	return GameState.has_save(save_path())


## Writes the campaign through a checked temporary file, keeping the previous save as a backup
## (audit L1-05). Returns whether it was written (audit A1-04): when it wasn't, save_error says
## why and the save on disk is still the last good one.
func save_campaign() -> bool:
	save_error = ""
	if not GameState.write_safely(save_path(), JSON.stringify({"version": SAVE_VERSION, "sections": _sections}, "", true, true)):
		save_error = "Could not write %s; the last good save is kept" % ProjectSettings.globalize_path(save_path())
		return false
	return true


## Loads the save for campaign_id. Returns whether it loaded one; last_load says what it found
## and load_notice what the host should be told. Tries the save, then an interrupted write of
## it, then its backup (GameState.save_candidates, audit A1-02), so a campaign caught between
## write_safely's renames isn't lost. A file that can't be read (broken, another version, the
## wrong shape) is never deleted: it's moved aside beside the save (GameState.set_aside) before
## the next one is tried (audit A1-01). With nothing readable the campaign starts empty and
## last_load is UNREADABLE, so the caller knows it starts fresh over a lost one.
func load_campaign() -> bool:
	_sections = {}
	load_notice = ""
	last_load = Loaded.NONE
	var data: Variant = null
	var from := ""
	var kept: Array[String] = []
	for path: String in GameState.save_candidates(save_path()):
		if not FileAccess.file_exists(path):
			continue
		data = _read(path)
		if data != null:
			from = path
			break
		kept.append(GameState.set_aside(path, "unreadable").get_file())
	if data == null:
		if not kept.is_empty():
			last_load = Loaded.UNREADABLE
			load_notice = "The campaign save couldn't be read. Its files are kept in %s as %s; a new campaign starts." \
				% [ProjectSettings.globalize_path(SAVE_DIR), ", ".join(kept)]
			push_error("Campaign: " + load_notice)
		return false
	last_load = Loaded.LOADED
	if from != save_path():
		load_notice = "The campaign save was missing or damaged: loaded %s instead." % from.get_file()
		if not kept.is_empty():
			load_notice += " The damaged file is kept as %s." % ", ".join(kept)
		push_warning("Campaign: " + load_notice)
	_sections = GameState.from_json(data.sections)
	for key: String in _sections:
		changed.emit(StringName(key))
	return true


## Starts a fresh campaign (and deletes its save).
func reset_campaign() -> void:
	_sections = {}
	for path: String in GameState.save_candidates(save_path()):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The save at `path` if it reads as a campaign this game can use, else null (audit A1-03):
## this SAVE_VERSION, a Dictionary of sections, each a Dictionary whose fields have the SHAPES
## the game reads. Nothing of a save that fails is used.
static func _read(path: String) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Campaign: %s isn't a campaign save" % path)
		return null
	if not GameState.is_number(data.get("version")) or int(data.version) != SAVE_VERSION:
		push_warning("Campaign: %s is version %s; this game reads version %d" % [path, str(data.get("version")), SAVE_VERSION])
		return null
	if typeof(data.get("sections")) != TYPE_DICTIONARY:
		push_warning("Campaign: %s has no sections" % path)
		return null
	for key: Variant in data.sections:
		var s: Variant = data.sections[key]
		if typeof(s) != TYPE_DICTIONARY or not GameState.fields_ok(s, SHAPES.get(key, {})):
			push_warning("Campaign: %s: section \"%s\" has the wrong shape" % [path, str(key)])
			return null
	return data
