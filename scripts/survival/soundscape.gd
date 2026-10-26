class_name Soundscape
extends RefCounted
## Contractor: Fallen's diegetic soundscape (call 63; docs/survival_audio.md): what the world
## sounds like around you, worked out from a snapshot (FallenAudio.gather) so it runs and tests
## the same with no audio device. `update(ctx, now)` returns the mix: each layer's volume 0..1
## (0 silent) and where the positional ones come from.
##
## Layers (World bus):
## - wind: by the weather's wind (DayNight.WEATHER wind_mps) and where you are (the region's
##   exposure; indoors it's a murmur through the walls);
## - rain: by the weather (rain, storm), on the roof when indoors;
## - groans: the crowd (ZoneDead's heads) within GROAN_M, louder the more of them and the nearer,
##   from their bearing (the density-weighted mean direction); a horde adds;
## - hum: a powered settlement's generators and lights, while you're inside its radius;
## - breath: your own, when the stamina or sleep is low; shiver: when the core is cold (Needs);
## - birds: by day and dry, and they go quiet when the dead or a stranger comes within
##   BIRD_QUIET_M, and stay quiet BIRD_RETURN_S after (silence is information).
## Footsteps by surface are Sfx's own (every peer, by the ground under the soldier).

const LAYERS: Array[String] = ["wind", "rain", "groans", "hum", "breath", "shiver", "birds"]
## Proposed: the numbers below.
const WIND_FULL_MPS := 14.0
const REGION_WIND := {"hills": 1.15, "coast": 1.1, "desert": 1.1, "plains": 1.0, "city": 0.7}
const INDOOR_WIND := 0.3
const RAIN_VOL := {"rain": 0.6, "storm": 1.0}
const INDOOR_RAIN := 0.45
const GROAN_M := 250.0
const GROAN_FULL_N := 40.0  # heads (weighted by nearness) for a full chorus
const HORDE_GROAN := 0.35
const HUM_VOL := 0.35
const BREATH_STAMINA := 0.3  # movement stamina 0..1 under this: you hear yourself
const BREATH_SLEEP := 30.0  # Needs.SLEEP_LOW
const BIRD_QUIET_M := 30.0
const BIRD_RETURN_S := 40.0
const BIRD_HOURS := Vector2(5.0, 20.5)
const BIRD_VOL := 0.4

var birds_quiet_until := -1.0
var mix := {}


## The mix for `ctx` at `now` (seconds): {"wind", "rain", "groans", "hum", "breath", "shiver",
## "birds"} volumes, "groan_dir" (Vector2: from you toward the crowd, unit; ZERO none), "groan_m"
## (the crowd's weighted distance), "birds_quiet" (bool: they stopped because something's near).
func update(ctx: Dictionary, now: float) -> Dictionary:
	var m := {}
	var indoors := bool(ctx.get("indoors", false))
	var weather := String(ctx.get("weather", "clear"))
	var wind := clampf(float(ctx.get("wind_mps", 3.0)) / WIND_FULL_MPS, 0.0, 1.0)
	wind *= float(REGION_WIND.get(String(ctx.get("region", "plains")), 1.0))
	m["wind"] = clampf(wind * (INDOOR_WIND if indoors else 1.0), 0.0, 1.0)
	m["rain"] = float(RAIN_VOL.get(weather, 0.0)) * (INDOOR_RAIN if indoors else 1.0)
	var g := groans(ctx)
	m["groans"] = float(g.vol)
	m["groan_dir"] = g.dir
	m["groan_m"] = float(g.dist)
	m["hum"] = HUM_VOL if bool(ctx.get("powered", false)) else 0.0
	var stamina := float(ctx.get("stamina", 1.0))
	var sleep := float(ctx.get("sleep", 100.0))
	var breath := 0.0
	if stamina < BREATH_STAMINA:
		breath = 1.0 - stamina / BREATH_STAMINA
	if sleep < BREATH_SLEEP:
		breath = maxf(breath, 0.4 * (1.0 - sleep / BREATH_SLEEP) + 0.2)
	m["breath"] = clampf(breath, 0.0, 1.0) * 0.6
	var warmth := float(ctx.get("warmth", Needs.NORMAL_C))
	m["shiver"] = clampf((Needs.SHIVER_C - warmth) / (Needs.SHIVER_C - Needs.FROZEN_C), 0.0, 1.0) * 0.6 if warmth < Needs.SHIVER_C else 0.0
	# Birds: day, dry, and nothing near.
	var near := _threat_near(ctx)
	if near:
		birds_quiet_until = now + BIRD_RETURN_S
	var h := float(ctx.get("hour", 12.0))
	var day := h >= BIRD_HOURS.x and h <= BIRD_HOURS.y
	var dry := not RAIN_VOL.has(weather)
	var quiet := now < birds_quiet_until
	m["birds_quiet"] = quiet and day and dry
	m["birds"] = BIRD_VOL * (0.4 if indoors else 1.0) if day and dry and not quiet else 0.0
	mix = m
	return m


## Whether one of the dead (a live one or a crowd head) or a living stranger is within
## BIRD_QUIET_M of you.
static func _threat_near(ctx: Dictionary) -> bool:
	for z: Dictionary in ctx.get("zombies", []):
		if float(z.get("d", INF)) <= BIRD_QUIET_M:
			return true
	for d: float in ctx.get("living", []):
		if d <= BIRD_QUIET_M:
			return true
	var me: Vector2 = ctx.get("me", Vector2.ZERO)
	for p: Vector2 in ctx.get("crowd", []):
		if p.distance_to(me) <= BIRD_QUIET_M:
			return true
	return false


## The crowd's chorus: its volume (by how many heads within GROAN_M, the near ones counting
## more), its bearing (the weighted mean of the directions to them) and their weighted distance.
static func groans(ctx: Dictionary) -> Dictionary:
	var me: Vector2 = ctx.get("me", Vector2.ZERO)
	var sum := Vector2.ZERO
	var weight := 0.0
	var dist := 0.0
	for p: Vector2 in ctx.get("crowd", []):
		var d := p.distance_to(me)
		if d > GROAN_M or d < 0.01:
			continue
		var w := 1.0 - d / GROAN_M
		sum += (p - me) / d * w
		weight += w
		dist += d * w
	var vol := clampf(weight / GROAN_FULL_N, 0.0, 1.0) * 0.8
	if bool(ctx.get("horde", false)):
		vol = minf(vol + HORDE_GROAN, 1.0)
	return {"vol": vol, "dir": sum.normalized() if sum.length() > 0.001 else Vector2.ZERO, "dist": dist / weight if weight > 0.0 else 0.0}
