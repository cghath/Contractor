class_name MeleeInput
extends RefCounted
## The player's melee controls (docs/survival.md call 86; Captain, 2026-10-26: "both"): with a
## melee weapon up, fire is a light swing, fire held past HEAVY_HOLD_S winds up a heavy, aim
## holds a block (a block raised just before a blow lands is the parry: Melee), and a movement
## key double-tapped is the sidestep (left, right) or dodge (forward, back) that way. With a gun
## up, the quick melee key is a shove with the butt. Behind an unaware zombie with a blade, the
## interact key tapped is the silent kill. Everything goes to the host as one RPC
## (Soldier._server_melee -> MeleeWeapons.server_action); the dodge's movement is the owner's
## (Soldier.dodge_input, read by SoldierMovement for the i-frames' length).

const DOUBLE_TAP_S := 0.3
const DIRS := {&"move_forward": Vector2(0, -1), &"move_back": Vector2(0, 1), &"move_left": Vector2(-1, 0), &"move_right": Vector2(1, 0)}

var body: Soldier
var _fire_down_at := -1.0
var _heavy_sent := false
var _blocking := false
var _taps := {}
var _dodge_until := -1.0


func _init(s: Soldier) -> void:
	body = s


## Each frame the game has the mouse and a melee weapon is up.
func update(hud: Node) -> void:
	var now := Soldier._now()
	if Archery.is_bow(body.active_weapon()):
		_update_bow(hud, now)
		_update_dodge(now)
		return
	if Input.is_action_just_pressed(&"fire"):
		_fire_down_at = now
		_heavy_sent = false
	if _fire_down_at >= 0.0 and Input.is_action_pressed(&"fire") and not _heavy_sent and now - _fire_down_at >= MeleeWeapons.HEAVY_HOLD_S:
		_heavy_sent = true
		body._server_melee.rpc_id(1, "heavy")
	if _fire_down_at >= 0.0 and Input.is_action_just_released(&"fire"):
		if not _heavy_sent:
			body._server_melee.rpc_id(1, "light")
		_fire_down_at = -1.0
	var want_block := Input.is_action_pressed(&"aim")
	if want_block != _blocking:
		_blocking = want_block
		body._server_melee.rpc_id(1, "block_on" if want_block else "block_off")
	_update_dodge(now)
	if hud and Input.is_action_just_pressed(&"fire") and body.movement and body.movement.stamina < 0.05:
		hud.flash("Too tired to swing")


## A bow up (Archery): fire held draws (full at Archery.draw_s), let go looses from the eye where
## it looks. No block with a bow.
func _update_bow(hud: Node, now: float) -> void:
	if _blocking:
		_blocking = false
		body._server_melee.rpc_id(1, "block_off")
	var bow := body.active_weapon()
	if Input.is_action_just_pressed(&"fire"):
		if body.inventory.count_of(Archery.ARROW) <= 0:
			if hud:
				hud.flash("No arrows")
			return
		_fire_down_at = now
		_heavy_sent = false  # (here: "full draw" said)
	if _fire_down_at < 0.0:
		return
	var draw := clampf((now - _fire_down_at) / Archery.draw_s(body, bow), 0.0, 1.0)
	if draw >= 1.0 and not _heavy_sent:
		_heavy_sent = true
		if hud:
			hud.flash("Full draw")
	if Input.is_action_just_released(&"fire"):
		var eye := body.camera.global_transform if body.camera else body.global_transform
		body._server_loose.rpc_id(1, eye.origin, -eye.basis.z, draw)
		_fire_down_at = -1.0
		_heavy_sent = false


## A movement key tapped twice within DOUBLE_TAP_S: the sidestep or dodge that way (any weapon up).
func _update_dodge(now: float) -> void:
	for action: StringName in DIRS:
		if not Input.is_action_just_pressed(action):
			continue
		var last: float = _taps.get(action, -10.0)
		_taps[action] = now
		if now - last > DOUBLE_TAP_S or now < _dodge_until:
			continue
		var dir: Vector2 = DIRS[action]
		var sidestep := dir.x != 0.0
		var frames := Melee.SIDESTEP_IFRAMES_S if sidestep else Melee.DODGE_IFRAMES_S
		_dodge_until = now + frames + 0.15
		body.dodge_input = dir
		body.dodge_until = now + frames + 0.1
		body._server_melee.rpc_id(1, "sidestep" if sidestep else "dodge")


## The weapon went down (a gun, a grenade, the hands busy): let go of the block.
func drop() -> void:
	if _blocking:
		_blocking = false
		body._server_melee.rpc_id(1, "block_off")
	_fire_down_at = -1.0
	_heavy_sent = false


## Behind an unaware zombie within reach with a blade: the silent kill on the interact key.
## Returns whether it was asked for (the interaction menu then leaves the tap alone).
func try_silent_kill() -> bool:
	if not Input.is_action_just_pressed(&"interact"):
		return false
	var target := Melee.silent_kill_target(body)
	if target == null:
		return false
	body._server_melee.rpc_id(1, "silent")
	return true
