class_name Handedness
extends RefCounted
## Which shoulder a soldier shoots from (Soldier.left_handed).
##
## Players pick on the main menu; the pick is saved in SETTINGS_PATH and sent to the host on
## join (CompoundLevel.request_handedness). AI soldiers are left-handed at LEFT_SHARE, the
## real rate for men: about 10.6% of people are left-handed (Papadatou-Pastou et al. 2020,
## "Human handedness: a meta-analysis"), and men are about 1.23 times as likely as women
## (Papadatou-Pastou et al. 2008), which puts men near 11-12%. Each AI's roll is seeded by
## its name, so a callsign keeps its shoulder across respawns and zone reloads. The shooting
## shoulder follows the hand here; eye dominance (about a third of people sight with the left
## eye) isn't modelled.

const LEFT_SHARE := 0.11
const SETTINGS_PATH := "user://settings.cfg"

static var _left := false
static var _loaded := false


## The local player's pick (main menu), from SETTINGS_PATH the first time.
static func local_left() -> bool:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			_left = bool(cfg.get_value("player", "left_handed", false))
	return _left


## Sets and saves the local player's pick (other settings in the file are kept).
static func set_local_left(left: bool) -> void:
	_left = left
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "left_handed", left)
	cfg.save(SETTINGS_PATH)


## Whether the AI soldier called `soldier_name` shoots left-handed (LEFT_SHARE of them, the
## same answer every time for the same name).
static func roll_ai(soldier_name: String) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("handedness:" + soldier_name)
	return rng.randf() < LEFT_SHARE
