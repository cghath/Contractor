class_name Flares
extends Node3D
## Illumination at night (AI bar G-24; LAMBS fires flares at night, Arma lights by them): a
## parachute flare bursts high over the ground, drifts down burning for its kind's "burn_s", and
## lights the ground round it: full within "full_m" (flat distance from the point under it),
## fading out to "edge_m", fading in its last FADE_S. Spotting reads it (Spotting.sight_x: the
## darkness at the one being looked at is cut by light_at), so a lit field is seen almost as by
## day, by both sides. Players' NVGs bloom in it (NvgView.bloom).
## Kinds (Proposed; KINDS): "hand" a hand-held parachute flare (HAND_ITEM, fired by a soldier:
## server_hand), "mortar" a mortar's illumination round (MortarFire.server_fire_illum, a faction's
## mortar team: MortarTeam.illum_for).
## Host authoritative: the host keeps the flares and sends each to every peer, and a late joiner
## asks for those still burning. One node, "Flares", under each level (of()).

const NODE_NAME := "Flares"
const GROUP := &"flares"
const HAND_ITEM := &"hand_flare"
## height_m: where it bursts over the ground; fall_mps: how fast it comes down under its chute.
const KINDS := {
	"hand": {"height_m": 150.0, "burn_s": 35.0, "fall_mps": 3.0, "full_m": 110.0, "edge_m": 220.0, "throw_m": 120.0},
	"mortar": {"height_m": 350.0, "burn_s": 45.0, "fall_mps": 5.0, "full_m": 200.0, "edge_m": 360.0, "throw_m": 0.0},
}
const FADE_S := 4.0
## The light it throws (visuals only: spotting goes by light_at).
const LIGHT_ENERGY := 6.0
const LIGHT_COLOUR := Color(1.0, 0.93, 0.78)
## Hand flares in hostile kits: every FLARE_EVERY-th hostile on the standard kit carries
## FLARES_CARRIED (insurgent_flares, as LauncherAI hands out RPGs). Proposed.
const FLARE_EVERY := 4
const FLARES_CARRIED := 2
const KIT_META := &"flare_kits"

## Every flare burning in this process: {"kind", "at" (the ground point under its burst),
## "born" (Soldier._now()), "id"}. Spotting and the NVG view read it (light_at).
static var burning: Array[Dictionary] = []
static var _next_id := 1
var _shown := {}  # flare id -> its Node3D (every peer with a display)


static func of(from: Node) -> Flares:
	var level := CompoundLevel.current(from)
	if level == null:
		return null
	var f := level.get_node_or_null(NODE_NAME) as Flares
	if f == null:
		f = Flares.new()
		f.name = NODE_NAME
		level.add_child(f)
	return f


func _ready() -> void:
	add_to_group(GROUP)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		(func() -> void: _ask_all.rpc_id(1)).call_deferred()


func _exit_tree() -> void:
	burning.clear()  # (a level's flares go with it)
	_shown.clear()


## How much flare light falls on `p` (0 none .. 1 full): the brightest burning flare's.
static func light_at(p: Vector3) -> float:
	if burning.is_empty():
		return 0.0
	var now := Soldier._now()
	var best := 0.0
	for f: Dictionary in burning.duplicate():
		var k: Dictionary = KINDS.get(String(f.kind), KINDS.hand)
		var age := now - float(f.born)
		if age >= float(k.burn_s):
			burning.erase(f)
			continue
		var at: Vector3 = f.at
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		var lit := 1.0 - clampf(inverse_lerp(float(k.full_m), float(k.edge_m), d), 0.0, 1.0)
		lit *= clampf((float(k.burn_s) - age) / FADE_S, 0.0, 1.0)
		best = maxf(best, lit)
	return best


## Where flare `f` is now (it drifts down from its burst), on every peer.
static func position_of(f: Dictionary) -> Vector3:
	var k: Dictionary = KINDS.get(String(f.kind), KINDS.hand)
	var age := Soldier._now() - float(f.born)
	var at: Vector3 = f.at
	var h := maxf(float(k.height_m) - float(k.fall_mps) * age, 10.0)
	return at + Vector3(sin(age * 0.4) * 3.0, h, cos(age * 0.3) * 3.0)


## Host: soldier `s` fires a hand flare over `toward` (at most the kind's "throw_m" out from him
## that way). Takes it from his kit. Returns whether it went up.
func server_hand(s: Soldier, toward: Vector3) -> bool:
	if not multiplayer.is_server() or s == null or not s.vitals.is_up() or Soldier._now() < s._busy_until:
		return false
	if not s.inventory.remove_one(HAND_ITEM):
		return false
	s._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	var to := Vector3(toward.x - s.global_position.x, 0.0, toward.z - s.global_position.z)
	var out := minf(to.length(), float(KINDS.hand.throw_m))
	var at := s.global_position + (to.normalized() * out if to.length() > 0.5 else Vector3.ZERO)
	server_pop("hand", at)
	Sfx.server_play(&"shot_grenade_launcher", s.global_position + Vector3.UP * 1.5)  # the pop of its launch
	print("[flare] %s puts up a flare over (%.0f, %.0f)" % [s.name, at.x, at.z])
	return true


## Host: a flare of `kind` bursts over ground point `at`, on every peer.
func server_pop(kind: String, at: Vector3) -> void:
	if not multiplayer.is_server() or not KINDS.has(kind):
		return
	var lvl := CompoundLevel.current(self)
	if lvl and lvl.has_method(&"ground_point"):
		at = lvl.call(&"ground_point", at)
	_next_id += 1
	_client_pop.rpc(_next_id, kind, at, 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var now := Soldier._now()
	for f: Dictionary in burning:
		_client_pop.rpc_id(peer, int(f.id), String(f.kind), f.at, now - float(f.born))


@rpc("authority", "call_local", "reliable")
func _client_pop(id: int, kind: String, at: Vector3, age: float) -> void:
	if burning.any(func(f: Dictionary) -> bool: return int(f.id) == id):
		return
	var f := {"id": id, "kind": kind, "at": at, "born": Soldier._now() - age}
	burning.append(f)
	if DisplayServer.get_name() == "headless":
		return  # (nothing to see)
	var node := Node3D.new()
	node.name = "Flare%d" % id
	var light := OmniLight3D.new()
	var k: Dictionary = KINDS[kind]
	light.omni_range = float(k.edge_m) + float(k.height_m)
	light.omni_attenuation = 0.6
	light.light_energy = LIGHT_ENERGY
	light.light_color = LIGHT_COLOUR
	node.add_child(light)
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.6
	ball.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LIGHT_COLOUR
	mat.emission_enabled = true
	mat.emission = LIGHT_COLOUR
	mat.emission_energy_multiplier = 8.0
	ball.material = mat
	mesh.mesh = ball
	node.add_child(mesh)
	add_child(node)
	node.global_position = position_of(f)
	_shown[id] = [node, light, f]


func _process(_delta: float) -> void:
	if _shown.is_empty():
		return
	var now := Soldier._now()
	for id: int in _shown.keys():
		var e: Array = _shown[id]
		var f: Dictionary = e[2]
		var k: Dictionary = KINDS[String(f.kind)]
		var age := now - float(f.born)
		if age >= float(k.burn_s):
			(e[0] as Node3D).queue_free()
			_shown.erase(id)
			continue
		(e[0] as Node3D).global_position = position_of(f)
		var flicker := 0.85 + 0.15 * sin(now * 23.0) * sin(now * 7.1)
		(e[1] as OmniLight3D).light_energy = LIGHT_ENERGY * flicker * clampf((float(k.burn_s) - age) / FADE_S, 0.0, 1.0)


## Host: the hand flares the next hostile on the standard kit spawned in `level` carries (most
## none; every FLARE_EVERY-th FLARES_CARRIED). Counted on the level.
static func insurgent_flares(level: Node) -> Array[StringName]:
	var n := int(level.get_meta(KIT_META, 0)) + 1
	level.set_meta(KIT_META, n)
	var out: Array[StringName] = []
	if (n - 1) % FLARE_EVERY == 0:
		for i in FLARES_CARRIED:
			out.append(HAND_ITEM)
	return out
