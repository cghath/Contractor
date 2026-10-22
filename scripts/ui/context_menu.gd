class_name ContextMenu
extends Control
## The one-key contextual order in the world (docs/combined_arms.md 5.5): what you look at
## decides the options (ContextResolver). Tap `context` (middle mouse by default) for the top
## option, hold it for the radial with the rest and "More..." (the full command menu); let go on
## the one you want. A prompt under the crosshair names the default ("[Middle] Follow me: Alpha").
## Recently used options come first. The number-tree command menu and the interaction menu stay
## as they are. Local to its player; every act goes through the existing host requests.

const ACTION := &"context"
const HOLD_S := 0.25
const RADIUS_PX := 130.0
const LOOK_M := 300.0
const PROMPT_S := 0.2

var player: Soldier
var options: Array[Dictionary] = []
var ctx := {}
var target: Node
var point := Vector3.INF
var highlight := 0
var _held := -1.0
var _open := false
var _pick := Vector2.ZERO
var _prompt: Label
var _prompt_left := 0.0
var _buttons: Array[Label] = []


func _init(p_player: Soldier = null) -> void:
	player = p_player


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = UiKit.hud_label()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 40
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_prompt)


func is_open() -> bool:
	return _open


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _held >= 0.0:
		_held += delta
		if not _open and _held >= HOLD_S:
			_open_radial()
	_prompt_left -= delta
	if _prompt_left <= 0.0 and not _open:
		_prompt_left = PROMPT_S
		look()
		var d: Dictionary = options[0] if not options.is_empty() and String(ctx.get("kind", "ground")) != "ground" else {}
		_prompt.text = "[%s] %s%s" % [GameSettings.binding_name(GameSettings.key_for(ACTION)), d.label, _target_name()] if not d.is_empty() else ""


## PlayerInput hands the event here (after the command menu); true when it was ours.
func handle(event: InputEvent) -> bool:
	if not event.is_action(ACTION) and not (_open and event is InputEventMouseMotion):
		return false
	if _open and event is InputEventMouseMotion:
		_pick += (event as InputEventMouseMotion).relative
		if _pick.length() > 30.0 and options.size() > 0:
			var a := fposmod(_pick.angle() + PI * 0.5, TAU)
			highlight = int(round(a / TAU * options.size())) % options.size()
			_restyle()
		return true
	if event.is_action_pressed(ACTION):
		look()
		_held = 0.0
		return true
	if event.is_action_released(ACTION) and _held >= 0.0:
		var pick := highlight if _open else 0
		_held = -1.0
		_close_radial()
		if pick < options.size():
			run(options[pick])
		return true
	return false


## Works out what's under the crosshair: ctx (ContextResolver's), target, point and options.
func look() -> void:
	ctx = {"kind": "ground"}
	target = null
	point = Vector3.INF
	var cam := player.camera
	if cam == null or not cam.is_inside_tree():
		return
	if is_instance_valid(player.vehicle):
		ctx = {"kind": "crew", "seat_role": "driver" if player.vehicle.driver() == player else "gunner"}
		options = ContextResolver.resolve(ctx)
		return
	var from := cam.global_position
	var to := from - cam.global_basis.z * LOOK_M
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	q.collision_mask = 0xFFFFFFFF
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		options = ContextResolver.resolve(ctx)
		return
	point = hit.position
	var n: Node = hit.collider
	while n and not (n is Soldier or n is Vehicle):
		n = n.get_parent()
	ctx = classify(player, n, point)
	target = n
	ctx["contact"] = Soldier._now() - player.threat_time < 10.0
	ctx["selected"] = "gun_team" if _has_gun_loads() else ""
	options = ContextResolver.resolve(ctx)


## What `n` (a Soldier, a Vehicle or null for the ground at `at`) is to `me`, as ContextResolver's ctx.
static func classify(me: Soldier, n: Node, at: Vector3) -> Dictionary:
	if n is Soldier:
		var s := n as Soldier
		if s.faction != me.faction and not Person.is_noncombatant(s):
			return {"kind": "enemy"}
		if not s.vitals.is_up():
			return {"kind": "casualty"}
		if String(s.hc_id).begins_with("hc_") or String(s.hc_id).begins_with("dev"):
			return {"kind": "hero_squad", "hc_id": String(s.hc_id)}
		if s.iff in [&"allied", &"rebel"] or String(s.hc_id).begins_with("allied"):
			return {"kind": "allied_unit", "hc_id": String(s.hc_id)}
		if s.is_ai() and Squad.is_squadmate(s):
			return {"kind": "squadmate"}
		return {"kind": "ground"}
	if n is Vehicle:
		var v := n as Vehicle
		var d := v.driver()
		if d and d.iff in [&"allied", &"rebel"]:
			return {"kind": "allied_armour"}
		return {"kind": "our_vehicle"}
	var lvl := MapNodes.level_of(me)
	if lvl is Node3D:
		var b := Buildings.nearest(lvl as Node3D, at, 6.0)
		if not b.is_empty():
			return {"kind": "building", "doors": ["kick", "open", "flash"]}
	return {"kind": "ground"}


## Carries out option `o` (ContextResolver's), and notes it as recently used.
func run(o: Dictionary) -> void:
	ContextResolver.used(String(ctx.get("kind", "ground")), String(o.id))
	var at := point if point.is_finite() else player.global_position
	var names := PackedStringArray()
	if String(o.get("names", "")) == "target" and target is Soldier:
		names.append(String((target as Soldier).name))
	match String(o.do):
		"squad":
			var cmd := String(o.cmd)
			if bool(o.get("aim", false)) and target is Node3D:
				var mid := Viewshed.bearing_of(Vector2((target as Node3D).global_position.x - player.global_position.x, (target as Node3D).global_position.z - player.global_position.z))
				cmd = "wt_setup:%.0f:%.0f" % [fposmod(mid - 30.0, 360.0), fposmod(mid + 30.0, 360.0)]
				at = player.global_position
			player._server_squad_command.rpc_id(1, cmd, at, names)
			_flash(o.label)
		"hc":
			var hc := HighCommand.of(player)
			if hc and hc.is_commander():
				MapCommandLayer.send(hc, String(ctx.get("hc_id", "")), String(o.verb), Vector2(player.global_position.x, player.global_position.z))
				_flash("%s: %s on you" % [String(ctx.get("hc_id", "")), o.label])
			else:
				_flash("Only the commander orders the squads")
		"request":
			var broker := RequestBroker.of(player)
			if broker:
				broker.request(String(o.kind), at, String(ctx.get("hc_id", "")), "")
				_flash(o.label)
		"menu":
			if player._hud and player._hud.command_menu:
				player._hud.command_menu.open()
		_:
			_local(String(o.get("what", "")), at)


func _local(what: String, at: Vector3) -> void:
	var t3 := target as Node3D
	match what:
		"treat":
			if player.player_input and player.player_input.medical_menu and target:
				player.player_input.medical_menu.open(target)
		"carry":
			if target:
				player._server_carry_body.rpc_id(1, target.get_path())
		"tag":
			if target:
				player._server_tag_enemy.rpc_id(1, String(target.name))
		"target":
			if target:
				player._server_squad_command.rpc_id(1, "target:%s" % target.name, at, PackedStringArray())
		"report", "mark":
			var marks := MapNodes.markers(player)
			if marks:
				marks.request_add("enemy" if what == "report" else "point", PackedVector2Array([Vector2(at.x, at.z)]), "contact" if what == "report" else "", "red" if what == "report" else "black")
		"loot":
			if player._hud and target:
				player._hud.open_loot(target)
		"get_in", "drive":
			if t3 is Vehicle:
				(t3 as Vehicle).request_enter.rpc_id(1, 0 if what == "drive" else -1)
		"take_gun":
			player._server_squad_command.rpc_id(1, "take_gun", at, PackedStringArray())
		"bail":
			if is_instance_valid(player.vehicle):
				player.vehicle.request_exit.rpc_id(1)
		"fire_support":
			if player._hud and player._hud.command_menu:
				player._hud.command_menu.open()  # (fire support is on the Support page)
		_:
			_flash("Not yet: %s" % what.replace("_", " "))  # (the crew wheel's orders come with A3's crews)
			return
	_flash(what.replace("_", " ").capitalize())


func _flash(text: String) -> void:
	if player.player_input:
		player.player_input.flash(text)


func _target_name() -> String:
	if target is Soldier:
		var s := target as Soldier
		return ": %s" % (s.person_name if s.person_name != "" else String(s.name))
	return ""


func _has_gun_loads() -> bool:
	for s: Soldier in MapNodes.squad_ai(player):
		if s.inventory and StaticWeapons.kit_of_load(s.inventory.hands) != "":
			return true
	return false


# --- The radial ----------------------------------------------------------------------------------

func _open_radial() -> void:
	_open = true
	_pick = Vector2.ZERO
	highlight = 0
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	var centre := size * 0.5
	for i in options.size():
		var a := TAU * float(i) / maxf(options.size(), 1) - PI * 0.5
		var label := Label.new()
		label.text = String(options[i].label)
		label.add_theme_font_size_override(&"font_size", UiKit.FONT_SMALL)
		label.position = centre + Vector2(cos(a), sin(a)) * RADIUS_PX - Vector2(60, 10)
		label.custom_minimum_size = Vector2(120, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)
		_buttons.append(label)
	_restyle()
	_prompt.text = "Move the mouse to pick, let go to do it"


func _close_radial() -> void:
	_open = false
	for b in _buttons:
		b.queue_free()
	_buttons.clear()


func _restyle() -> void:
	for i in _buttons.size():
		_buttons[i].modulate = Color(1.0, 0.9, 0.3) if i == highlight else Color(1, 1, 1, 0.8)
