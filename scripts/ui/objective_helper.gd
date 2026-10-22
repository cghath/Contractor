class_name ObjectiveHelper
extends Control
## What to do now, on the HUD (Captain 2026-10-13: "an objective helper system ... so they do
## know what to do", kept minimal): one short line under the objectives panel, and a small
## marker on screen for the current step's target. Everything is read on this peer from
## replicated state (Contracts.objectives with their sites, Extraction's points, the people
## layer's HVT states and bodies, the squad's gear), so the host needs nothing new and a late
## joiner sees the same as everyone else.
##
## The step (step_for, a pure function of the objectives and a `situation` read from the
## level) goes like this:
## - No deployment: nothing.
## - An HVT or hostage the squad has in hand (led, carried, or cuffed or given up with
##   someone from the squad beside them): "Bring <name> to the LZ (<dir>, <distance>)".
## - Otherwise the nearest required objective still to do. Away from its site: "Head to the
##   <site> (<dir>, <distance>)". At the site, by kind: CLEAR_AREA "Clear the <site>" with
##   the hostiles left; DESTROY_CACHE "Destroy the <name>" (a charge set: "get clear");
##   DESTROY_VEHICLES (sabotage's vehicle park) "Put every vehicle ... out of action";
##   missions 2's KILL_HVT "Kill <name>: ... take his ID papers off the body", DESTROY_WRECK "Set a
##   breaching charge on the <wreck>", OVERWATCH "Hold the overwatch position and cover the convoy";
##   EXTRACT_ITEM "Find the <item> in the building", or for a piece an HVT carries "Search
##   <name> for the <item>"; DELIVER_HVT "Capture <name>: cuff them, take them to the LZ"
##   ("you need zip cuffs" without any), or for a hostage "Free <name>: have them follow you
##   to the LZ".
##   An item the squad already carries counts as in hand: it goes out at extraction.
## - Nothing left to do: "All done: call extraction (map, M) or walk to an LZ" (or "Carry the
##   <item> out" with an item in hand), "At <LZ>: extract on the map (M) once everyone's in",
##   and the countdown while it runs.
## With no contract objectives (the menu's test contract), the briefing's objectives stand in:
## the nearest one, by its title and text.
##
## Markers: a small diamond, a short label and the distance for each target of the current
## step (the objective's site, or the extraction point once everything is done), placed by
## projecting the point with the player's camera. Off screen or behind, only a small arrow at
## the screen's edge. They fade and shrink with distance, and hide close in (inside an area
## objective, or near a point that sits inside a building) so the marker never points through
## a wall at the thing itself. Nothing is drawn in the world.

## The settings menu's switch for the markers (the hint line stays).
static var markers_on := true
## The local HUD's helper joins this group: a world label for a point it marks hides
## (DeliveryPoint; Captain, 2026-10-14: aimed through a red dot at "LZ 2", the LZ's own label
## showed small in the sight as well as the marker below it).
const GROUP := &"objective_helper"
## A marker this close (m, flat) to a point counts as marking it (marks()).
const MARKS_M := 3.0

## Within this far (m, flat) of a site the hint switches from "Head to" to what to do there.
const AT_SITE_M := 50.0
## Markers hide within this far of a point target, or of one inside a building.
const HIDE_NEAR_M := 6.0
const HIDE_INDOORS_M := 20.0
## How often the step is worked out again (s); markers move every frame.
const STEP_S := 0.25
## Marker look: alpha and size near and far (they fade and shrink out to FADE_M), the inset
## from the screen's edge for the edge arrows, and the colours.
const FADE_M := 1500.0
## ui-modern (2026-10-20): 70% near and 45% far were still hard to pick out over bright ground.
const ALPHA_NEAR := 0.95
## docs/ui_audit.md P1-13: far diamonds were 3.5 px at 30%, too faint to find.
const ALPHA_FAR := 0.75
const SIZE_NEAR := 8.0
const SIZE_FAR := 6.0
const EDGE_PX := 26.0
const OBJECTIVE_COLOUR := Color(1.0, 0.9, 0.55)
const EXTRACT_COLOUR := Color(0.82, 0.7, 1.0)
## The hint line's width (px) on its own: the objectives panel's (it poked 116 px out to the left
## of the panel at 480, P1-13). In the Hud it goes in the top-right zone, under the panel.
const HINT_WIDTH := ObjectivesPanel.WIDTH
const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var player: Soldier
## The current step: {"text", "targets": [{"pos": Vector3, "label", "extract": bool,
## "rect": Rect2 (an area target), "hide_m"}]}.
var current: Dictionary = {"text": "", "targets": []}
## The markers as last drawn (tests read them): [{"pos", "label", "screen": Vector2,
## "edge": bool (an arrow at the screen's edge), "distance", "alpha", "size", "extract"}].
var drawn: Array = []

var _hint: Label
var _panel: Control
var _step_left := 0.0
var _indoors := {}  # point (rounded) -> whether a roof is over it, worked out once


func _init(p: Soldier = null) -> void:
	player = p
	name = "ObjectiveHelper"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = UiKit.hud_label("", &"HudSmallLabel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hud := Hud.of(self)
	if hud and hud.zone_top_right:
		hud.zone_top_right.add_child(_hint)
	else:
		add_child(_hint)
	Contracts.objectives.changed.connect(refresh)


## The hint line as shown ("" when hidden; tests read it).
func hint_text() -> String:
	return _hint.text if _hint.visible else ""


## Whether a marker is drawn now on `pos` (within MARKS_M, flat): its label is on the HUD, so a
## label in the world for the same point would only say it twice.
func marks(pos: Vector3) -> bool:
	for m: Dictionary in drawn:
		if _flat(m.pos, pos) <= MARKS_M:
			return true
	return false


## Works the step out now (it also does so a few times a second on its own).
func refresh() -> void:
	if not is_inside_tree():
		return  # objectives changed while the HUD is between levels (net: a restore on the way in); it refreshes once it's back
	_step_left = STEP_S
	var objs := _objectives()
	if Objectives.chosen_oid != "" and not pickable(objs).any(func(o: Dictionary) -> bool: return String(o.oid) == Objectives.chosen_oid):
		Objectives.chosen_oid = ""  # done, failed or gone: back to the nearest
	current = step_for(objs, situation())
	_hint.text = String(current.text)
	_hint.visible = _hint.text != "" and _shown()
	_place_hint()
	drawn = layout_markers()
	queue_redraw()


func _process(delta: float) -> void:
	_step_left -= delta
	if _step_left <= 0.0:
		refresh()
	else:
		_hint.visible = _hint.text != "" and _shown()
		_place_hint()
	drawn = layout_markers()
	queue_redraw()


## Under the objectives panel, right-aligned with it (the corner itself without one).
func _place_hint() -> void:
	if _hint.get_parent() != self:
		return  # in the Hud's top-right zone, which places it
	if (_panel == null or not is_instance_valid(_panel)) and get_parent():
		for sibling in get_parent().get_children():
			if sibling is ObjectivesPanel:
				_panel = sibling
	var top := 16.0
	if _panel and _panel.visible:
		top = _panel.position.y + _panel.size.y + 4.0
	_hint.size = Vector2(HINT_WIDTH, 0.0)
	_hint.position = Vector2(size.x - 16.0 - HINT_WIDTH, top)


## Whether the HUD shows anything now: a player up, with the inventory and the map shut.
func _shown() -> bool:
	if player == null or not is_instance_valid(player) or not player.vitals.is_up():
		return false
	var hud := Hud.of(self)
	return hud == null or not (hud.is_inventory_open() or (hud.map_screen and hud.map_screen.visible))


# --- The step (pure) ----------------------------------------------------------------------

## The step for `objectives` (Contracts.objectives.list, or briefing stand-ins with "kind"
## "briefing") in `sit` (situation()): {"text", "targets"}.
static func step_for(objectives: Array, sit: Dictionary) -> Dictionary:
	var none := {"text": "", "targets": []}
	if objectives.is_empty():
		return none
	var from: Vector3 = sit.get("pos", Vector3.ZERO)
	if String(objectives[0].get("kind", "")) == "briefing":
		return _briefing_step(objectives, from)
	var live := objectives.filter(func(o: Dictionary) -> bool: return o.get("state", "") == Objectives.ACTIVE)
	var required := objectives.filter(func(o: Dictionary) -> bool: return not bool(o.get("optional", false)))
	var todo := live.filter(func(o: Dictionary) -> bool: return not bool(o.get("optional", false))) if not required.is_empty() else live
	# An HVT or hostage in hand goes to extraction first: the one thing the squad can lose.
	for o: Dictionary in todo:
		if String(o.kind) == Objectives.DELIVER_HVT and bool(_hvt(o, sit).get("custody", false)):
			var lz := nearest_lz(sit, from)
			var who := person_name(o)
			if lz.is_empty():
				return {"text": "Bring %s out: call extraction (map, M)" % who, "targets": []}
			return {"text": "Bring %s to %s (%s)" % [who, _lz_name(lz), where_text(from, lz.pos)], "targets": [_lz_target(lz)]}
	var pending := todo.filter(func(o: Dictionary) -> bool:
		return not (String(o.kind) == Objectives.EXTRACT_ITEM and String(o.oid) in sit.get("held", [])))
	var chosen := String(sit.get("chosen", ""))
	if chosen != "":
		for o: Dictionary in live:
			if String(o.get("oid", "")) == chosen and o in pending:
				return _with_oid(_objective_step(o, objectives, sit), o)
	if not pending.is_empty():
		var best: Dictionary = pending[0]
		for o: Dictionary in pending:
			if _flat(from, target_pos(o, sit)) < _flat(from, target_pos(best, sit)):
				best = o
		return _with_oid(_objective_step(best, objectives, sit), best)
	return _extraction_step(objectives, sit)


static func _with_oid(step: Dictionary, o: Dictionary) -> Dictionary:
	step["oid"] = String(o.get("oid", ""))
	return step


## The objectives the player can pick between (the live ones, in list order).
static func pickable(objectives: Array) -> Array:
	return objectives.filter(func(o: Dictionary) -> bool: return o.get("state", "") == Objectives.ACTIVE and String(o.get("kind", "")) != "briefing")


## The next pick after `chosen`: auto ("") -> first -> ... -> last -> auto.
static func next_choice(objectives: Array, chosen: String) -> String:
	var live := pickable(objectives)
	if live.is_empty():
		return ""
	if chosen == "":
		return String(live[0].oid)
	for i in live.size():
		if String(live[i].oid) == chosen:
			return String(live[i + 1].oid) if i + 1 < live.size() else ""
	return ""


## Cycles this player's pick (the N key); refreshes the hint and marker at once.
func cycle_choice() -> void:
	Objectives.chosen_oid = next_choice(_objectives(), Objectives.chosen_oid)
	refresh()


## What to do about objective `o`: head for its site, or the job there.
static func _objective_step(o: Dictionary, all: Array, sit: Dictionary) -> Dictionary:
	var from: Vector3 = sit.get("pos", Vector3.ZERO)
	var at := target_pos(o, sit)
	var p: Dictionary = o.get("params", {})
	var target := {"pos": at, "label": short_label(o, sit), "extract": false, "hide_m": HIDE_INDOORS_M if _is_indoors(o, sit) else HIDE_NEAR_M}
	if p.has("rect"):
		var r: Array = p.rect
		target["rect"] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var site := site_name(o, sit)
	var near := _flat(from, at) <= AT_SITE_M or (target.has("rect") and (target.rect as Rect2).grow(10.0).has_point(Vector2(from.x, from.z)))
	if not near and String(o.kind) != Objectives.FIRE_TARGET:  # (a forward observer's target is called from afar)
		var place := site if site != "" else String(target.label)
		if String(o.kind) in [Objectives.DELIVER_HVT, Objectives.KILL_HVT]:
			return {"text": "Find %s at the %s (%s)" % [person_name(o), place, where_text(from, at)] if site != "" else
				"Find %s (%s)" % [person_name(o), where_text(from, at)], "targets": [target]}
		return {"text": "Head to the %s (%s)" % [place, where_text(from, at)], "targets": [target]}
	var progress := String(o.get("progress", ""))
	var text := ""
	match String(o.kind):
		Objectives.CLEAR_AREA:
			text = "Clear the %s: %s" % [site if site != "" else "area", progress if progress != "" else "search it for hostiles"]
		Objectives.DESTROY_CACHE:
			var thing := String(p.get("name", "cache"))
			text = "Charge set on the %s: get clear" % thing if progress == "charge set" else "Destroy the %s (breaching charge or explosives)" % thing
		Objectives.EXTRACT_ITEM:
			var item := item_name(o)
			if p.has("of_hvt"):
				var holder := _holder_of(o, all)
				text = "Search %s for the %s" % [holder, item] if holder != "" else "Find the %s" % item
			else:
				text = "Find the %s in the building" % item if _is_indoors(o, sit) else "Find the %s" % item
		Objectives.DELIVER_HVT:
			var who := person_name(o)
			var hvt := _hvt(o, sit)
			if String((p.get("person", {}) as Dictionary).get("side", "hostile")) == Person.FRIENDLY:
				text = "Free %s: have them follow you to the LZ" % who
			elif not bool(sit.get("cuffs", true)):
				text = "Capture %s: you need zip cuffs" % who
			elif bool(hvt.get("surrendered", false)):
				text = "%s gave up: cuff them, take them to the LZ" % who
			else:
				text = "Capture %s: cuff them, take them to the LZ" % who
		Objectives.CONVOY:
			text = "Ambush the convoy on its route%s" % (": " + progress if progress != "" else "")
		Objectives.HOLD_POINT:
			text = "Hold the %s%s" % [String(p.get("name", "position")), ": " + progress if progress != "" else ""]
		Objectives.RESCUE_CREW:
			text = "Treat and carry the downed crew to the LZ%s" % (" (" + progress + ")" if progress != "" else "")
		Objectives.DESTROY_VEHICLES:
			text = "Put every vehicle in the %s out of action: a charge on each%s" % [String(p.get("name", "vehicle park")), " (" + progress + ")" if progress != "" else ""]
		Objectives.RECON_SITE:
			text = "Observe the %s from within %d m%s" % [String(p.get("name", "site")), roundi(float(p.get("observe_m", 75.0))), " (" + progress + ")" if progress != "" else ""]
		Objectives.KILL_HVT:
			text = "Kill %s: he walks between the buildings with his guards; take his ID papers off the body" % person_name(o)
		Objectives.DESTROY_WRECK:
			text = "Set a breaching charge on the %s, then get clear" % String(p.get("name", "wreck"))
		Objectives.OVERWATCH:
			text = "Hold the %s and cover the convoy on the road%s" % [String(p.get("name", "overwatch position")), ": " + progress if progress != "" else ""]
		Objectives.FIRE_TARGET:  # the forward observer (ObserverMission): only the guns' kill counts
			text = "Call fire on the %s (Support > Fire support)%s" % [String(p.get("name", "target")), " (" + progress + ")" if progress != "" else ""]
		_:
			text = String(o.get("text", ""))
	return {"text": text, "targets": [target]}


## Everything required is done (or in hand): out by extraction.
static func _extraction_step(objectives: Array, sit: Dictionary) -> Dictionary:
	var from: Vector3 = sit.get("pos", Vector3.ZERO)
	var ext: Dictionary = sit.get("extraction", {})
	var lz := nearest_lz(sit, from)
	var targets: Array = [_lz_target(lz)] if not lz.is_empty() else []
	if bool(ext.get("countdown", false)):
		return {"text": "Extracting in %d s: stay inside" % ceili(float(ext.get("left", 0.0))), "targets": []}
	if not lz.is_empty() and _flat(from, lz.pos) <= float(lz.get("radius", Extraction.RADIUS_M)):
		return {"text": "At %s: extract on the map (M) once everyone's in" % _lz_name(lz), "targets": []}
	var held: Array = sit.get("held", [])
	for o: Dictionary in objectives:
		if String(o.oid) in held and o.get("state", "") == Objectives.ACTIVE:
			return {"text": "Carry the %s out: walk to an LZ or call extraction (map, M)" % item_name(o), "targets": targets}
	return {"text": "All done: call extraction (map, M) or walk to an LZ", "targets": targets}


## The menu's test contract (Briefing): its objectives have no state, so the nearest one.
static func _briefing_step(objectives: Array, from: Vector3) -> Dictionary:
	var best: Dictionary = objectives[0]
	for o: Dictionary in objectives:
		if _flat(from, o.pos) < _flat(from, best.pos):
			best = o
	var target := {"pos": best.pos, "label": String(best.title), "extract": false, "hide_m": HIDE_NEAR_M}
	if _flat(from, best.pos) > float(best.get("radius", 0.0)) + 25.0:
		return {"text": "Head for: %s (%s)" % [String(best.title), where_text(from, best.pos)], "targets": [target]}
	return {"text": String(best.get("text", best.title)), "targets": [target]}


# --- Words --------------------------------------------------------------------------------

## "NE, 340 m": the compass direction (north is -z, as on the map) and the flat distance.
static func where_text(from: Vector3, to: Vector3) -> String:
	return "%s, %s" % [compass(from, to), distance_text(_flat(from, to))]


static func compass(from: Vector3, to: Vector3) -> String:
	var bearing := fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)
	return COMPASS[roundi(bearing / 45.0) % 8]


## Rounded as a soldier would say it: to 5 m close in, 10 m out to a kilometre, then km.
static func distance_text(d: float) -> String:
	if d >= 1000.0:
		return "%.1f km" % (d / 1000.0)
	if d >= 100.0:
		return "%d m" % (roundi(d / 10.0) * 10)
	return "%d m" % maxi(roundi(d / 5.0) * 5, 5)


## The site's name: the contract's target module ("compound", "HQ"), "" when unknown.
static func site_name(o: Dictionary, sit: Dictionary) -> String:
	return String((sit.get("sites", {}) as Dictionary).get(String(o.get("cid", "")), ""))


## Who a DELIVER_HVT is about (their real name), else "the HVT" / "the hostage".
static func person_name(o: Dictionary) -> String:
	var person: Dictionary = (o.get("params", {}) as Dictionary).get("person", {})
	var n := String(person.get("name", ""))
	if n == "":
		var label := String(person.get("label", ""))
		n = label.get_slice("(", 1).trim_suffix(")") if label.contains("(") else ""
	if n != "":
		return n
	return "the hostage" if String(person.get("side", "")) == Person.FRIENDLY else "the HVT"


## What an EXTRACT_ITEM is after, in words ("laptop", "phone").
static func item_name(o: Dictionary) -> String:
	var p: Dictionary = o.get("params", {})
	if String(p.get("name", "")) != "":
		return String(p.name)
	var items: Array = p.get("items", [])
	if not items.is_empty() and ItemDB.has_item(StringName(items[0])):
		return ItemDB.get_item(StringName(items[0])).name.get_slice(" (", 0).to_lower()
	return "item"


## A marker's short label: the item, cache, person or site.
static func short_label(o: Dictionary, sit: Dictionary) -> String:
	var label := ""
	match String(o.get("kind", "")):
		Objectives.DELIVER_HVT, Objectives.KILL_HVT:
			label = person_name(o)
		Objectives.DESTROY_WRECK:
			label = String((o.get("params", {}) as Dictionary).get("name", "wreck"))
		Objectives.OVERWATCH:
			label = "overwatch position"
		Objectives.EXTRACT_ITEM:
			label = item_name(o)
		Objectives.DESTROY_CACHE, Objectives.DESTROY_VEHICLES:
			label = String((o.get("params", {}) as Dictionary).get("name", "cache"))
		Objectives.CONVOY:
			label = "convoy ambush point"
		Objectives.HOLD_POINT:
			label = "hold " + String((o.get("params", {}) as Dictionary).get("name", "position"))
		Objectives.RESCUE_CREW:
			label = "crash site"
		Objectives.RECON_SITE:
			label = "observe " + String((o.get("params", {}) as Dictionary).get("name", "site"))
		Objectives.FIRE_TARGET:
			label = "target: " + String((o.get("params", {}) as Dictionary).get("name", "target"))
		_:
			label = site_name(o, sit)
	if label == "":
		label = "objective"
	return label.left(1).to_upper() + label.substr(1)


## The HVT whose person carries objective `o`'s item (an "of_hvt" piece), by name.
static func _holder_of(o: Dictionary, all: Array) -> String:
	for other: Dictionary in all:
		if other.get("cid") == o.get("cid") and String(other.get("kind", "")) in [Objectives.DELIVER_HVT, Objectives.KILL_HVT]:
			return person_name(other)
	return ""


# --- Places -------------------------------------------------------------------------------

## Where objective `o`'s marker goes: the situation's ground-snapped point, else its "pos".
static func target_pos(o: Dictionary, sit: Dictionary) -> Vector3:
	var where: Dictionary = sit.get("where", {})
	if where.has(String(o.get("oid", ""))):
		return where[String(o.oid)]
	var p: Array = o.get("pos", [0, 0, 0])
	if p.size() < 3:
		return Vector3.ZERO  # (a leg not placed yet: LZ-7)
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func _is_indoors(o: Dictionary, sit: Dictionary) -> bool:
	return String(o.get("oid", "")) in sit.get("indoors", [])


static func _hvt(o: Dictionary, sit: Dictionary) -> Dictionary:
	return (sit.get("hvts", {}) as Dictionary).get(String((o.get("params", {}) as Dictionary).get("hvt", "")), {})


## The extraction point to make for: a called one (grid or smoke: where the helicopter goes),
## else the nearest. {} for none.
static func nearest_lz(sit: Dictionary, from: Vector3) -> Dictionary:
	var best := {}
	for lz: Dictionary in sit.get("lzs", []):
		if String(lz.get("source", "zone")) != "zone":
			return lz
		if best.is_empty() or _flat(from, lz.pos) < _flat(from, best.pos):
			best = lz
	return best


static func _lz_name(lz: Dictionary) -> String:
	var n := String(lz.get("name", ""))
	return n if n != "" else "the LZ"


static func _lz_target(lz: Dictionary) -> Dictionary:
	var n := String(lz.get("name", ""))
	return {"pos": lz.pos, "label": n if n != "" else "LZ", "extract": true, "hide_m": float(lz.get("radius", Extraction.RADIUS_M)) * 0.5}


## The deployment's objectives that play in this level (Objectives.here) and have a place.
func _here() -> Array:
	var lvl := CompoundLevel.current(self) if is_inside_tree() else null
	return Contracts.objectives.list.filter(func(o: Dictionary) -> bool:
		return Objectives.here(o, lvl) and (o.get("pos", []) as Array).size() >= 3)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- The situation (this peer's view of the level) ------------------------------------------

## The objectives the step is worked from: the deployment's in this zone (LZ-7: a leg in another
## zone has no place here), else the briefing's stand-ins.
func _objectives() -> Array:
	if not Contracts.objectives.list.is_empty():
		return _here()
	var briefing := MapNodes.briefing(self)
	if briefing == null or not briefing.is_deployed():
		return []
	var out: Array = []
	for o: Dictionary in briefing.contract.get("objectives", []):
		var p: Variant = o.get("pos")
		if p is Array and (p as Array).size() >= 2:
			out.append({"kind": "briefing", "title": String(o.get("title", "Objective")), "text": String(o.get("text", "")),
				"radius": float(o.get("radius", 0.0)), "pos": _ground(Vector2(float(p[0]), float(p[1])))})
	return out


## What the step needs from the level, all of it replicated: "pos" (the player), "sites"
## (cid -> the target module's name), "where" (oid -> marker point, areas on the ground),
## "indoors" (oids whose point has a roof over it), "hvts" (hvt id -> {"found", "custody",
## "surrendered"}), "held" (oids whose item the squad carries), "cuffs" (the player has zip
## cuffs), "lzs" ([{"name", "pos", "radius", "source"}]) and "extraction" ({"countdown",
## "left"}).
func situation() -> Dictionary:
	var sit := {"chosen": Objectives.chosen_oid, "pos": player.global_position if player and is_instance_valid(player) else Vector3.ZERO,
		"sites": {}, "where": {}, "indoors": [], "hvts": {}, "held": [], "lzs": [], "extraction": {}}
	if player and is_instance_valid(player):
		sit["cuffs"] = player.inventory.count_of(Person.ZIP_CUFFS) > 0
	var squad: Array[Soldier] = []
	squad.append_array(MapNodes.players(self))
	squad.append_array(MapNodes.squad_ai(self))
	var carried: Array = []
	for s: Soldier in squad:
		if s.vitals.is_dead():
			continue
		carried.append_array(Contracts.inventory_items(s.inventory))
	var layer := PeopleLayer.find(self)
	for o: Dictionary in _here():
		var cid := String(o.get("cid", ""))
		if not sit.sites.has(cid):
			sit.sites[cid] = _site_name_of(cid)
		var p: Dictionary = o.get("params", {})
		var at := target_pos(o, {})
		if p.has("rect"):
			at = _ground(Vector2(at.x, at.z))
		sit.where[String(o.oid)] = at + Vector3.UP * (0.0 if p.has("rect") else 1.0)
		if p.has("pos") and _roofed(at):
			sit.indoors.append(String(o.oid))
		if String(o.kind) == Objectives.EXTRACT_ITEM and carried.any(func(e: Dictionary) -> bool: return Objectives.entry_matches(p, e)):
			sit.held.append(String(o.oid))
		if String(o.kind) == Objectives.DELIVER_HVT and p.has("hvt"):
			sit.hvts[String(p.hvt)] = _hvt_now(layer, String(p.hvt), squad)
	var ext := MapNodes.extraction(self)
	if ext and ext.is_active():
		for point: Dictionary in ext.shown_points():  # a helicopter extraction: its LZ only
			var v: Vector2 = point.pos
			sit.lzs.append({"name": String(point.get("name", "")), "pos": _ground(v), "radius": float(point.get("radius", Extraction.RADIUS_M)),
				"source": String(point.get("source", "zone"))})
		sit.extraction = {"countdown": ext.state == Extraction.State.COUNTDOWN, "left": ext.countdown_left}
	if sit.lzs.is_empty():
		for node in get_tree().get_nodes_in_group(DeliveryPoint.GROUP):
			if node is Node3D and not node.is_queued_for_deletion():
				sit.lzs.append({"name": String(node.get(&"label")) if node.get(&"label") != null else "", "pos": (node as Node3D).global_position,
					"radius": DeliveryPoint.radius_of(node), "source": "zone"})
	return sit


## The contract's target module by name ("compound"), on any peer (its public view).
func _site_name_of(cid: String) -> String:
	var c := Contracts.contract(cid)
	var n := MissionRegistry.module_name(String(c.module)) if String(c.get("module", "")) != "" else String(c.get("module_name", ""))
	if n == "" and Contracts.deployment().has("module"):
		n = MissionRegistry.module_name(String(Contracts.deployment().module))
	return n


## Where HVT `hvt_id` stands with the squad: "found" (their body is in the level), "custody"
## (led or carried by the squad, or a captive or friendly with someone from it beside them, as
## PeopleLayer._escort counts it) and "surrendered" (gave up, not yet cuffed).
func _hvt_now(layer: PeopleLayer, hvt_id: String, squad: Array[Soldier]) -> Dictionary:
	var body := layer.hvt(hvt_id) if layer else null
	if body == null or body.vitals.is_dead():
		return {"found": false}
	var st := layer.state_of(body)
	if bool(st.get("delivered", false)):
		return {"found": true}
	var custody := is_instance_valid(body.carried_by) and body.carried_by.faction == &"friendly"
	var leader := String(st.get("led_by", ""))
	var led_by := layer.level.get_node_or_null(NodePath(leader)) as Soldier if leader != "" and layer.level else null
	custody = custody or (led_by != null and led_by.faction == &"friendly")
	var friendly := StringName(st.get("side", "")) == Person.FRIENDLY
	if not custody and (friendly or bool(st.get("cuffed", false))):
		for s: Soldier in squad:
			if s.vitals.is_up() and s.global_position.distance_to(body.global_position) <= PeopleLayer.ESCORT_M:
				custody = true
				break
	return {"found": true, "custody": custody, "surrendered": bool(st.get("surrendered", false)) and not bool(st.get("cuffed", false))}


## The ground at (x, z) (or the player's height there when it can't be read yet).
func _ground(at: Vector2) -> Vector3:
	var space := get_viewport().find_world_3d().direct_space_state if is_inside_tree() and get_viewport().find_world_3d() else null
	if space:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.y), Vector3(at.x, -100.0, at.y), 1))
		if not hit.is_empty():
			return hit.position
	var y := player.global_position.y if player and is_instance_valid(player) else 0.0
	return Vector3(at.x, y, at.y)


## Whether something is overhead within 12 m of `at` (a roof: the point is inside a building).
## Worked out once per point; a roof blown off later doesn't matter for a hint.
func _roofed(at: Vector3) -> bool:
	var key := Vector3i(at.round())
	if _indoors.has(key):
		return _indoors[key]
	var space := get_viewport().find_world_3d().direct_space_state if is_inside_tree() and get_viewport().find_world_3d() else null
	if space == null:
		return false
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.6, at + Vector3.UP * 12.0, 1))
	_indoors[key] = not hit.is_empty()
	return _indoors[key]


# --- Markers ------------------------------------------------------------------------------

## Where target `t` goes on the screen for `camera` in a view of `view` pixels:
## {"screen": Vector2, "edge": bool}. A point behind the camera or off the screen sits on
## the edge (inset EDGE_PX) in its direction.
static func place_on_screen(camera: Camera3D, view: Vector2, pos: Vector3) -> Dictionary:
	var centre := view * 0.5
	var local := camera.global_transform.affine_inverse() * pos
	var screen := camera.unproject_position(pos) if local.z < -0.05 else Vector2.ZERO
	var inner := Rect2(Vector2.ONE * EDGE_PX, view - Vector2.ONE * EDGE_PX * 2.0)
	if local.z < -0.05 and inner.has_point(screen):
		return {"screen": screen, "edge": false}
	# Behind (or off to a side): the direction on screen is the point's camera-space x and y.
	var dir := (screen - centre) if local.z < -0.05 else Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2.DOWN  # straight behind: point down, as if to turn round
	var half := inner.size * 0.5
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	return {"screen": centre + dir * k, "edge": true}


## The markers for the current step's targets as they go on the screen now (see `drawn`):
## none with markers_on off or nothing shown, none for a target the player is inside or
## close to.
func layout_markers() -> Array:
	var out: Array = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not markers_on or not bool(GameSettings.get_value("hud", "objective_markers")) or not _shown() or camera == null:
		return out
	var from := player.global_position
	var view := size if size.x > 0.0 else get_viewport_rect().size
	for t: Dictionary in current.get("targets", []):
		var pos: Vector3 = t.pos
		var d := _flat(from, pos)
		if t.has("rect"):
			if (t.rect as Rect2).has_point(Vector2(from.x, from.z)):
				continue  # inside the area: no marker
		elif d <= float(t.get("hide_m", HIDE_NEAR_M)):
			continue
		var place := place_on_screen(camera, view, pos)
		var f := clampf(d / FADE_M, 0.0, 1.0)
		out.append({"pos": pos, "label": String(t.get("label", "")), "screen": place.screen, "edge": place.edge, "distance": d,
			"alpha": lerpf(ALPHA_NEAR, ALPHA_FAR, f), "size": lerpf(SIZE_NEAR, SIZE_FAR, f), "extract": bool(t.get("extract", false))})
	return out


func _draw() -> void:
	var font := UiKit.FONT_STRONG
	var fs := UiKit.FONT_HUD_SMALL
	for m: Dictionary in drawn:
		var alpha: float = m.alpha
		var s: float = m.size
		var colour: Color = EXTRACT_COLOUR if bool(m.extract) else OBJECTIVE_COLOUR
		colour.a = alpha
		var at: Vector2 = m.screen
		var shadow := Color(UiKit.OUTLINE, alpha * UiKit.OUTLINE.a)
		if m.edge:
			# Off screen or behind: a small arrow at the edge, nothing else.
			var dir := (at - size * 0.5).normalized()
			var side := Vector2(-dir.y, dir.x)
			var tip := at + dir * s * 1.2
			draw_colored_polygon(PackedVector2Array([tip, at - dir * s * 0.6 + side * s, at - dir * s * 0.6 - side * s]), colour)
			continue
		var diamond := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)])
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), shadow, 3.0, true)
		draw_colored_polygon(diamond, colour)
		var label := String(m.label)
		if label != "":
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, at + Vector2(-w * 0.5, -s - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, shadow)
			draw_string(font, at + Vector2(-w * 0.5, -s - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
		var dist := distance_text(float(m.distance))
		var dw := font.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, at + Vector2(-dw * 0.5, s + 17.0), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, shadow)
		draw_string(font, at + Vector2(-dw * 0.5, s + 17.0), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
