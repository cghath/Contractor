class_name LauncherSight
extends Control
## The local player's launcher (wave 5, V2): the sight drawn over the view while aiming (a
## placeholder iron sight or optic with range marks for the loaded round's drop, or the
## Javelin's seeker), the Javelin's lock, the attack mode, and the fire and reload requests
## PlayerInput hands over when the active weapon is a launcher (Launchers.request_fire and
## request_reload; the host decides). One per local player, on the HUD.
##
## Javelin: aim (RMB) and hold the seeker on a vehicle for the CLU's lock_s (proposed 2.5 s)
## to lock; Fire sends the locked vehicle with the shot. F switches top and direct attack
## (NLAW: overfly top attack and direct attack).

const RANGE_MARKS: Array[float] = [100.0, 200.0, 300.0, 400.0]
const SEEKER_TINT := Color(0.05, 0.16, 0.05, 0.55)
const SEEKER_INK := Color(0.45, 1.0, 0.45, 0.9)
const SIGHT_INK := Color(0.05, 0.05, 0.04, 0.85)
## First-person: where the tube sits in the view model (from PlayerInput's hip view): on
## the firing shoulder, beside the eye.
const VIEW_OFFSET := Vector3(-0.02, 0.06, 0.32)

var body: Soldier
## Attack mode picked with F, per launcher type (it defaults to the launcher's first).
var modes := {}
## Javelin lock: the vehicle in the seeker, how long it has been held there, and the lock.
var seeking: Node3D
var lock_t := 0.0
var locked: Node3D


func _init(s: Soldier) -> void:
	body = s
	name = "LauncherSight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The local player's sight (null for anyone else).
static func of(s: Soldier) -> LauncherSight:
	var hud: Node = s.player_input.hud if s and s.player_input else null
	return hud.get_node_or_null(^"LauncherSight") as LauncherSight if hud else null


## The first-person launcher for the view model (PlayerInput._update_view_model).
static func view_node(item: ItemData) -> Node3D:
	var node := LauncherRig.make_model(item, 1)
	node.position = VIEW_OFFSET
	return node


## The attack mode for the launcher `item` ("" if it has none).
func mode_for(item: ItemData) -> String:
	var all := Launchers.modes(item)
	if all.is_empty():
		return ""
	var m: String = modes.get(String(item.id), all[0])
	return m if m in all else all[0]


func _launcher() -> ItemData:
	var item := body.active_weapon() if body.active_slot == Launchers.SLOT else null
	return item if Launchers.is_launcher(item) else null


## PlayerInput: the active weapon is a launcher. F switches the attack mode, a press of Fire
## fires (one round, then it needs a reload or it's spent).
func try_fire() -> void:
	var item := _launcher()
	if item == null:
		return
	if Input.is_action_just_pressed(&"fire_mode") and Launchers.modes(item).size() > 1:
		var all := Launchers.modes(item)
		modes[String(item.id)] = all[(all.find(mode_for(item)) + 1) % all.size()]
		_flash({"top": "Top attack", "direct": "Direct attack", "ota": "Overfly top attack", "da": "Direct attack"}.get(mode_for(item), mode_for(item)))
	if not Input.is_action_just_pressed(&"fire"):
		return
	var now := Soldier._now()
	if now < body._busy_until:
		return
	var w := Launchers.loaded_of(body)
	if w == &"":
		_flash("Empty - R to load" if not Launchers.carried_rounds(body).is_empty() else "No rounds")
		return
	var target_path := NodePath()
	if String(Warheads.data(w).get("guidance", "")) == "javelin":
		if not is_instance_valid(locked):
			_flash("No lock - hold the seeker on a vehicle")
			return
		target_path = (CompoundLevel.current(body) as Node).get_path_to(locked)
	elif String(Warheads.data(w).get("guidance", "")) == "nlaw" and is_instance_valid(seeking):
		target_path = (CompoundLevel.current(body) as Node).get_path_to(seeking)
	var launchers := Launchers.of(body)
	if launchers == null:
		return
	body._busy_until = now + Launchers.FIRE_BUSY_S
	launchers.request_fire.rpc_id(1, body.camera.global_position, -body.camera.global_basis.z, mode_for(item), target_path)
	body._kick(item)
	if body.player_input:
		body.player_input.shake(0.35)
	locked = null
	lock_t = 0.0


## PlayerInput: R with a launcher up: load the next round (or swap kinds).
func try_reload() -> void:
	var item := _launcher()
	var now := Soldier._now()
	if item == null or now < body._busy_until or body.inventory.hands != &"" or not body.vitals.is_up():
		return
	if item.stats.get("disposable", false):
		_flash("Single shot: %s" % ("ready" if Launchers.loaded_of(body) != &"" else "spent"))
		return
	var choice := Launchers.next_round(body)
	if choice == &"":
		var w := Launchers.loaded_of(body)
		_flash("Loaded: %s" % Launchers.warhead_name(w) if w != &"" else "No rounds")
		return
	var launchers := Launchers.of(body)
	if launchers == null:
		return
	body._busy_until = now + float(item.stats.get("reload_s", 4.0)) * body.vitals.reload_mult()
	body.is_reloading = true
	launchers.request_reload.rpc_id(1, choice)
	_flash("Loading %s" % ItemDB.get_item(choice).name)


func _flash(text: String) -> void:
	if body.player_input:
		body.player_input.flash(text)


func _physics_process(delta: float) -> void:
	var item := _launcher()
	var seeker := item != null and String(item.stats.get("sight", "")) == "seeker"
	var nlaw := item != null and Launchers.loaded_of(body) != &"" and String(Warheads.data(Launchers.loaded_of(body)).get("guidance", "")) == "nlaw"
	if item == null or not body.is_aiming or not (seeker or nlaw):
		seeking = null
		lock_t = 0.0
		locked = null
	else:
		var found := vehicle_in_sight(body, float(item.stats.get("lock_range_m", 1000.0)))
		if found != seeking:
			seeking = found
			lock_t = 0.0
			if locked != found:
				locked = null
		elif found != null:
			lock_t += delta
			if seeker and lock_t >= float(item.stats.get("lock_s", 2.5)) and locked != found:
				locked = found
				_flash("Lock")
	queue_redraw()


## The vehicle (not a wreck) nearest the middle of `s`'s view within Launchers.LOCK_CONE_DEG
## and `range_m`, in sight; null for none. What a Javelin seeker (or an NLAW's tracking) holds.
static func vehicle_in_sight(s: Soldier, range_m: float) -> Vehicle:
	var eye := s.camera.global_position
	var forward := -s.camera.global_basis.z
	var best: Vehicle = null
	var best_angle := Launchers.LOCK_CONE_DEG * 0.8
	for n in s.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked:
			continue
		var centre := Launchers.hull_box(v).get_center()
		var to := centre - eye
		if to.length() > range_m:
			continue
		var angle := rad_to_deg(forward.angle_to(to.normalized()))
		if angle >= best_angle:
			continue
		var hit := s.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, centre, 1, [s.get_rid()]))
		if not hit.is_empty() and eye.distance_to(hit.position) < to.length() * 0.95:
			continue
		best = v
		best_angle = angle
	return best


func _draw() -> void:
	var item := _launcher()
	if item == null:
		return
	var size := get_viewport_rect().size
	var centre := size * 0.5
	var font := ThemeDB.fallback_font
	var w := Launchers.loaded_of(body)
	var status := "%s  %s%s" % [item.name, Launchers.warhead_name(w) if w != &"" else ("spent" if item.stats.get("disposable", false) else "empty"),
		("  [%s]" % mode_for(item).to_upper()) if mode_for(item) != "" else ""]
	draw_string(font, Vector2(centre.x - 200.0, size.y - 40.0), status, HORIZONTAL_ALIGNMENT_CENTER, 400.0, 14, Color(1, 1, 1, 0.75))
	if not body.is_aiming:
		return
	if String(item.stats.get("sight", "")) == "seeker":
		_draw_seeker(item, size, centre, font)
		return
	# Iron sight or optic: a post and range marks below it for the loaded round's drop.
	draw_line(centre + Vector2(-60, 0), centre + Vector2(-12, 0), SIGHT_INK, 2.0)
	draw_line(centre + Vector2(12, 0), centre + Vector2(60, 0), SIGHT_INK, 2.0)
	draw_line(centre + Vector2(0, 6), centre + Vector2(0, 40), SIGHT_INK, 2.0)
	if w == &"" or String(Warheads.data(w).get("guidance", "")) != "":
		if is_instance_valid(seeking):
			draw_rect(Rect2(centre - Vector2(24, 18), Vector2(48, 36)), SEEKER_INK, false, 1.5)  # NLAW: tracking
		return
	var half_fov := deg_to_rad(body.camera.fov * 0.5)
	for r in RANGE_MARKS:
		var drop := float(LauncherProjectile.drop_at(w, r).drop)
		var y := tan(atan2(drop, r)) / tan(half_fov) * centre.y
		if y > centre.y * 0.9:
			break
		draw_line(centre + Vector2(-10, y), centre + Vector2(10, y), SIGHT_INK, 1.5)
		draw_string(font, centre + Vector2(14, y + 5), str(int(r)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SIGHT_INK)


func _draw_seeker(item: ItemData, size: Vector2, centre: Vector2, font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEEKER_TINT)
	var gate := Vector2(80, 56)
	draw_rect(Rect2(centre - gate * 0.5, gate), SEEKER_INK, false, 1.5)
	draw_line(centre + Vector2(-size.x * 0.3, 0), centre + Vector2(-gate.x * 0.6, 0), SEEKER_INK, 1.0)
	draw_line(centre + Vector2(gate.x * 0.6, 0), centre + Vector2(size.x * 0.3, 0), SEEKER_INK, 1.0)
	var text := "SEEK"
	if is_instance_valid(locked):
		text = "LOCK"
		draw_rect(Rect2(centre - gate * 0.3, gate * 0.6), SEEKER_INK, false, 3.0)
	elif is_instance_valid(seeking):
		var share := clampf(lock_t / float(item.stats.get("lock_s", 2.5)), 0.0, 1.0)
		draw_rect(Rect2(centre + Vector2(-gate.x * 0.5, gate.y * 0.5 + 8), Vector2(gate.x * share, 4)), SEEKER_INK)
		text = "TRACK"
	draw_string(font, centre + Vector2(-gate.x * 0.5, -gate.y * 0.5 - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SEEKER_INK)
	draw_string(font, centre + Vector2(gate.x * 0.5 - 40, -gate.y * 0.5 - 8), mode_for(item).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SEEKER_INK)
