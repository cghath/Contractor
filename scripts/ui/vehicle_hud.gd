class_name VehicleHud
extends Control
## The armoured vehicle HUDs (combined arms A5, cg_brief queue item 2.4; docs/combined_arms.md
## 2.12, F-252), for the local player in any seat of a vehicle with modules (the Abrams, Bradley,
## AAV, M-ATV, MaxxPro). It takes the place of the text strip (Vehicle.readout_parts in
## Hud.show_vehicle, which soft vehicles, helicopters and static guns keep), in the HUD's zones:
##
## - The compass strip (top): the hull's heading (a caret), the turret's (a bracket) and the
##   bearing the last hit came from (a red tick, HIT_TICK_S): Compass.vehicle_marks.
## - The centre, in the chase view: where the gun actually points (a ring), apart from your aim
##   (the HUD's crosshair), so the turret's lag reads at a glance. In every view, a blue chevron
##   over each friendly vehicle on the Blue Force Tracker (its radio working: SideIntel.radio_ok)
##   in view (B5's "blue chevron in the sight": in the gunner's sight too).
## - The vehicle panel (bottom centre, under the radio): the doll (top-down: modules white,
##   yellow damaged, red destroyed; tracks or wheels; ERA tiles, grey once fired; crew pips with
##   role letters at their seats), the vehicle and seat with a short damage word, the alerts
##   (only when true), the weapons (Vehicle's readout lines: main gun, loader, feeds, the lase),
##   the round selector (every round type, the loaded one bracketed, the next named, the reload
##   bar), the crew line (names, roles, state from Vitals, "you"), the drive line (speed, gear,
##   fuel, engine and transmission) and the keys (the player's own bindings). It fits the room
##   the HUD's bottom-centre zone has (fit()): on a small window the keys go first, then the crew
##   names, then the drive line (a driver keeps it), then the selector.
## - First person: the gunner's and commander's sights keep VehicleSightOverlay (restyled: crew
##   pips and the damage word, the round selector's look); buttoned up in a hatch seat the vision
##   blocks or the driver's periscopes (VehicleVision: this draws the slit's mask and frame, the
##   driver's turret arrow, the night channel's tube look with the rest of the HUD dimmed); the
##   loader turned in sees the bustle doors and a large round selector under his periscope.
## - Hearing: buttoned up (a closed seat) outside sounds are muffled (Sfx.set_muffled).
## Local only. Readouts are gathered GATHER_S apart; the markers each frame. Budget BUDGET_MS
## (9.3: "HUD under 0.3 ms"; the vehiclehud suite measures it). Numbers Proposed.

const NODE_NAME := &"VehicleHud"
const BUDGET_MS := 0.3
const GATHER_S := 0.1
## Hidden this long after its vehicle last showed it (it left the seat).
const SHOW_S := 0.5
const HIT_TICK_S := 10.0
## Blue Force Tracker chevrons out to this far (m).
const BFT_RANGE_M := 2500.0
const BFT_COLOUR := Color(0.38, 0.62, 1.0, 0.95)
const GUN_COLOUR := Color(1.0, 0.8, 0.42, 0.95)
const STATE_COLOURS: Array[Color] = [Color(0.92, 0.93, 0.89), Color(0.98, 0.8, 0.28), Color(0.9, 0.22, 0.18)]
const CREW_COLOURS := {"up": Color(0.5, 0.85, 0.45), "wounded": Color(1.0, 0.6, 0.2), "down": Color(0.9, 0.22, 0.18),
	"dead": Color(0.55, 0.1, 0.1), "empty": Color(0.5, 0.52, 0.48)}
const CREW_MARKS := {"up": "*", "wounded": "+", "down": "x", "dead": "x", "empty": "-"}
const ROLE_LETTERS := {&"driver": "D", &"gunner": "G", &"commander": "C", &"loader": "L", &"pilot": "P", &"passenger": "R"}
## The crew jobs whose absence makes the vehicle short-crewed (2.5.1).
const JOBS: Array[StringName] = [&"driver", &"gunner", &"loader"]
## The doll's size (logical px) and on a small window.
const DOLL := Vector2(78.0, 112.0)
const DOLL_SMALL := Vector2(52.0, 76.0)
## Rollover risk at this share of the static tip angle (2.8.3: A6's real centres of mass and
## tracks, VehicleDrive.tip_deg; data/vehicle_drive.json rollover.hud_share).
const ROLLOVER_SHARE := 0.7
## A6: the BRIDGE MLC line for a span this far ahead (m) or under it.
const BRIDGE_WARN_M := 40.0
## A launch seen by the crew: a rocket or missile within this far heading within this cone of us.
const MISSILE_WARN_M := 2500.0
const MISSILE_CONE_DEG := 10.0
## The rest of the HUD under the driver's night channel.
const NIGHT_DIM := 0.5
const SLIT_DARK := Color(0.0, 0.0, 0.0, 0.94)
const SLIT_FRAME := Color(0.28, 0.3, 0.26, 1.0)

var hud: Hud
var vehicle: Vehicle
var me: Soldier
var seat := -1
## The last gathered view (gather()): what the panel and the drawing show.
var view: Dictionary = {}
## "chase", "first", "sight", "vision" (blocks, periscopes) or "" (hidden).
var mode := ""
var panel: PanelContainer
var doll: Doll
var _rows: VBoxContainer
var _title: Label
var _alerts: Label
var _weapon: Label
var _selector: Label
var _crew: Label
var _drive: Label
var _keys: Label
var _night: ColorRect
var _night_material: ShaderMaterial
var _left := 0.0
var _gather_left := 0.0
var _small := false
## This frame's own cost, and the average (ms; tests and the budget).
var cost_ms := 0.0
var cost_avg_ms := 0.0
var _cost_n := 0
## Doll layouts by model (static: the data doesn't change).
static var _dolls := {}


func _init(p_hud: Hud = null) -> void:
	hud = p_hud
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_night = ColorRect.new()
	_night.name = "NightChannel"
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_material = NvgView._make_material(NvgView.screen_shader_code())  # (its MEAN too: left in, the shader failed to compile)
	_night_material.set_shader_parameter(&"tube", 8.0)  # (the whole glass: the slit masks it)
	_night_material.set_shader_parameter(&"outside", 1.0)
	_night.material = _night_material
	_night.visible = false
	add_child(_night)
	panel = UiKit.panel()
	panel.name = "VehiclePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	panel.add_child(row)
	doll = Doll.new(self)
	row.add_child(doll)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 0)
	row.add_child(_rows)
	_title = _row(&"HudLabel")
	_alerts = _row(&"HudSmallWarnLabel")
	_weapon = _row(&"HudSmallLabel")
	_selector = _row(&"HudSmallLabel")
	_crew = _row(&"HudSmallLabel")
	_drive = _row(&"HudSmallLabel")
	_keys = _row(&"HudSmallLabel")
	_keys.modulate = Color(1, 1, 1, 0.85)


func _row(variation: StringName) -> Label:
	var l := UiKit.hud_label("", variation)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 0.0
	_rows.add_child(l)
	return l


func _ready() -> void:
	if hud and panel.get_parent() == null:
		hud.zone_bottom_centre.add_child(panel)  # under the radio, the strip's place
		hud.vehicle_hud = self


func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.get_parent() != self:
		panel.queue_free()
	if hud and hud.vehicle_hud == self:
		hud.vehicle_hud = null
	if is_instance_valid(Sfx) and Sfx.muffled and me != null:
		Sfx.set_muffled(false)


# --- The entry points -----------------------------------------------------------------------------

## Whether `v` gets these HUDs: a vehicle whose damage goes through authored modules (armour).
static func applies(v: Vehicle) -> bool:
	return v != null and v.modules != null and v.modules.authored


## The local player `s`'s VehicleHud, or null.
static func of(s: Soldier) -> VehicleHud:
	if s == null or not is_instance_valid(s) or s.player_input == null or s.player_input.hud == null:
		return null
	return s.player_input.hud.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleHud


## Every frame from Vehicle._local_controls while the local player `s` sits in seat `p_seat` of
## `v`: shows these HUDs (made the first time), the vision blocks and the muffling. False for a
## vehicle without them (the strip shows).
static func local_step(v: Vehicle, s: Soldier, p_seat: int, free: bool) -> bool:
	if not applies(v):
		return false
	var h := s.player_input.hud
	var vh := h.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleHud
	if vh == null:
		vh = VehicleHud.new(h)
		h.add_child(vh)
		h.move_child(vh, 1)  # over the 3D view's effects, under the rest of the HUD
	VehicleVision.local_step(v, s, p_seat, free)
	vh.attach(v, s, p_seat)
	Sfx.set_muffled(muffled_for(v, p_seat))
	return true


## Whether seat `p_seat` of `v` is closed in (outside sounds muffled): not an open seat, not
## turned out, not out of the roof hatch (Vehicle.seat_open).
static func muffled_for(v: Vehicle, p_seat: int) -> bool:
	return applies(v) and p_seat >= 0 and not v.seat_open(p_seat)


func attach(v: Vehicle, s: Soldier, p_seat: int) -> void:
	if v != vehicle or p_seat != seat:
		_gather_left = 0.0
	vehicle = v
	me = s
	seat = p_seat
	_left = SHOW_S


## Hides everything and lets go (the player left the seat).
func detach() -> void:
	vehicle = null
	seat = -1
	mode = ""
	view = {}
	panel.visible = false
	_night.visible = false
	if hud and hud.compass:
		hud.compass.vehicle_marks = []
	modulate.a = 1.0
	panel.modulate.a = 1.0
	Sfx.set_muffled(false)
	queue_redraw()


# --- Each frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if vehicle == null:
		return
	_left -= delta
	if _left <= 0.0 or not is_instance_valid(vehicle) or me == null or not is_instance_valid(me) or vehicle.seat_of(me) != seat:
		detach()
		return
	var was := mode
	mode = mode_of(me)
	_gather_left -= delta
	if mode != was:
		_gather_left = 0.0  # (the sight up or down, the view switched: the panel at once)
	if _gather_left <= 0.0:
		_gather_left = GATHER_S
		view = gather(vehicle, me, seat)
		show_view(view)
	_markers()
	queue_redraw()
	cost_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_cost_n += 1
	cost_avg_ms += (cost_ms - cost_avg_ms) / minf(float(_cost_n), 120.0)


## The view the local player `s` has now: "sight", "vision", "chase" or "first".
static func mode_of(s: Soldier) -> String:
	if VehicleSight.up_for(s):
		return "sight"
	if VehicleVision.up_for(s):
		return "vision"
	return "chase" if VehicleCamera.chase else "first"


## The per-frame parts: the compass marks, the gun's ring, the BFT chevrons, the night channel.
func _markers() -> void:
	var marks: Array = [[float(view.get("hull_deg", 0.0)), "hull"]]
	if view.has("turret_deg"):
		marks.append([float(view.turret_deg), "turret"])
	if view.has("hit_deg"):
		marks.append([float(view.hit_deg), "hit"])
	if hud and hud.compass:
		hud.compass.vehicle_marks = marks
	var vv := VehicleVision.of(me)
	var night := mode == "vision" and vv != null and vv.mode() == "night"
	_night.visible = night
	if night:
		var slit := slit_rect(vv, size)
		_night.position = slit.position
		_night.size = slit.size
		_night_material.set_shader_parameter(&"aspect", slit.size.x / maxf(slit.size.y, 1.0))
	panel.modulate.a = NIGHT_DIM if night else 1.0


# --- Gathering (every peer reads the same replicated state) --------------------------------------

## Everything the HUD shows for local player `s` in seat `p_seat` of `v`: JSON-like, so tests and
## the ui_test can hand show_view() one of their own.
static func gather(v: Vehicle, s: Soldier, p_seat: int) -> Dictionary:
	var out := {"title": "%s, %s" % [v.display_name(), v.seat_name(p_seat)], "seat": p_seat, "kind": String(v.seat_kind(p_seat)),
		"damage": damage_word(v), "alerts": alerts(v, p_seat), "crew": crew_pips(v, s), "hull_deg": bearing(-v.global_basis.z)}
	if v.turret:
		out["turret_deg"] = bearing(v.global_basis * (Basis(Vector3.UP, v.turret.yaw) * Vector3.FORWARD))
	var hit := last_hit(v)
	if not hit.is_empty() and float(hit.age) <= HIT_TICK_S:
		out["hit_deg"] = float(hit.from_deg)
	var lines: PackedStringArray = []
	for part: Dictionary in v.readout_parts(p_seat):
		var st := StringName(part.get("style", &""))
		var text := String(part.text)
		if st == &"key" or text == out.title or text.begins_with("Fuel ") or text.ends_with(" km/h") or text == "ON FIRE: GET OUT":
			continue  # (the keys, the title, fuel and speed have their own lines; the fire's an alert)
		lines.append(text)
	out["weapons"] = lines
	out["selector"] = selector(v, p_seat)
	out["drive"] = drive_line(v)
	out["keys"] = keys(v, p_seat)
	return out


## A bearing (0 north, clockwise, degrees) of world direction `d`, as Compass.bearing_of.
static func bearing(d: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


## The vehicle's crew, a pip each: [{"seat", "letter", "name", "state" (HitReport.crew_state),
## "you"}], the jobs first in seat order, then "riders" as one entry ({"letter": "R", "n", "of"}).
static func crew_pips(v: Vehicle, s: Soldier = null) -> Array:
	var out: Array = []
	var riders := 0
	var rider_seats := 0
	for i in (v.spec.get("seats", []) as Array).size():
		var k := v.seat_kind(i)
		var man := v.occupant(i)
		if k == Vehicle.PASSENGER:
			rider_seats += 1
			if man:
				riders += 1
			continue
		out.append({"seat": i, "letter": String(ROLE_LETTERS.get(k, "?")), "role": String(k), "name": _surname(man),
			"state": HitReport.crew_state(man), "you": man != null and man == s})
	if rider_seats > 0:
		out.append({"seat": -1, "letter": "R", "role": "riders", "n": riders, "of": rider_seats, "state": "up" if riders > 0 else "empty", "you": false})
	return out


static func _surname(s: Soldier) -> String:
	if s == null:
		return ""
	var n := String(s.display_name()) if s.has_method(&"display_name") else String(s.name)
	return n.get_slice(" ", n.get_slice_count(" ") - 1)


## The short damage word (2.12.2's "DMG none"): none, damaged, mobility, firepower, knocked out,
## burning, wrecked.
static func damage_word(v: Vehicle) -> String:
	if v.wrecked:
		return "wrecked"
	if v.is_burning():
		return "burning"
	var k := v.modules.kill if v.modules else 0
	if k & VehicleModules.KNOCKED_OUT:
		return "knocked out"
	if k & VehicleModules.MOBILITY:
		return "mobility"
	if k & VehicleModules.FIREPOWER:
		return "firepower"
	if v.modules:
		for i in v.modules.health.size():
			var m: Dictionary = v.modules.mods[i]
			if float(m.hp) > 0.0 and not bool(m.crew) and v.modules.health[i] <= VehicleModules.DAMAGED_SHARE + 0.0001:
				return "damaged"
	return "none"


## The alerts that are true now (2.12.1): ON FIRE, TRACK THROWN, ROLLOVER RISK (or ROLLED OVER),
## FORD depth over the model's fording depth (or AFLOAT, FLOODING, FLOODED, STALLED), BRIDGE MLC,
## BOGGED, MISSILE LAUNCH, SHORT-CREWED, NO RADIO. A6 (cg_brief queue item 2.7) gave them their
## real numbers: VehicleDrive's tip angle, ford depth and flooding, ZoneBridges' load classes.
static func alerts(v: Vehicle, p_seat: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if v.is_burning():
		out.append("ON FIRE: GET OUT")
	var m := v.modules
	if m:
		for i in m.mods.size():
			if String(m.mods[i].kind) == "track" and m.health[i] <= 0.0:
				out.append("TRACK THROWN")
				break
	var drive := v.drive
	var tip := tip_deg(v)
	var roll := VehicleDrive.roll_deg(v)
	if drive and drive.is_rolled():
		out.append("ROLLED OVER: NEEDS A TOW" if not drive.is_righting() else "RIGHTING")
	elif tip > 0.0 and roll >= tip * ROLLOVER_SHARE:
		out.append("ROLLOVER RISK %d / %d deg" % [roundi(roll), roundi(tip)])
	if drive:
		var depth := VehicleDrive.ford_depth(v)
		if drive.is_flooded():
			out.append("FLOODED: GET OUT")
		elif VehicleDrive.swims(v.spec):
			if AavWater.afloat(v):
				out.append("AFLOAT")
			if drive.flood_share() > 0.0:
				out.append("FLOODING %d%%" % roundi(drive.flood_share() * 100.0))
		elif depth > VehicleDrive.WET_M:
			out.append("FORD %.1f / %.1f m" % [depth, VehicleDrive.ford_m(v.spec)])
		if drive.is_stalled():
			out.append("STALLED: TOO DEEP")
		if drive.is_bogged():
			out.append("BOGGED: NEEDS A TOW")
		var line := bridge_line(v)
		if line != "":
			out.append(line)
	if missile_seen(v):
		out.append("MISSILE LAUNCH")
	if short_crewed(v):
		out.append("SHORT-CREWED")
	if bool(v.get_meta(&"radio_down", false)):
		out.append("NO RADIO")
	if not v.can_drive() and v.seat_kind(p_seat) == Vehicle.DRIVER and not v.is_burning():
		out.append("WON'T DRIVE")
	return out


## The static tip angle (degrees): half the track width over the centre of mass's height
## (VehicleDrive.tip_deg: the model's real ones, F-257).
static func tip_deg(v: Vehicle) -> float:
	return VehicleDrive.tip_deg(v.spec) if v.kind in [Vehicle.WHEELED, Vehicle.TRACKED] else 0.0


## 2.8.5's warning (F-255): the span ahead (within BRIDGE_WARN_M along the way it's going) or
## under it, "BRIDGE MLC 40", with ": TOO HEAVY" when the vehicle's class is over the span's.
static func bridge_line(v: Vehicle) -> String:
	var b := TerrainRoute.bridges_of(v)
	if b == null or b.bridges.is_empty():
		return ""
	var dir := -v.global_basis.z * (-1.0 if v.forward_speed() < -0.3 else 1.0)
	var next := b.next_span(v.global_position + Vector3.UP * 0.3, dir, BRIDGE_WARN_M)
	if next.is_empty():
		return ""
	var cls := float(next.mlc)
	return "BRIDGE MLC %d%s" % [floori(cls + 0.001), ": TOO HEAVY" if float(VehicleDrive.mlc(v)) > cls else ""]


## Whether a rocket or missile is in flight towards `v` (within MISSILE_WARN_M, heading within
## MISSILE_CONE_DEG of it): what a crew would see launched at them.
static func missile_seen(v: Vehicle) -> bool:
	var lvl := v.level()
	var holder: Node = lvl.get_node_or_null(^"Launchers") if lvl else null
	if holder == null:
		return false
	for n in holder.get_children():
		var p := n as LauncherProjectile
		if p == null or not p.is_inside_tree():
			continue
		var to := v.global_position - p.global_position
		var d := to.length()
		var fly := -p.global_basis.z
		if d > 0.5 and d <= MISSILE_WARN_M and rad_to_deg(fly.angle_to(to / d)) <= MISSILE_CONE_DEG:
			return true
	return false


## Whether a crew job (driver, gunner, loader; 2.5.1) has nobody able in it.
static func short_crewed(v: Vehicle) -> bool:
	for i in (v.spec.get("seats", []) as Array).size():
		if v.seat_kind(i) in JOBS:
			var man := v.occupant(i)
			if man == null or not man.vitals.is_up():
				return true
	return false


## The last hit on `v` this peer has: {"report", "age" (s), "from_deg" (the bearing it came from)} or {}.
static func last_hit(v: Vehicle) -> Dictionary:
	if v.modules == null or v.modules.events.is_empty():
		return {}
	var ev: Dictionary = v.modules.events.back()
	var at := float(v.modules.event_times.back()) if not v.modules.event_times.is_empty() else -INF
	var d: Array = ev.get("d", [0.0, 0.0, -1.0])
	var world := v.global_basis * Vector3(float(d[0]), float(d[1]), float(d[2]))
	return {"event": ev, "age": Soldier._now() - at, "from_deg": bearing(-world)}


## The round selector for the seat's main gun or autocannon: [{"name", "n", "loaded", "next"}],
## plus "reload": [share done (0..1, -1 none), seconds left]. {} with no such gun.
static func selector(v: Vehicle, p_seat: int) -> Dictionary:
	var w := v.weapons
	if w == null:
		return {}
	for m: Dictionary in w.mounts:
		var mine := int(m.seat) == p_seat or int(m.commander_seat) == p_seat or int(m.loader_seat) == p_seat
		if not mine:
			continue
		var vw := w._view(String(m.id))
		match String(m.kind):
			VehicleWeapons.CANNON:
				var rounds: Array = []
				for sid: Variant in m.g.get("ammo", []):
					rounds.append({"name": VehicleWeapons.short_name(String(sid)), "n": w._ready_net(m, String(sid)),
						"loaded": String(sid) == String(vw.get("l", "")), "next": String(sid) == String(vw.get("n", ""))})
				var reload := [-1.0, 0.0]
				if String(vw.get("cy", "")) in ["load", "short"]:
					var left := w._left(vw.get("e", 0.0))
					var by := int(vw.get("by", -1))
					var whole := maxf(w.load_time(m, by, v.occupant(by)) if by >= 0 else VehicleWeapons.PLAYER_FAST_S, 0.1)
					reload = [clampf(1.0 - left / whole, 0.0, 1.0), left]
				return {"gun": String(m.g.get("name", m.id)), "rounds": rounds, "reload": reload,
					"loader": int(m.loader_seat) == p_seat, "doors": w._left(vw.get("dp", 0.0)) > 0.0}
			VehicleWeapons.AUTOCANNON:
				var feed := String(vw.get("f", "ap"))
				return {"gun": String(m.g.get("name", m.id)), "rounds": [
					{"name": "AP", "n": w._ready_net(m, w._feed_shell(m, "ap")), "loaded": feed == "ap", "next": false},
					{"name": "HE", "n": w._ready_net(m, w._feed_shell(m, "he")), "loaded": feed == "he", "next": false}],
					"reload": [-1.0, 0.0], "loader": false, "doors": false}
	return {}


## "24 km/h  F   FUEL [=====---] 1420 L   ENGINE ok   TRANS ok".
static func drive_line(v: Vehicle) -> String:
	var sp := v.forward_speed()
	var gear := "F" if sp > 0.3 else ("R" if sp < -0.3 else "N")
	var full := maxf(float(v.spec.get("fuel_l", 1.0)), 1.0)
	var share := clampf(v.fuel_litres() / full, 0.0, 1.0)
	var n := roundi(share * 8.0)
	var line := "%d km/h  %s   FUEL [%s%s] %d L" % [roundi(absf(sp) * 3.6), gear, "=".repeat(n), "-".repeat(8 - n), roundi(v.fuel_litres())]
	for pair: Array in [["engine", "ENGINE"], ["transmission", "TRANS"]]:
		var st := _kind_state(v, String(pair[0]))
		if st >= 0:
			line += "   %s %s" % [String(pair[1]), ["ok", "damaged", "OUT"][st]]
	return line


## The worst state of `v`'s modules of `kind` (-1: none).
static func _kind_state(v: Vehicle, kind: String) -> int:
	var worst := -1
	if v.modules:
		for i in v.modules.mods.size():
			if String(v.modules.mods[i].kind) == kind:
				worst = maxi(worst, VehicleModules.state_of(v.modules.health[i]))
	return worst


## The keys worth showing in seat `p_seat`: [[key name, what]], each the player's own binding.
static func keys(v: Vehicle, p_seat: int) -> Array:
	var out: Array = []
	var key := func(action: StringName) -> String: return GameSettings.binding_name(GameSettings.key_for(action))
	if v.gunnery and not v.gunnery.sight_for(p_seat).is_empty():
		out.append(["RMB", "sight"])
		out.append([key.call(&"lase"), "lase"])
		if p_seat == v.gunnery.commander_seat():
			out.append([key.call(&"designate"), "designate"])
	if v.hatches and v.hatches.has_hatch(p_seat):
		out.append([key.call(&"hatch"), "hatch"])
	out.append([key.call(VehicleCamera.ACTION), "view"])
	out.append([key.call(VehicleXray.ACTION), "last hit"])
	if ControlOptions.get_out_key():
		out.append([ControlOptions.get_out_key_name(), "get out"])
	return out


# --- Showing ----------------------------------------------------------------------------------

## Shows `v` (gather()'s shape; tests hand it their own).
func show_view(v: Dictionary) -> void:
	view = v
	var shown := mode in ["chase", "first", "vision"] or mode == ""
	panel.visible = shown and not v.is_empty()
	if not panel.visible:
		return
	_title.text = "%s    DMG %s" % [String(v.get("title", "")), String(v.get("damage", "none"))]
	var al: PackedStringArray = v.get("alerts", PackedStringArray())
	_alerts.text = "   ".join(al)
	_alerts.visible = not al.is_empty()
	var weapons: PackedStringArray = v.get("weapons", PackedStringArray())
	_weapon.text = "\n".join(weapons.slice(0, 3))
	_weapon.visible = not weapons.is_empty()
	_selector.text = selector_text(v.get("selector", {}))
	_selector.visible = _selector.text != ""
	_crew.text = crew_text(v.get("crew", []))
	_crew.visible = _crew.text != ""
	_drive.text = String(v.get("drive", ""))
	_drive.visible = _drive.text != ""
	var keys_out: PackedStringArray = []
	for k: Array in v.get("keys", []):
		keys_out.append("[%s] %s" % [String(k[0]), String(k[1])])
	_keys.text = "  ".join(keys_out)
	_keys.visible = _keys.text != ""
	doll.queue_redraw()


## "[SABOT 14]  HEAT 9  HE 8   next HEAT   loading [======----] 3.1 s".
static func selector_text(sel: Dictionary) -> String:
	if sel.is_empty():
		return ""
	var parts: PackedStringArray = []
	var next := ""
	for r: Dictionary in sel.get("rounds", []):
		var t := "%s %d" % [String(r.name), int(r.n)]
		parts.append("[%s]" % t if bool(r.loaded) else t)
		if bool(r.get("next", false)):
			next = String(r.name)
	var out := "  ".join(parts)
	if next != "":
		out += "   next %s" % next
	var reload: Array = sel.get("reload", [-1.0, 0.0])
	if float(reload[0]) >= 0.0:
		var n := roundi(float(reload[0]) * 10.0)
		out += "   loading [%s%s] %.1f s" % ["=".repeat(n), "-".repeat(10 - n), float(reload[1])]
	return out


## "CREW  D Okafor *  G Mercer *  C you *  L Hale + wounded  R 4/6".
static func crew_text(crew: Array) -> String:
	if crew.is_empty():
		return ""
	var parts: PackedStringArray = []
	for c: Dictionary in crew:
		if String(c.letter) == "R":
			parts.append("R %d/%d" % [int(c.get("n", 0)), int(c.get("of", 0))])
			continue
		var who := "you" if bool(c.get("you", false)) else (String(c.get("name", "")) if String(c.get("name", "")) != "" else "empty")
		var st := String(c.state)
		parts.append("%s %s %s%s" % [String(c.letter), who, String(CREW_MARKS.get(st, "?")), (" " + st) if st in ["wounded", "down", "dead"] else ""])
	return "CREW  " + "  ".join(parts)


## The sight's crew pips and damage word ("CREW D* G* C* L*   DMG none"; VehicleSightOverlay).
static func sight_line(v: Vehicle, s: Soldier) -> String:
	if not applies(v):
		return ""
	var pips: PackedStringArray = []
	for c: Dictionary in crew_pips(v, s):
		if String(c.letter) != "R":
			pips.append(String(c.letter) + String(CREW_MARKS.get(String(c.state), "?")))
	return "CREW %s   DMG %s" % [" ".join(pips), damage_word(v)]


## Fits the panel into `room` px tall and `width` wide (Hud._fit_bottom_centre): drops the keys,
## then the crew line, then the drive line (a driver keeps his), then the selector, then the doll
## shrinks. Returns the height it takes.
func fit(room: float, width: float) -> float:
	if not panel.visible:
		return 0.0
	panel.custom_minimum_size.x = 0.0
	_small = width < 420.0 or room < 220.0
	doll.custom_minimum_size = DOLL_SMALL if _small else DOLL
	for l: Label in [_keys, _crew, _drive, _selector, _weapon]:
		l.visible = l.text != ""
	_alerts.visible = _alerts.text != ""
	var order: Array = [_keys, _crew]
	order.append(_weapon if String(view.get("kind", "")) == String(Vehicle.DRIVER) else _drive)
	order.append(_selector)
	order.append(_drive if String(view.get("kind", "")) == String(Vehicle.DRIVER) else _weapon)
	var h := panel.get_combined_minimum_size().y
	while h > room and not order.is_empty():
		(order.pop_front() as Label).visible = false
		h = panel.get_combined_minimum_size().y
	return h


## Whether the panel takes room in the bottom-centre zone now.
func panel_shown() -> bool:
	return panel.visible


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	if vehicle == null or view.is_empty():
		return
	if mode == "vision":
		_draw_vision()
	if mode == "chase":
		_draw_gun_ring()
	_draw_bft()


## Where the gun is laid, in the chase view: a ring where the barrel's line meets the aim's range.
func _draw_gun_ring() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or vehicle.turret == null:
		return
	var origin := vehicle.gun_origin()
	var chase := VehicleCamera.of(me)
	var reach := 500.0
	if chase and chase.active:
		reach = clampf(origin.distance_to(chase.aim_point()), 30.0, VehicleCamera.AIM_RANGE)
	var p := origin + vehicle.barrel_direction() * reach
	if cam.is_position_behind(p):
		return
	var at := cam.unproject_position(p)
	at = at.clamp(Vector2(12, 12), size - Vector2(12, 12))
	draw_arc(at, 11.0, 0.0, TAU, 24, GUN_COLOUR, 2.0, true)
	draw_line(at + Vector2(-5, 0), at + Vector2(5, 0), GUN_COLOUR, 1.5)
	draw_line(at + Vector2(0, -5), at + Vector2(0, 5), GUN_COLOUR, 1.5)


## A blue chevron over each friendly vehicle on the Blue Force Tracker in view.
func _draw_bft() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for m: Array in bft_marks(vehicle, me, cam, size):
		var at: Vector2 = m[0]
		var c := BFT_COLOUR if not bool(m[1]) else Color(BFT_COLOUR, 0.4)
		draw_polyline(PackedVector2Array([at + Vector2(-9, -6), at, at + Vector2(9, -6)]), c, 3.0, true)
		draw_polyline(PackedVector2Array([at + Vector2(-9, -12), at + Vector2(0, -6), at + Vector2(9, -12)]), c, 3.0, true)


## The chevrons for player `s` in `own` seen by `cam` on a screen `screen` px: [[screen point,
## dimmed (beyond 1,500 m)], ...] for every friendly vehicle but his own that's on the Blue Force
## Tracker (its radio working: SideIntel.radio_ok), in front of the camera, within BFT_RANGE_M
## and on screen.
static func bft_marks(own: Vehicle, s: Soldier, cam: Camera3D, screen: Vector2) -> Array:
	var out: Array = []
	if cam == null or s == null or not cam.is_inside_tree():
		return out
	var friendly := s.faction in Deconfliction.FRIENDLY
	for n in cam.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v == own or not v.is_inside_tree() or not SideIntel.radio_ok(v):
			continue
		if not ((v.faction in Deconfliction.FRIENDLY) if friendly else v.faction == s.faction):
			continue
		var top := v.global_transform * (VehicleCamera.hull_box(v).get_center() + Vector3(0, VehicleCamera.hull_box(v).size.y * 0.5 + 0.8, 0))
		var d := cam.global_position.distance_to(top)
		if d > BFT_RANGE_M or cam.is_position_behind(top):
			continue
		var at := cam.unproject_position(top)
		if Rect2(Vector2.ZERO, screen).has_point(at):
			out.append([at, d > 1500.0, v.vehicle_id])
	return out


## The slit of glass block `vv.block` on a screen `screen` px (its width by the block's, its
## height GLASS_TALL_DEG), in the middle.
static func slit_rect(vv: VehicleVision, screen: Vector2) -> Rect2:
	var blocks := vv.blocks()
	if blocks.is_empty():
		return Rect2(screen * 0.5, Vector2.ZERO)
	var width := float(blocks[clampi(vv.block, 0, blocks.size() - 1)][1])
	var vfov := deg_to_rad(vv.fov if vv.fov > 1.0 else 75.0)
	var aspect := screen.x / maxf(screen.y, 1.0)
	var half_h := tan(vfov * 0.5)
	var half_w := half_h * aspect
	var w := minf(screen.x * tan(deg_to_rad(width) * 0.5) / half_w, screen.x - 40.0)
	var h := minf(screen.y * tan(deg_to_rad(VehicleVision.GLASS_TALL_DEG) * 0.5) / half_h, screen.y * 0.6)
	return Rect2((screen - Vector2(w, h)) * 0.5 - Vector2(0, screen.y * 0.06), Vector2(w, h))


## The vision block's mask: dark round the glass, its frame, which block of how many, the
## driver's turret arrow, the loader's doors and rounds.
func _draw_vision() -> void:
	var vv := VehicleVision.of(me)
	if vv == null:
		return
	var font := UiKit.FONT_STRONG
	if vv.mode() == "out":
		draw_rect(Rect2(Vector2.ZERO, size), SLIT_DARK)
		draw_string(font, Vector2(0, size.y * 0.42), "PERISCOPES OUT: TURN OUT TO DRIVE [%s]" % GameSettings.binding_name(GameSettings.key_for(&"hatch")),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, UiKit.FONT_HUD, UiKit.WARN)
		return
	var r := slit_rect(vv, size)
	draw_rect(Rect2(0, 0, size.x, r.position.y), SLIT_DARK)
	draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), SLIT_DARK)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), SLIT_DARK)
	draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), SLIT_DARK)
	draw_rect(r.grow(3.0), SLIT_FRAME, false, 6.0)
	var n := vv.blocks().size()
	var label := "%s %d / %d%s" % ["PERISCOPE" if vehicle.seat_kind(seat) == Vehicle.DRIVER else "BLOCK", vv.block + 1, n,
		("   " + vv.mode().to_upper()) if vehicle.seat_kind(seat) == Vehicle.DRIVER else ""]
	draw_string(font, Vector2(r.position.x, r.position.y - 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiKit.FONT_HUD_SMALL, UiKit.TEXT)
	# Which way the gun points, from the hull (the driver must know before he swings it).
	if vehicle.turret and vehicle.seat_kind(seat) == Vehicle.DRIVER:
		var c := Vector2(r.end.x - 26.0, r.end.y + 34.0)
		draw_rect(Rect2(c - Vector2(10, 16), Vector2(20, 32)), UiKit.TEXT_DIM, false, 2.0)
		var dir := Vector2(-sin(vehicle.turret.yaw), -cos(vehicle.turret.yaw))
		draw_line(c, c + dir * 26.0, GUN_COLOUR, 3.0)
		draw_circle(c, 5.0, GUN_COLOUR)
	if vehicle.seat_kind(seat) == Vehicle.LOADER:
		_draw_loader(r)


## The loader turned in: the bustle doors and a large round selector under his periscope.
func _draw_loader(r: Rect2) -> void:
	var sel: Dictionary = view.get("selector", {})
	var rounds: Array = sel.get("rounds", [])
	if rounds.is_empty():
		return
	var font := UiKit.FONT_BOLD
	var top := r.end.y + 70.0
	var tile := Vector2(clampf(size.x * 0.11, 90.0, 180.0), clampf(size.y * 0.09, 54.0, 96.0))
	var gap := 14.0
	var total := tile.x * rounds.size() + gap * (rounds.size() - 1)
	var x := (size.x - total) * 0.5
	var doors := bool(sel.get("doors", false))
	draw_string(font, Vector2(0, top - 14.0), "BUSTLE DOORS %s" % ("OPEN" if doors else "SHUT"), HORIZONTAL_ALIGNMENT_CENTER, size.x,
		UiKit.FONT_HUD, UiKit.WARN if doors else UiKit.TEXT)
	for rd: Dictionary in rounds:
		var box := Rect2(Vector2(x, top), tile)
		var hot := bool(rd.get("next", false))
		draw_rect(box, Color(0, 0, 0, 0.6))
		draw_rect(box, UiKit.ACCENT if hot else (UiKit.GOOD if bool(rd.loaded) else UiKit.BORDER), false, 4.0 if hot else 2.0)
		draw_string(font, box.position + Vector2(0, tile.y * 0.45), String(rd.name), HORIZONTAL_ALIGNMENT_CENTER, tile.x, UiKit.FONT_HUD, UiKit.TEXT_BRIGHT)
		draw_string(font, box.position + Vector2(0, tile.y * 0.85), "%d" % int(rd.n), HORIZONTAL_ALIGNMENT_CENTER, tile.x, UiKit.FONT_HUD_SMALL, UiKit.TEXT)
		x += tile.x + gap
	var reload: Array = sel.get("reload", [-1.0, 0.0])
	var hint := "[%s] load / ram    [%s] next round" % [GameSettings.binding_name(GameSettings.key_for(&"reload")), GameSettings.binding_name(GameSettings.key_for(&"fire_mode"))]
	if float(reload[0]) >= 0.0:
		var bar := Rect2(Vector2((size.x - total) * 0.5, top + tile.y + 12.0), Vector2(total, 8.0))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(reload[0]), bar.size.y)), UiKit.ACCENT)
	draw_string(UiKit.FONT_REGULAR, Vector2(0, top + tile.y + 44.0), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, UiKit.FONT_HUD_SMALL, UiKit.TEXT_DIM)


## The vehicle doll: top-down from its data (front up), modules coloured by state, tracks or
## wheels, ERA tiles (grey once fired), crew pips with role letters at their seats.
class Doll extends Control:
	var owner_hud: VehicleHud

	func _init(h: VehicleHud = null) -> void:
		owner_hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = VehicleHud.DOLL

	func _draw() -> void:
		var v := owner_hud.vehicle if owner_hud else null
		if v == null or not is_instance_valid(v):
			return
		var layout := VehicleHud.doll_layout(v)
		var bounds: Rect2 = layout.bounds
		var k := minf((size.x - 6.0) / maxf(bounds.size.x, 0.1), (size.y - 6.0) / maxf(bounds.size.y, 0.1))
		var off := (size - bounds.size * k) * 0.5
		var to_px := func(r: Rect2) -> Rect2: return Rect2(off + (r.position - bounds.position) * k, r.size * k)
		draw_rect(to_px.call(bounds), Color(0, 0, 0, 0.35))
		draw_rect(to_px.call(bounds), UiKit.TEXT_DIM, false, 1.5)
		var m := v.modules
		for e: Array in layout.modules:
			var i := int(e[0])
			var st := VehicleModules.state_of(m.health[i]) if i < m.health.size() else 0
			var col := VehicleHud.STATE_COLOURS[st]
			var r: Rect2 = to_px.call(e[1])
			if String(e[2]) in ["track", "wheel"]:
				draw_rect(r, Color(col, 0.75))
			else:
				draw_rect(r, Color(col, 0.18 if st == VehicleModules.WORKING else 0.55))
				draw_rect(r, Color(col, 0.9), false, 1.0)
		var used: Dictionary = v.get_meta(ArmourModel.META_TILES, {})
		for t: Array in layout.tiles:
			var flags: PackedByteArray = used.get(String(t[0]), PackedByteArray())
			var r: Rect2 = to_px.call(t[1])
			var count := int(t[2])
			var along_x := r.size.x >= r.size.y
			for j in count:
				var seg := Rect2(r.position + (Vector2(r.size.x * j / count, 0) if along_x else Vector2(0, r.size.y * j / count)),
					Vector2(r.size.x / count, r.size.y) if along_x else Vector2(r.size.x, r.size.y / count))
				var fired := j < flags.size() and flags[j] != 0
				draw_rect(seg.grow(-0.5), Color(0.55, 0.55, 0.55, 0.9) if fired else Color(0.62, 0.72, 0.5, 0.9))
		var font := UiKit.FONT_BOLD
		for c: Dictionary in owner_hud.view.get("crew", []):
			if int(c.seat) < 0 or not layout.seats.has(int(c.seat)):
				continue
			var at: Vector2 = off + ((layout.seats[int(c.seat)] as Vector2) - bounds.position) * k
			var col: Color = VehicleHud.CREW_COLOURS.get(String(c.state), UiKit.TEXT_OFF)
			draw_circle(at, 7.0, col)
			if bool(c.get("you", false)):
				draw_arc(at, 9.5, 0.0, TAU, 16, UiKit.TEXT_BRIGHT, 1.5)
			draw_string(font, at + Vector2(-7, 4.5), String(c.letter), HORIZONTAL_ALIGNMENT_CENTER, 14.0, 12, UiKit.INK)


## The doll's layout for `v`'s model (cached): {"bounds": Rect2 (x, z top-down, front up),
## "modules": [[index, Rect2, kind]] (boxed, not crew or structure), "tiles": [[group, Rect2,
## count]] (fitted only), "seats": {seat: Vector2}}.
static func doll_layout(v: Vehicle) -> Dictionary:
	var key := v.model + ":" + ",".join(PackedStringArray((v.get_meta(ArmourModel.META_PACKAGES, []) as Array).map(func(p: Variant) -> String: return String(p))))
	if _dolls.has(key):
		return _dolls[key]
	var flat := func(b: AABB) -> Rect2: return Rect2(Vector2(b.position.x, b.position.z), Vector2(b.size.x, b.size.z))
	var hull := VehicleCamera.hull_box(v)
	var bounds: Rect2 = flat.call(hull)
	var mods: Array = []
	for m: Dictionary in v.modules.mods:
		if m.box == null or bool(m.crew) or String(m.kind) == "structure" or String(m.kind) == "compartment":
			continue
		var r: Rect2 = flat.call(m.box)
		mods.append([int(m.i), r, String(m.kind)])
		bounds = bounds.merge(r)
	# Tracks and wheels drawn first (under), the rest over them.
	mods.sort_custom(func(a: Array, b: Array) -> bool: return int(String(a[2]) in ["track", "wheel"]) > int(String(b[2]) in ["track", "wheel"]))
	var tiles: Array = []
	var fitted := ArmourModel.fitted_packages(v.spec, v.get_meta(ArmourModel.META_PACKAGES, []))
	for t: Dictionary in v.spec.get("tiles", []):
		if ArmourModel.tile_fitted(t, fitted):
			var r: Rect2 = flat.call(VehicleSpecs.box(t.box))
			tiles.append([String(t.group), r, maxi(int(t.get("count", 1)), 1)])
			bounds = bounds.merge(r)
	var seats := {}
	for i in (v.spec.get("seats", []) as Array).size():
		var b := VehicleModules.seat_box(v.spec, i)
		seats[i] = Vector2(b.get_center().x, b.get_center().z)
	var out := {"bounds": bounds, "modules": mods, "tiles": tiles, "seats": seats}
	_dolls[key] = out
	return out
