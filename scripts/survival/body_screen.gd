class_name BodyScreen
extends HBoxContainer
## The body screen (docs/survival_medical.md section 7, call 58), inside BodyReadout (the
## backslash key): a figure of the Person (MedicalMenu.draw_diagram as the base) with layers you
## toggle (1-6: wounds, bones, infection, temperature, wetness, clothing) and a front and back
## (the arrow keys turn it), each part's state in words first and numbers on hover, the
## metabolism panel beside it (rings with trend arrows), and the treatments for the picked part
## (click a part; the buttons are the kit's items through Soldier._server_treat and the body's own
## care through Survival._server_body_action). The same screen opens on a companion or casualty
## you look at within reach. What you can see is gated by medical skill (Rpg.medical_sees): a
## novice sees "hurt, bleeding, hot"; a medic the wound classes and the infection stage; a doctor
## everything, days left included. part_lines and summary are static (tests).

const LAYERS: Array[String] = ["wounds", "bones", "infection", "temperature", "wetness", "clothing"]
const FIGURE_K := 0.9
const RING_R := 16.0
const STAGE_COLORS := [Color(0.3, 0.75, 0.35, 0.0), Color(0.85, 0.75, 0.25, 0.45), Color(0.9, 0.45, 0.15, 0.55), Color(0.75, 0.1, 0.1, 0.65)]
const KIND_WORDS := {"graze": "graze", "venous": "venous bleed", "arterial": "arterial bleed", "junctional": "junctional bleed",
	"muscle": "deep wound", "chest": "chest wound", "fracture": "broken bone", "rib": "cracked rib", "burn": "burn"}
const STAGE_WORDS := ["clean", "dirty", "infected", "septic"]
const REFRESH_S := 0.5

var layers := {"wounds": true, "bones": true, "infection": true, "temperature": false, "wetness": false, "clothing": false}
var back := false
var selected: StringName = &""
var target: Soldier
var figure: Control
var words: Label
var hover: Label
var buttons: VBoxContainer
var _prev := {}
var _trend := {}
var _left := 0.0


func _init() -> void:
	name = "BodyScreen"
	figure = Control.new()
	figure.custom_minimum_size = MedicalMenu.FIGURE_SIZE * FIGURE_K + Vector2(0, 150)
	figure.mouse_filter = Control.MOUSE_FILTER_STOP
	figure.draw.connect(_draw_figure)
	figure.gui_input.connect(_figure_input)
	add_child(figure)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	add_child(col)
	words = UiKit.hud_label("", &"HudSmallLabel")
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(380, 0)
	col.add_child(words)
	hover = UiKit.hud_label("", &"HudSmallLabel")
	col.add_child(hover)
	buttons = VBoxContainer.new()
	col.add_child(buttons)


# --- What the screen shows (static: tests) -----------------------------------------------------

## Each hurt part's line in words by what `sees` lets you see (0 novice, 1 medic, 2 doctor), from
## the body `n` (Infection's records, the bite) and the wound model's `wounds` (Vitals.wound_list).
static func part_lines(n: Dictionary, wounds: Array, sees: int) -> Dictionary:
	var out := {}
	var parts := {}
	for w: Dictionary in wounds:
		parts[StringName(w.part)] = true
	for r: Dictionary in Infection.records(n):
		parts[StringName(String(r.part))] = true
	var hot := Body.has_fever(n)
	for p: StringName in parts:
		var bits: Array = []
		var bleeding := wounds.any(func(w: Dictionary) -> bool: return StringName(w.part) == p and bool(w.bleeding))
		var recs := Infection.on_part(n, String(p))
		var part_hot := hot or recs.any(func(r: Dictionary) -> bool: return int(r.stage) >= 2)
		if sees <= 0:
			bits.append("hurt")
			if bleeding:
				bits.append("bleeding")
			if part_hot:
				bits.append("hot")
		else:
			for w: Dictionary in wounds:
				if StringName(w.part) != p:
					continue
				var word := String(KIND_WORDS.get(String(w.kind), String(w.kind)))
				if bool(w.bleeding):
					word += ", bleeding" + (" slowly" if float(w.rate) < 0.1 else "")
				bits.append(word)
			for r: Dictionary in recs:
				var bit := "deep bite" if bool(r.get("bite", false)) else ""
				if not bool(r.closed):
					bit += (", " if bit != "" else "") + String(STAGE_WORDS[clampi(int(r.stage), 0, 3)])
					if float(r.dressed_h) < 0.0:
						bit += ", undressed"
					else:
						bit += ", clean dressing" if float(r.dressed_h) < Infection.DRESSING_FRESH_H else ", dirty dressing"
				if bool(r.fragment):
					bit += ", something still in it"
				if bool(r.stitched):
					bit += ", stitched"
				if bool(r.get("abscess", false)):
					bit += ", an abscess"
				if bool(r.get("gangrene", false)):
					bit += ", gangrene"
				if String(r.get("bone", "")) != "":
					bit += ", " + String(r.bone).replace("_", " ")
				if sees >= 2:
					var days := Infection.days_left(n, r)
					var why := Infection.slowed_by(n, r)
					bit += (", heals in %d days" % ceili(days)) if days < INF else ", not healing"
					if not why.is_empty():
						bit += " (%s)" % ", ".join(why)
					if int(r.stage) == 1:
						bit += ", infected in %d h unless cleaned" % ceili(maxf(0.0, Infection.INFECT_H - float(r.stage_h)))
					elif int(r.stage) == 2:
						bit += ", septic in %d h" % ceili(maxf(0.0, Infection.SEPSIS_H - float(r.stage_h)))
				if bit != "":
					bits.append(bit.trim_prefix(", "))
			if bool(n.get("bite") is Dictionary) and recs.any(func(r: Dictionary) -> bool: return bool(r.get("bite", false))) and sees >= 2:
				var st := BiteFever.stage(n)
				if st == 0 and not bool(BiteFever.clock(n).get("immune", false)):
					bits.append("fever in %d days" % ceili(maxf(0.0, BiteFever.FEVER_AT_H - float(BiteFever.clock(n).get("h", 0.0))) / 24.0))
		out[p] = "%s: %s" % [Vitals.part_name(p), ", ".join(bits)]
	return out


## The whole body's state in words (the bite, fever, sicknesses, the course), by `sees`.
static func summary(n: Dictionary, sees: int) -> Array:
	var out: Array = Mind.words(n) if sees > 0 else Mind.signs(n)  # the nerve, habits (Mind)
	var hot := Body.has_fever(n) or float(n.get("warmth", Needs.NORMAL_C)) >= 37.8
	if sees <= 0:
		if hot:
			out.append("hot")
		if BiteFever.bitten(n):
			out.append("bitten")
		if Sickness.coughing(n):
			out.append("coughing")
		if Infection.worst(n) >= 1 or not Sickness.shown(n).is_empty():
			out.append("unwell")
		return out
	if BiteFever.bitten(n):
		var st := BiteFever.stage(n)
		if sees >= 2:
			out.append("bitten: %s, collapse in %.1f days at this pace" % [BiteFever.stage_name(n), BiteFever.hours_left(n) / 24.0 / maxf(0.01, BiteFever.pace(n))] if not bool(BiteFever.clock(n).get("immune", false)) else "bitten: no fever yet")
		else:
			out.append("bitten" + (": " + BiteFever.stage_name(n) if st >= 1 else ""))
	if Infection.worst(n) >= 1:
		out.append("wounds: " + Infection.STAGES[Infection.worst(n)])
	for id: String in Sickness.shown(n):
		out.append(String((Sickness.ILLS.get(id, {}) as Dictionary).get("name", id)))
	if hot:
		out.append("fever %.1f C" % float(n.get("warmth", Needs.NORMAL_C)) if sees >= 2 else "fever")
	var c := Infection.course(n)
	if not c.is_empty():
		out.append("antibiotics: dose %d of %d" % [int(c.get("doses", 0)), Infection.COURSE])
	if sees >= 2 and String(n.get("blood_type", "")) != "":
		out.append("blood type %s" % String(n.blood_type))
	return out


# --- Live -------------------------------------------------------------------------------------

func _me() -> Soldier:
	var level := CompoundLevel.current(self)
	return level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if level else null


## Who the screen is on: the body looked at within reach (a companion, a casualty), else yourself.
func pick_target() -> void:
	var me := _me()
	target = me
	if me == null or me.camera == null:
		return
	var fwd := -me.camera.global_basis.z
	var best := Survival.BODY_REACH_M
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or s == me or s.vitals == null or s.vitals.undead or s.vitals.is_dead():
			continue
		var to := s.global_position + Vector3.UP - me.camera.global_position
		var d := to.length()
		if d < best and fwd.dot(to / d) > 0.9:
			best = d
			target = s


## The body Dictionary shown: yours (Survival.my_body) or the target's last read.
func body() -> Dictionary:
	var me := _me()
	if target == null or target == me:
		return Survival.my_body
	return Survival.read_bodies.get(target.get_path(), {})


func refresh() -> void:
	var me := _me()
	if target != null and target != me and is_instance_valid(target):
		Survival._server_body_action.rpc_id(1, target.get_path(), "read", "", "")
	var n := body()
	var sees := Rpg.medical_sees(me) if me else 0
	for k: String in ["calories", "water", "sleep", "warmth", "hygiene"]:
		var v := float(n.get(k, 0.0))
		if _prev.has(k):
			_trend[k] = signf(v - float(_prev[k])) if absf(v - float(_prev[k])) > 0.001 else 0.0
		_prev[k] = v
	var lines: Array = []
	var who := "You" if target == null or target == me else target.display_name()
	lines.append("%s%s" % [who, " (back)" if back else ""])
	var sum := summary(n, sees)
	if not sum.is_empty():
		lines.append(", ".join(sum))
	var wl: Array = []
	if target and is_instance_valid(target) and target.vitals:
		wl.assign(target.vitals.wound_list())
	var pl := part_lines(n, wl, sees)
	for p: StringName in pl:
		lines.append(String(pl[p]))
	if not n.is_empty():
		var w := Needs.words(n)
		lines.append("Food %s, water %s, sleep %s, %s, %s" % [w.calories, w.water, w.sleep, w.warmth, w.hygiene])
	lines.append("Layers (1-6): " + " ".join(LAYERS.filter(func(l: String) -> bool: return bool(layers[l]))))
	words.text = "\n".join(lines)
	figure.queue_redraw()


func _draw_figure() -> void:
	var n := body()
	var origin := Vector2(4, 4)
	var k := FIGURE_K
	var me := _me()
	var sees := Rpg.medical_sees(me) if me else 0
	var v: Vitals = target.vitals if target and is_instance_valid(target) else null
	if v and bool(layers.wounds):
		MedicalMenu.draw_diagram(figure, v, origin, k, selected)
	else:
		for p: StringName in MedicalMenu.PART_RECTS:
			figure.draw_rect(_rect(p, origin, k), Color(0.55, 0.57, 0.6, 0.5))
	var warmth := float(n.get("warmth", Needs.NORMAL_C))
	for p: StringName in MedicalMenu.PART_RECTS:
		var r := _rect(p, origin, k)
		if bool(layers.infection) and sees >= 1:
			var worst := 0
			for rec: Dictionary in Infection.on_part(n, String(p)):
				worst = maxi(worst, int(rec.stage))
			if worst > 0:
				figure.draw_rect(r, STAGE_COLORS[worst])
		if bool(layers.temperature):
			var t := clampf((warmth - Needs.NORMAL_C) / 2.0, -1.0, 1.0)
			figure.draw_rect(r, Color(1.0, 0.3, 0.1, t * 0.5) if t > 0.0 else Color(0.2, 0.5, 1.0, -t * 0.5))
		if bool(layers.wetness):
			figure.draw_rect(r, Color(0.2, 0.4, 0.9, float(n.get("wet", 0.0)) * 0.5))
		if bool(layers.bones) and v:
			for w: Dictionary in v.wound_list():
				if StringName(w.part) == p and String(w.kind) in ["fracture", "rib"]:
					figure.draw_line(r.position + Vector2(2, r.size.y * 0.5), r.end - Vector2(2, r.size.y * 0.5), Color.WHITE, 2.0)
	if bool(layers.clothing) and target and is_instance_valid(target):
		var cw := BodySeason.clothing_warmth(target.inventory)
		figure.draw_rect(Rect2(origin, MedicalMenu.FIGURE_SIZE * k), Color(0.8, 0.7, 0.5, 0.25 + cw * 0.5), false, 3.0)
	# The metabolism rings, under the figure.
	var y := MedicalMenu.FIGURE_SIZE.y * k + 30.0
	var x := 22.0
	for key: String in ["calories", "water", "sleep", "warmth", "hygiene"]:
		var frac := 0.0
		match key:
			"calories":
				frac = float(n.get("hunger", 0.0)) / 100.0
			"water":
				frac = float(n.get("thirst", 0.0)) / 100.0
			"warmth":
				frac = clampf((warmth - Needs.MIN_C) / (Needs.NORMAL_C - Needs.MIN_C), 0.0, 1.0)
			_:
				frac = float(n.get(key, 0.0)) / 100.0
		var c := Vector2(x, y)
		figure.draw_arc(c, RING_R, 0.0, TAU, 32, Color(0.3, 0.3, 0.3), 4.0)
		figure.draw_arc(c, RING_R, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 32, Color(0.3, 0.8, 0.4) if frac > 0.35 else Color(0.9, 0.5, 0.2), 4.0)
		var tr := float(_trend.get(key, 0.0))
		var arrow := "^" if tr > 0.0 else ("v" if tr < 0.0 else "-")
		figure.draw_string(UiKit.FONT_STRONG, c + Vector2(-RING_R, RING_R + 16), "%s %s" % [key.substr(0, 4), arrow], HORIZONTAL_ALIGNMENT_LEFT, 60, UiKit.FONT_SMALL, Color.WHITE)
		x += 42.0


func _rect(p: StringName, origin: Vector2, k: float) -> Rect2:
	var r: Rect2 = MedicalMenu.PART_RECTS[p]
	if back:  # turned round: left and right swap sides
		r.position.x = MedicalMenu.FIGURE_SIZE.x - r.position.x - r.size.x
	return Rect2(origin + r.position * k, r.size * k)


func _part_at(pos: Vector2) -> StringName:
	for p: StringName in MedicalMenu.PART_RECTS:
		if _rect(p, Vector2(4, 4), FIGURE_K).has_point(pos):
			return p
	return &""


func _figure_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		hover.text = _numbers(_part_at(motion.position))
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		selected = _part_at(click.position)
		_build_buttons()
		figure.queue_redraw()


## Numbers on hover: the part's records (stage hours, heal hours) by skill, else the stores.
func _numbers(p: StringName) -> String:
	var n := body()
	var me := _me()
	var sees := Rpg.medical_sees(me) if me else 0
	if p == &"":
		return "%.1f C, %d kcal, %.1f l" % [float(n.get("warmth", Needs.NORMAL_C)), roundi(float(n.get("calories", 0.0))), float(n.get("water", 0.0))]
	var bits: Array = []
	for r: Dictionary in Infection.on_part(n, String(p)):
		if sees >= 2:
			bits.append("%s %s %.0f h, heal %.0f/%.0f h" % [String(r.kind), Infection.stage_name(r), float(r.stage_h), float(r.heal_h), float(r.heal_total)])
		elif sees == 1:
			bits.append("%s %s" % [String(r.kind), Infection.stage_name(r)])
	return "%s: %s" % [Vitals.part_name(p), "; ".join(bits) if not bits.is_empty() else "nothing more to tell"]


## The treatments for the picked part: the kit's items (Soldier._server_treat) and the body's care.
func _build_buttons() -> void:
	for c in buttons.get_children():
		c.queue_free()
	var me := _me()
	if me == null or selected == &"" or target == null or not is_instance_valid(target):
		return
	for row: Dictionary in MedicalMenu.item_options(me, target, selected):
		if String(row.get("disabled", "")) != "":
			continue
		var b := Button.new()
		b.text = String(row.get("label", "Treat"))
		var action: Dictionary = row
		b.pressed.connect(func() -> void: InteractionMenu.perform(me, action))
		buttons.add_child(b)
	var care := [["antibiotics", "", "Antibiotics (a dose)"], ["clean", "antiseptic", "Clean: antiseptic"], ["clean", "water", "Clean: clean water"],
		["drink", "", "A strong drink first"], ["surgery", "remove_fragment", "Remove the fragment"], ["surgery", "debride", "Debride"],
		["surgery", "stitch", "Stitch"], ["surgery", "set_bone", "Set the bone"], ["surgery", "drain", "Drain"], ["surgery", "amputate", "Amputate"],
		["serum", "", "The serum"]]
	for c: Array in care:
		var b := Button.new()
		b.text = String(c[2])
		var action := String(c[0])
		var arg := String(c[1])
		var path := target.get_path()
		var part := String(selected)
		b.pressed.connect(func() -> void: Survival._server_body_action.rpc_id(1, path, action, part, arg))
		buttons.add_child(b)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_visible_in_tree():
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		var l := LAYERS[key.keycode - KEY_1]
		layers[l] = not bool(layers[l])
		refresh()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT:
		back = not back
		refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_S
		refresh()
