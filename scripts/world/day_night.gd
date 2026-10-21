class_name DayNight
extends Node
## Time of day and weather (wave 7, S1): one per level ("DayNight", CompoundLevel._ready), the
## same on every peer, the host's the truth.
##
## - Time of day: the zone definition's "hour" (0..24, DEFAULT_HOUR without one; a contract's
##   zone sets it), passing at TIME_SCALE in a contract zone (fixed in the compound, the base,
##   the range). The sun climbs and sets with it (sun_elevation_deg); below the horizon the
##   moon (a dim, blue light opposite) takes its place, and the sky, ambient and fill darken.
## - Weather: the definition's "weather", one of WEATHER (clear, overcast, fog, rain, storm),
##   each a row of data: haze (fog_x on the Environment's fog), light (on the sun and sky),
##   darkness it adds (dark_add: clouds make a darker night), sight (spot_x on the time to spot,
##   sight_m the furthest anyone is seen at all), hearing (hear_x on footsteps), rain (drops
##   near the camera, none headless) and whether it grounds helicopters (grounds).
## - Saved with the zone (GameState.sky: the save wins over the definition, except the hour
##   after travel: TRAVELLED, and a contract's own night or weather: CONTRACT_SKY) and replicated: a client asks the host on _ready, and the host
##   sends it to everyone every SYNC_S.
##
## Readers: Spotting (darkness_at, sight_m, spot_x, hearing_x; NVGs, wave 7 S2, restore sight
## in the dark there), Supports.can_fly (CompoundLevel.weather_grounds_aircraft ->
## grounds_aircraft). Every number is proposed, for Captain's playtests.

const NODE_NAME := "DayNight"
## Mid-morning: the sun at about the elevation zones were lit at before (ZoneLevel.SUN_ELEVATION_DEG).
const DEFAULT_HOUR := 8.5
const DEFAULT_WEATHER := "clear"
## The def's key for an arrival after travel (BaseHub.server_cross_on): its "hour" is the clock
## the squad brought with it, over the zone's save and a contract's own hour (audit A2-08).
const TRAVELLED := "travelled"
## The def's key for a deployment on a contract that rolled a night start or bad weather
## (missions 2: ContractGen.roll_conditions, BaseHub.contract_level_info): the def's "hour" and
## "weather" are the contract's, over the zone's save (a resume of the save has no such key).
const CONTRACT_SKY := "contract_sky"
## Game seconds per real second in a contract zone: an hour passes in 10 minutes.
const TIME_SCALE := 6.0
## The host sends the time and weather to every client this often (s).
const SYNC_S := 10.0
## The lights and sky follow the time this often (s).
const LOOK_S := 0.5
## Dev keys (DevTools.on(), the host; F-keys are the squad menu, ] the AAV's dev key).
const DEV_TIME_KEY := KEY_SEMICOLON
const DEV_WEATHER_KEY := KEY_APOSTROPHE
const DEV_HOURS := 2.0
## The sun's highest elevation (degrees, at noon); it rises at 06:00 and sets at 18:00.
const NOON_ELEVATION_DEG := 62.0
## Darkness: none with the sun this high (degrees), full this far below the horizon.
const LIGHT_FROM_DEG := 8.0
const DARK_FROM_DEG := -12.0
const MOON_ENERGY := 0.09
const MOON_COLOUR := Color(0.62, 0.70, 0.95)
## At full darkness the ambient and fill fall to this much of the day's.
const NIGHT_AMBIENT := 0.10
const NIGHT_SKY_TOP := Color(0.015, 0.02, 0.05)
const NIGHT_SKY_HORIZON := Color(0.04, 0.05, 0.09)
const OVERCAST_SKY := Color(0.55, 0.57, 0.60)
## The haze the weather thickens where the level has none of its own (ZoneLevel.FOG_DENSITY).
const BASE_FOG := 0.00035

const WEATHER := {
	"clear":    {"fog_x": 1.0,  "light": 1.0,  "dark_add": 0.0,  "spot_x": 1.0, "sight_m": INF,   "hear_x": 1.0,  "rain": 0,    "grounds": false},
	"overcast": {"fog_x": 2.0,  "light": 0.6,  "dark_add": 0.1,  "spot_x": 1.1, "sight_m": INF,   "hear_x": 1.0,  "rain": 0,    "grounds": false},
	"fog":      {"fog_x": 40.0, "light": 0.55, "dark_add": 0.05, "spot_x": 1.5, "sight_m": 150.0, "hear_x": 1.0,  "rain": 0,    "grounds": false},
	"rain":     {"fog_x": 6.0,  "light": 0.5,  "dark_add": 0.15, "spot_x": 1.3, "sight_m": 400.0, "hear_x": 0.75, "rain": 900,  "grounds": false},
	"storm":    {"fog_x": 10.0, "light": 0.35, "dark_add": 0.25, "spot_x": 1.6, "sight_m": 250.0, "hear_x": 0.55, "rain": 2200, "grounds": true},
}

static var _current: DayNight

## The hour now (0..24).
var hour := DEFAULT_HOUR
## One of WEATHER.
var weather := DEFAULT_WEATHER
## Whether the time passes here (a contract zone).
var passing := false

var _sync_left := SYNC_S
var _look_left := 0.0
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _env: Environment
var _base := {}
var _rain: GPUParticles3D
var _touched := false  # the look has been changed from the level's own


static func current() -> DayNight:
	return _current if is_instance_valid(_current) and _current.is_inside_tree() else null


## How dark it is at `pos` now: 0 full day, 1 the darkest night (with the weather's clouds).
## Off a level: 0. `pos` is for later (shelter, lights); today it's the same everywhere.
static func darkness_at(_pos: Vector3) -> float:
	var dn := current()
	return dn.darkness() if dn else 0.0


## The furthest anyone is seen at all in this weather (m; INF: no limit). Night is darkness_at's.
static func sight_m(_pos: Vector3) -> float:
	var dn := current()
	return float(dn.row().sight_m) if dn else INF


## The weather's factor on the time to spot someone (1: none).
static func spot_x(_pos: Vector3) -> float:
	var dn := current()
	return float(dn.row().spot_x) if dn else 1.0


## The weather's factor on how far footsteps carry (rain covers them).
static func hearing_x() -> float:
	var dn := current()
	return float(dn.row().hear_x) if dn else 1.0


## Whether the weather grounds helicopters now (a storm).
static func grounds_aircraft() -> bool:
	var dn := current()
	return dn != null and bool(dn.row().grounds)


## The sun's elevation at `h` o'clock (degrees; below 0 it's night).
static func sun_elevation_deg(h: float) -> float:
	return sin((fposmod(h, 24.0) - 6.0) / 12.0 * PI) * NOON_ELEVATION_DEG


## Darkness from the sun alone at `h` o'clock (0 day .. 1 night).
static func night_of(h: float) -> float:
	return 1.0 - smoothstep(DARK_FROM_DEG, LIGHT_FROM_DEG, sun_elevation_deg(h))


static func has_weather(w: String) -> bool:
	return WEATHER.has(w)


func _init() -> void:
	name = NODE_NAME


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _ready() -> void:
	var level := get_parent()
	var def: Dictionary = level.get(&"def") if level and "def" in level and level.get(&"def") is Dictionary else {}
	passing = "def" in level  # a contract zone (ZoneLevel)
	_set_state(float(def.get("hour", DEFAULT_HOUR)), String(def.get("weather", DEFAULT_WEATHER)))
	_find_lights()
	if DisplayServer.get_name() != "headless":
		_make_rain()
	_apply_look()
	# A client asks the host for its time and weather: now if it's in, else once it is (a level
	# loads while the client is still authenticating).
	if not multiplayer.is_server():
		if 1 in multiplayer.get_peers():
			_request.rpc_id(1)
		else:
			Net.joined.connect(_ask_host, CONNECT_ONE_SHOT)


## Dev keys (DevTools.on(), the host): ; moves the clock on DEV_HOURS, ' the next weather.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or not multiplayer.is_server() or not DevTools.on():
		return
	var key := (event as InputEventKey).keycode
	if key == DEV_TIME_KEY:
		server_set(hour + DEV_HOURS, weather)
	elif key == DEV_WEATHER_KEY:
		var names := WEATHER.keys()
		server_set(hour, String(names[(names.find(weather) + 1) % names.size()]))
	else:
		return
	print("[daynight] %05.2f h, %s (darkness %.2f)" % [hour, weather, darkness()])
	get_viewport().set_input_as_handled()


func _ask_host() -> void:
	if is_inside_tree() and not multiplayer.is_server():
		_request.rpc_id(1)


func row() -> Dictionary:
	return WEATHER.get(weather, WEATHER[DEFAULT_WEATHER])


func darkness() -> float:
	return clampf(night_of(hour) + float(row().dark_add) * (0.4 + 0.6 * night_of(hour)), 0.0, 1.0)


## What the zone's save keeps (GameState.sky).
func to_save() -> Dictionary:
	return {"hour": hour, "weather": weather}


## Host (CompoundLevel._on_hosted, after GameState.load_zone): the saved time and weather, if
## the zone has any, over the definition's. Walked or flown in from another zone (TRAVELLED),
## the hour is the travel clock's, not the one the zone was left at: only a resume of the save
## (BaseHub.resume_info) takes its hour back. The saved weather stays either way.
func server_restore() -> void:
	var saved: Dictionary = GameState.sky
	if not (saved.has("hour") or saved.has("weather")):
		saved = _contract_sky()
	var level := get_parent()
	var def: Dictionary = level.get(&"def") if level and "def" in level and level.get(&"def") is Dictionary else {}
	if bool(def.get(TRAVELLED, false)) and def.has("hour"):
		saved = saved.duplicate()
		saved["hour"] = float(def.hour)
	if bool(def.get(CONTRACT_SKY, false)):
		saved = saved.duplicate()
		for key: String in ["hour", "weather"]:
			if def.has(key):
				saved[key] = def[key]  # the contract's own night or weather, over the zone's save
	if saved.has("hour") or saved.has("weather"):
		_set_state(float(saved.get("hour", hour)), String(saved.get("weather", weather)))
		_apply_look()


## A deployed contract's own "hour" and "weather" (over the zone's), if one has them.
static func _contract_sky() -> Dictionary:
	for cid: Variant in Contracts.deployment().get("cids", []):
		var c: Dictionary = Contracts.contract(String(cid))
		if c.has("hour") or c.has("weather"):
			return c
	return {}


## Host: sets the time and weather (a contract, DevTools, tests) and tells every client.
func server_set(h: float, w: String) -> void:
	_set_state(h, w)
	_apply_look()
	_broadcast()


## Moves the clock on `seconds` of real time (TIME_SCALE game seconds each).
func advance(seconds: float) -> void:
	hour = fposmod(hour + seconds * TIME_SCALE / 3600.0, 24.0)


func _set_state(h: float, w: String) -> void:
	hour = fposmod(h, 24.0)
	weather = w if has_weather(w) else DEFAULT_WEATHER
	GameState.sky = to_save()


func _process(delta: float) -> void:
	var server := multiplayer.is_server()
	if passing:
		advance(delta)  # clients run the clock too; the host's sync corrects them
	if server:
		GameState.sky = to_save()
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_S
			_broadcast()
	_look_left -= delta
	if _look_left <= 0.0:
		_look_left = LOOK_S
		_apply_look()
	if _rain and _rain.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_rain.global_position = cam.global_position + Vector3.UP * 12.0


func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _broadcast() -> void:
	if _connected() and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_sync.rpc(hour, weather)


@rpc("any_peer", "reliable")
func _request() -> void:
	if multiplayer.is_server():
		_sync.rpc_id(multiplayer.get_remote_sender_id(), hour, weather)


@rpc("authority", "reliable")
func _sync(h: float, w: String) -> void:
	_set_state(h, w)
	_apply_look()


# --- The look ----------------------------------------------------------------------------------

func _find_lights() -> void:
	var level := get_parent()
	if level == null:
		return
	for child in level.get_children():
		if child is DirectionalLight3D:
			if _sun == null and String(child.name) != "SkyFill":
				_sun = child
			elif _fill == null:
				_fill = child
		elif child is WorldEnvironment and _env == null:
			_env = (child as WorldEnvironment).environment
	if _sun:
		_base["sun_energy"] = _sun.light_energy
		_base["sun_colour"] = _sun.light_color
		_base["sun_yaw"] = _sun.rotation_degrees.y
	if _fill:
		_base["fill_energy"] = _fill.light_energy
	if _env:
		_base["ambient"] = _env.ambient_light_energy
		_base["fog_on"] = _env.fog_enabled
		_base["fog"] = _env.fog_density if _env.fog_enabled else 0.0
		_base["fog_colour"] = _env.fog_light_color
		var mat: Material = _env.sky.sky_material if _env.sky else null
		if mat is ProceduralSkyMaterial:
			_base["top"] = (mat as ProceduralSkyMaterial).sky_top_color
			_base["horizon"] = (mat as ProceduralSkyMaterial).sky_horizon_color
		elif mat is ShaderMaterial:
			_base["top"] = (mat as ShaderMaterial).get_shader_parameter(&"sky_top")
			_base["horizon"] = (mat as ShaderMaterial).get_shader_parameter(&"sky_horizon")
			_base["ridge"] = (mat as ShaderMaterial).get_shader_parameter(&"ridge_colour")


func _apply_look() -> void:
	var w := row()
	if _rain:
		var drops := int(w.rain)
		_rain.emitting = drops > 0
		if drops > 0 and _rain.amount != drops:
			_rain.amount = drops
	# A level at its own default (the compound, the base, the range) keeps the look it built.
	if not _touched and not passing and is_equal_approx(hour, DEFAULT_HOUR) and weather == DEFAULT_WEATHER:
		return
	_touched = true
	var night := night_of(hour)
	var dark := darkness()
	var light := float(w.light)
	var day := 1.0 - night
	if _sun:
		var el := sun_elevation_deg(hour)
		var yaw := float(_base.get("sun_yaw", -35.0)) + (fposmod(hour, 24.0) - DEFAULT_HOUR) * 12.0
		if el > 0.0 or night < 0.5:
			_sun.rotation_degrees = Vector3(-maxf(el, 2.0), yaw, 0.0)
			_sun.light_color = (_base.get("sun_colour", Color.WHITE) as Color).lerp(Color(1.0, 0.62, 0.38), clampf(1.0 - el / 25.0, 0.0, 1.0) * 0.6)
			_sun.light_energy = float(_base.get("sun_energy", 1.0)) * light * day
		else:  # the moon, opposite where the sun is
			_sun.rotation_degrees = Vector3(-maxf(-el, 15.0), yaw + 180.0, 0.0)
			_sun.light_color = MOON_COLOUR
			_sun.light_energy = MOON_ENERGY * (1.0 - float(w.dark_add) * 2.0)
	if _fill:
		_fill.light_energy = float(_base.get("fill_energy", 0.35)) * lerpf(1.0, NIGHT_AMBIENT, dark) * lerpf(1.0, light, 0.5)
	if _env == null:
		return
	_env.ambient_light_energy = float(_base.get("ambient", 1.0)) * lerpf(1.0, NIGHT_AMBIENT, dark) * lerpf(1.0, light, 0.5)
	var fog_x := float(w.fog_x)
	if fog_x > 1.0:
		_env.fog_enabled = true
		_env.fog_density = maxf(float(_base.get("fog", 0.0)), BASE_FOG) * fog_x
	else:
		_env.fog_enabled = bool(_base.get("fog_on", false))
		_env.fog_density = float(_base.get("fog", 0.0))
	var grey := clampf((1.0 - light) * 1.4, 0.0, 1.0)
	var fog_colour := (_base.get("fog_colour", Color(0.72, 0.77, 0.83)) as Color).lerp(OVERCAST_SKY, grey)
	_env.fog_light_color = fog_colour.lerp(NIGHT_SKY_HORIZON, dark)
	if not _base.has("top") or _env.sky == null:
		return
	var top := (_base.top as Color).lerp(OVERCAST_SKY * 0.85, grey).lerp(NIGHT_SKY_TOP, dark)
	var horizon := (_base.horizon as Color).lerp(OVERCAST_SKY, grey).lerp(NIGHT_SKY_HORIZON, dark)
	var mat := _env.sky.sky_material
	if mat is ProceduralSkyMaterial:
		var p := mat as ProceduralSkyMaterial
		p.sky_top_color = top
		p.sky_horizon_color = horizon
		p.ground_horizon_color = horizon
		p.ground_bottom_color = horizon
	elif mat is ShaderMaterial:  # zone_sky.gdshader: its own uniforms, no shader edit
		var s := mat as ShaderMaterial
		s.set_shader_parameter(&"sky_top", top)
		s.set_shader_parameter(&"sky_horizon", horizon)
		if _base.has("ridge") and _base.ridge is Color:
			s.set_shader_parameter(&"ridge_colour", (_base.ridge as Color).lerp(NIGHT_SKY_HORIZON * 0.8, dark))


## Rain: streaks falling in a box round the camera (with a display only).
func _make_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 1.4
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	pm.direction = Vector3(0.05, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.015, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	quad.material = m
	_rain.draw_pass_1 = quad
	add_child(_rain)
