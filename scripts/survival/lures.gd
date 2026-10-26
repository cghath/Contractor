class_name Lures
extends RefCounted
## Lures and distractions (docs/survival_seasons.md; call 53): noise the dead go to, so they can be
## drawn off a route, away from the walls or onto a raider camp. Host only, static: the noises go
## through Survival.server_noise (the live dead's hearing) and the zone's pressure (the crowd's
## pull); the lasting ones are on a list ticked by Sieges every TICK_S.
## - a thrown bottle (the "glass_bottle" throwable: Throwables "bottle"): one smash at the spot;
## - a car alarm (a wreck's: server_car_alarm): CAR_S of noise every CAR_EVERY_S, loud;
## - a radio left playing (the lure_radio piece, "Leave it playing"): RADIO_S on its batteries;
## - a flare (Flares, burning): at night the light pulls the dead under it (FLARE_EVERY_S);
## - a tied goat (the goat_stake piece): it bleats every GOAT_EVERY_S until the dead reach it.
## Every number here is Proposed.

const TICK_S := 0.5
const BOTTLE_M := 35.0
const BOTTLE_LOUD := 0.6
const BOTTLE_PRESSURE := 2.0
const CAR_S := 60.0
const CAR_EVERY_S := 2.0
const CAR_M := 120.0
const CAR_PRESSURE := 1.0
const RADIO_S := 300.0
const RADIO_EVERY_S := 4.0
const RADIO_M := 60.0
const FLARE_EVERY_S := 5.0
const FLARE_M := 80.0
const GOAT_EVERY_S := 6.0
const GOAT_M := 40.0
const GOAT_BITE_M := 1.5
const GOAT_BITE := 10.0

## Host: the lasting lures [{at, until, every, next, radius, loud, pressure, kind, piece}].
static var active: Array[Dictionary] = []
static var _flare_next := {}


## Host: a bottle smashed at `at`.
static func server_bottle(level: Node, at: Vector3) -> int:
	return _noise(level, at, BOTTLE_M, BOTTLE_LOUD, BOTTLE_PRESSURE)


## Host: a car alarm going off at `at` (a wreck: the vehicles lane's menu calls this).
static func server_car_alarm(level: Node, at: Vector3) -> void:
	_noise(level, at, CAR_M, ZombieAI.HEAR_SHOT, CAR_PRESSURE)
	active.append({"kind": "car_alarm", "at": at, "until": Soldier._now() + CAR_S, "every": CAR_EVERY_S, "next": Soldier._now() + CAR_EVERY_S,
		"radius": CAR_M, "loud": ZombieAI.HEAR_SHOT, "pressure": CAR_PRESSURE, "piece": -1})
	Survival._journal_line("A car alarm is wailing.")


## Host: the radio piece `id` left playing.
static func server_radio_on(b: Builder, id: int) -> String:
	if not b.is_piece_built(id):
		return "?"
	for l: Dictionary in active:
		if int(l.piece) == id:
			return "It's playing"
	var at := b.piece_pos(id)
	active.append({"kind": "radio", "at": at, "until": Soldier._now() + RADIO_S, "every": RADIO_EVERY_S, "next": Soldier._now(),
		"radius": RADIO_M, "loud": 0.5, "pressure": 0.5, "piece": id})
	return ""


## Host: every TICK_S: the lasting lures, the flares at night, the goats.
static func server_tick(level: Node) -> void:
	var now := Soldier._now()
	var b := Builder.find(level)
	var i := 0
	while i < active.size():
		var l := active[i]
		if now >= float(l.until) or (int(l.piece) > 0 and (b == null or not b.pieces.has(int(l.piece)))):
			active.remove_at(i)
			continue
		if now >= float(l.next):
			l["next"] = now + float(l.every)
			_noise(level, l.at, float(l.radius), float(l.loud), float(l.pressure))
		i += 1
	if DayNight.night_of(Survival.hour()) > 0.5:
		for f: Dictionary in Flares.burning:
			var key := int(f.get("id", 0))
			if now >= float(_flare_next.get(key, 0.0)):
				_flare_next[key] = now + FLARE_EVERY_S
				_noise(level, f.at as Vector3, FLARE_M, 0.4, 0.5)  # (the ground under its light)
	if b:
		for id: int in b.pieces_of("goat_stake"):
			if not b.is_piece_built(id):
				continue
			var at := b.piece_pos(id)
			var rec: Dictionary = b.pieces[id]
			if now >= float(rec.get("bleat", 0.0)):
				rec["bleat"] = now + GOAT_EVERY_S
				_noise(level, at, GOAT_M, 0.5, 0.3)
			for z: Soldier in Survival.zombies(level):
				if Vector2(z.global_position.x - at.x, z.global_position.z - at.z).length() <= GOAT_BITE_M:
					b.server_hit_piece(id, GOAT_BITE * TICK_S)
					if not b.pieces.has(id):
						Survival._journal_line("The goat's gone quiet.")
						break


static func _noise(level: Node, at: Vector3, radius: float, loud: float, pressure: float) -> int:
	if level == null:
		return 0
	var heard := 0
	for z: Soldier in Survival.zombies(level):
		if z.global_position.distance_to(at) <= radius:
			heard += 1
	Survival.server_noise(level, at, radius, loud)
	if pressure > 0.0 and level is ZoneLevel:
		Survival._raise_pressure(level, at, pressure)
	return heard
