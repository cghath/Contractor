class_name Tension
extends RefCounted
## Contractor: Fallen's tension layer (call 63, 142; docs/survival_audio.md): a near-subliminal
## bed (a low drone, a heartbeat) under the world, driven by the stealth model around you, not a
## score. Levels: calm, unease, alert, danger. It rises at once and falls one level at a time
## after COOLDOWN_S with nothing to keep it up; the volumes glide (FADE_S). A settings toggle
## mutes it (FallenAudio.setting "tension_on") and a slider sets its level ("tension").
##
## What raises it (ctx from FallenAudio.gather; the dead within NEAR_M):
## - danger: one of them chasing (ZombieAI CHASE), a scream just now, a raid on the settlement,
##   a horde within HORDE_NEAR_M;
## - alert: one ALERT or SEARCHING, or awareness at ZombieAI.ALERT_AT; the bite's delirium;
## - unease: one suspicious or with any awareness, UNEASE_N or more close, a horde in the zone,
##   the bite's fever.

enum Level { CALM, UNEASE, ALERT, DANGER }
const NAMES: Array[String] = ["calm", "unease", "alert", "danger"]
## Proposed: the numbers below.
const NEAR_M := 60.0
const UNEASE_N := 3
const UNEASE_AWARE := 0.1
const HORDE_NEAR_M := 120.0
const SCREAM_S := 8.0
const COOLDOWN_S := 8.0
const FADE_S := 2.0
## Each level's drone and heartbeat (0..1) and the heart's pace.
const DRONE := [0.0, 0.3, 0.55, 0.8]
const HEART := [0.0, 0.0, 0.35, 0.8]
const BPM := [60, 70, 96, 128]

var level: Level = Level.CALM
var target: int = Level.CALM
var drone := 0.0
var heart := 0.0
var enabled := true
var _hold := 0.0  # seconds left before it may drop a level


## The level `ctx` calls for, with no smoothing.
static func target_for(ctx: Dictionary) -> int:
	var t: int = Level.CALM
	if bool(ctx.get("raid", false)):
		t = Level.DANGER
	var horde_m := float(ctx.get("horde_m", INF))
	if horde_m <= HORDE_NEAR_M:
		t = Level.DANGER
	elif bool(ctx.get("horde", false)):
		t = maxi(t, Level.UNEASE)
	var stage := String(ctx.get("delirium", ""))
	if stage == "delirium" or stage == "collapse":
		t = maxi(t, Level.ALERT)
	elif stage == "fever":
		t = maxi(t, Level.UNEASE)
	var close := 0
	for z: Dictionary in ctx.get("zombies", []):
		if float(z.get("d", INF)) > NEAR_M:
			continue
		close += 1
		var mode := int(z.get("mode", -1))
		var aware := float(z.get("awareness", 0.0))
		if mode == ZombieAI.Mode.CHASE or float(z.get("screamed_s", INF)) <= SCREAM_S:
			t = Level.DANGER
		elif mode == ZombieAI.Mode.ALERT or mode == ZombieAI.Mode.SEARCH or aware >= ZombieAI.ALERT_AT:
			t = maxi(t, Level.ALERT)
		elif mode == ZombieAI.Mode.INVESTIGATE or aware >= UNEASE_AWARE:
			t = maxi(t, Level.UNEASE)
	if close >= UNEASE_N:
		t = maxi(t, Level.UNEASE)
	return t


## One step of `dt` seconds: the level (up at once, down one level per COOLDOWN_S quiet) and the
## gliding volumes. Returns the level.
func update(ctx: Dictionary, dt: float) -> int:
	target = target_for(ctx)
	if target >= level:
		if target > level:
			level = target as Level
		_hold = COOLDOWN_S
	else:
		_hold -= dt
		if _hold <= 0.0:
			level = (level - 1) as Level
			_hold = COOLDOWN_S
	var k := clampf(dt / FADE_S, 0.0, 1.0)
	drone = lerpf(drone, float(DRONE[level]) if enabled else 0.0, k)
	heart = lerpf(heart, float(HEART[level]) if enabled else 0.0, k)
	if not enabled and drone < 0.01:
		drone = 0.0
		heart = 0.0
	return level


func level_name() -> String:
	return NAMES[level]


func bpm() -> int:
	return int(BPM[level])


## Muted at once (the toggle), or back on.
func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		drone = 0.0
		heart = 0.0
