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

## Which campaign save is in use. Tests set their own ("test_<suite>" + CONTRACTOR_TEST_TAG)
## so they never touch a real one.
var campaign_id := "campaign_01"

var _sections: Dictionary = {}  # String -> Dictionary


## The state of one part of the campaign (created empty the first time it's asked for).
func section(section_name: StringName) -> Dictionary:
	var key := String(section_name)
	if not _sections.has(key):
		_sections[key] = {}
	return _sections[key]


## Host: a section changed (it saves with the rest on save_campaign).
func mark_changed(section_name: StringName) -> void:
	changed.emit(section_name)


func save_path() -> String:
	return "%s/%s.json" % [SAVE_DIR, campaign_id]


func save_campaign() -> void:
	# Through a checked temporary file, keeping the previous save as a backup (audit L1-05).
	GameState.write_safely(save_path(), JSON.stringify({"version": SAVE_VERSION, "sections": _sections}, "", true, true))


## Loads the save for campaign_id, or starts empty if there is none. Returns whether one was found.
func load_campaign() -> bool:
	_sections = {}
	if not FileAccess.file_exists(save_path()):
		return false
	var data: Variant = _read(save_path())
	if data == null and FileAccess.file_exists(GameState.backup_path(save_path())):
		data = _read(GameState.backup_path(save_path()))
		if data != null:
			push_warning("Campaign: %s was unreadable; loaded its backup" % save_path())
	if data == null:
		push_error("Campaign: unreadable save %s" % save_path())
		return false
	_sections = GameState.from_json(data.get("sections", {}))
	for key: String in _sections:
		changed.emit(StringName(key))
	return true


## Starts a fresh campaign (and deletes its save).
func reset_campaign() -> void:
	_sections = {}
	for path: String in [save_path(), GameState.backup_path(save_path()), save_path() + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The save at `path` if it reads as a campaign (a Dictionary whose "sections" is one), else null.
static func _read(path: String) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("sections", {})) != TYPE_DICTIONARY:
		return null
	return data
