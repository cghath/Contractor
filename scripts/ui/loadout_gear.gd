class_name LoadoutGear
extends Control
## The 3D loadout editor in a survival world (docs/survival_clothing.md, calls 133-134): the
## same screen idea as the base's LoadoutEditor (the person's body in 3D, LoadoutPreview, the
## slots as markers on it), but on a real kit in the field, item by item, with no stash and no
## buying: your own kit, or a companion's (the talk menu's "Gear" on one within reach).
##
## Left, their body in 3D wearing what they wear now, the clothing slots marked too; the middle,
## their kit place by place: every body slot (gear and clothes), every MOLLE point, and the
## containers you can put things INTO: the pockets (the clothes' pockets add to them), the vest,
## the backpack and each pouch on the carrier or pack, with litres used of what it holds. Right,
## your own kit (when it's a companion's), and beside it their needs, mood, clothes and warmth.
##
## Pick a place (click its header or its marker on the body), then Give (your row) or Move (their
## row) puts one unit there; Take brings one back to you. Drag a row onto a place header or onto
## a marker on the body does the same. Saved kits: save theirs by name, apply one to them (from
## what you carry). Everything goes through the host (CompanionGear), which keeps Inventory's
## capacity rules and says why something won't go. Esc or Close shuts it.

const LAYER := 22
const NODE_NAME := &"LoadoutGearLayer"
const POLL_S := 0.25
const HELP := [
	"Click a place in their kit (or its marker on the body) to pick it, then Give one of your things or Move one of theirs into it.",
	"Places include the pockets, the vest, the backpack and every pouch: things go INTO them, within what each holds.",
	"Take brings one back to you. Drag a row onto a place or a marker does the same as the buttons.",
	"Save their kit by name, or apply a saved kit to them from what you carry.",
]

var actor: Soldier
var target: Soldier
## The place picked in their kit ("" none: wherever it fits).
var place := ""
## The host's answer to the last op ("" done); what a client sent is answered by a message.
var last := ""
var info: Dictionary = {}
var preview: LoadoutPreview
var title_label: Label
var theirs_box: VBoxContainer
var mine_box: VBoxContainer
var info_box: VBoxContainer
var kits_box: VBoxContainer
var person_pick: OptionButton
var status: Label
var kit_name: LineEdit
var _hash := 0
var _poll := 0.0
var _people: Array[Soldier] = []


## Opens the editor on `target`'s kit (`actor`'s own when target is actor) for the local
## `actor`; replaces one already open. Returns it.
static func open_on(p_actor: Soldier, p_target: Soldier) -> LoadoutGear:
	if p_actor == null:
		return null
	var old := p_actor.get_node_or_null(NodePath(NODE_NAME))
	if old:
		old.queue_free()
		p_actor.remove_child(old)
	var layer := CanvasLayer.new()
	layer.name = NODE_NAME
	layer.layer = LAYER
	var ed := LoadoutGear.new()
	ed.actor = p_actor
	ed.target = p_target if p_target else p_actor
	layer.add_child(ed)
	p_actor.add_child(layer)
	return ed


## The editor open on `p_actor`, or null.
static func current(p_actor: Node) -> LoadoutGear:
	if p_actor == null or not is_instance_valid(p_actor):
		return null
	var layer := p_actor.get_node_or_null(NodePath(NODE_NAME))
	return layer.get_child(0) as LoadoutGear if layer and layer.get_child_count() > 0 else null


func _ready() -> void:
	name = "LoadoutGear"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.apply(self)
	var panel := UiKit.panel(true)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	panel.add_child(root)
	var head := UiKit.header("Gear", "Give, take and move gear on the body itself: into slots, onto points, and into pockets and pouches.",
		PackedStringArray(HELP), [["Click", "Pick a place"], ["Drag", "Put it there"], ["Esc", "Close"]], false)
	var top := head.get_child(0) as HBoxContainer
	title_label = top.get_child(0) as Label
	person_pick = OptionButton.new()
	person_pick.tooltip_text = "Whose kit"
	person_pick.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _people.size():
			select_target(_people[i]))
	top.add_child(person_pick)
	top.add_child(UiKit.button("Close [Esc]", close, "Close the gear editor (Esc)"))
	root.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	root.add_child(body)
	preview = LoadoutPreview.new()
	preview.clothing = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.slot_clicked.connect(func(key: String) -> void: pick_place(place_of_marker(key)))
	preview.set_drag_forwarding(Callable(), _can_drop_preview, _drop_preview)
	body.add_child(preview)
	theirs_box = _column(body, "Their kit")
	mine_box = _column(body, "Your kit")
	var side := _column(body, "")
	info_box = UiKit.section("How they are", side)
	kits_box = UiKit.section("Saved kits", side)
	status = UiKit.text("")
	root.add_child(status)
	select_target(target)


func _column(parent: Control, heading: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	if heading != "":
		box.add_child(UiKit.heading(heading))
	return box


func _exit_tree() -> void:
	var layer: SurvivorsLayer = SurvivorsLayer.find(actor) if actor and is_instance_valid(actor) else null
	if layer and layer.gear_info.is_connected(_on_info):
		layer.gear_info.disconnect(_on_info)


## Edits `t`'s kit (a companion near you, or yourself).
func select_target(t: Soldier) -> void:
	target = t if t and is_instance_valid(t) else actor
	place = ""
	_fill_people()
	if preview and target.model:
		preview.set_look({"variant": target.model.variant, "body": target.model.body, "face": target.model.face, "name_tape": target.model.name_tape})
	var layer := SurvivorsLayer.find(actor)
	if layer and not layer.gear_info.is_connected(_on_info):
		layer.gear_info.connect(_on_info)
	info = {}
	if target != actor:
		send({"op": "info"})
	_hash = 0
	refresh()


func _fill_people() -> void:
	if person_pick == null:
		return
	_people = [actor]
	var layer := SurvivorsLayer.find(actor)
	if layer:
		for c: Soldier in layer.companions():
			if c != actor and is_instance_valid(c) and c.global_position.distance_to(actor.global_position) <= CompanionGear.REACH_M:
				_people.append(c)
	if target not in _people:
		_people.append(target)
	person_pick.clear()
	for i in _people.size():
		person_pick.add_item("You" if _people[i] == actor else _people[i].display_name())
		if _people[i] == target:
			person_pick.select(i)


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_S
	if target == null or not is_instance_valid(target) or actor == null or not is_instance_valid(actor):
		close()
		return
	if target != actor and actor.global_position.distance_to(target.global_position) > CompanionGear.REACH_M + 1.0:
		close()
		return
	refresh()


## Rebuilds the lists and the body when either kit changed.
func refresh() -> void:
	var h := hash([target.inventory.net_state, actor.inventory.net_state, place, info])
	if h == _hash:
		return
	_hash = h
	title_label.text = "Gear: %s" % ("you" if target == actor else target.display_name())
	if preview and preview.inventory:
		preview.show_gear(Roster.json_safe(target.inventory.net_state))
		preview.selected = marker_of_place(place)
	_build_theirs()
	_build_mine()
	_build_info()
	_build_kits()


# --- What's where --------------------------------------------------------------------------------

## The places of `inv` in the order shown: [{"place", "label", "entries": [[label, from, index]]}].
static func places_of(inv: Inventory) -> Array:
	var out: Array = []
	for slot: StringName in Inventory.all_slots():
		if slot in Inventory.PLATE_SLOTS and inv.slots.get(&"vest", &"") == &"":
			continue
		if slot == &"exo" or slot == &"launcher":
			if inv.slots.get(slot, &"") == &"":
				continue
		var id := StringName(inv.slots.get(slot, &""))
		var label := String(Clothing.NAMES.get(slot, String(slot).replace("_", " ").capitalize()))
		var entries: Array = []
		if id != &"":
			entries.append([ItemDB.get_item(id).name, "slot:" + String(slot), -1])
		out.append({"place": "slot:" + String(slot), "label": label, "entries": entries})
	for p: Dictionary in inv.attach_points():
		var att := inv.attachment(StringName(p.id))
		var entries: Array = []
		if not att.is_empty():
			entries.append([ItemDB.get_item(StringName(att.id)).name, "point:" + String(p.id), -1])
		out.append({"place": "point:" + String(p.id), "label": "%s point (%s)" % [Inventory.types_text(Inventory.point_types(p), "/"), String(p.id)], "entries": entries})
	for c: StringName in inv.search_containers():
		if inv.capacity(c) <= 0.0:
			continue
		var entries: Array = []
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			var it := ItemDB.get_item(StringName(String(list[i].id)))
			entries.append(["%s%s" % [it.name if it else String(list[i].id), " x%d" % int(list[i].count) if int(list[i].count) > 1 else ""], "container:" + String(c), i])
		var pouch: ItemData = inv.pouch_item(c) if Inventory.is_pouch_container(c) else null
		var units := int(pouch.stats.get("max_units", 0)) if pouch else 0
		var room := "%d of %d" % [inv.units_in(c), units] if units > 0 else "%.1f of %.1f L" % [inv.used(c), inv.capacity(c)]
		out.append({"place": "container:" + String(c), "label": "%s (%s)" % [inv.container_label(c), room], "entries": entries})
	return out


## The place a marker on the body stands for.
static func place_of_marker(key: String) -> String:
	if key == "pockets":
		return "container:pockets"
	if key.begins_with("slot:") or key.begins_with("point:"):
		return key
	return ""


static func marker_of_place(p: String) -> String:
	if p == "container:pockets":
		return "pockets"
	return p if p.begins_with("slot:") or p.begins_with("point:") else ""


func pick_place(p: String) -> void:
	place = "" if p == place else p
	_hash = 0
	refresh()


func _build_theirs() -> void:
	_clear(theirs_box)
	for pl: Dictionary in places_of(target.inventory):
		var head := UiKit.button(("> " if String(pl.place) == place else "") + String(pl.label), pick_place.bind(String(pl.place)),
			"Pick this place: Give or Move puts things here")
		head.set_drag_forwarding(Callable(), _can_drop_place, _drop_place.bind(String(pl.place)))
		theirs_box.add_child(head)
		for e: Array in pl.entries:
			var row := HBoxContainer.new()
			var lab := UiKit.text("    " + String(e[0]))
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(lab)
			var data := {"side": "theirs", "from": String(e[1]), "index": int(e[2]), "label": String(e[0])}
			row.set_drag_forwarding(func(_at: Vector2) -> Variant: return data, Callable(), Callable())
			if target != actor:
				row.add_child(UiKit.button("Take", take.bind(String(e[1]), int(e[2])), "Take one back"))
			if place != "" and place != String(e[1]):
				row.add_child(UiKit.button("Move", move.bind(String(e[1]), int(e[2]), place), "Move one to the picked place"))
			theirs_box.add_child(row)


func _build_mine() -> void:
	_clear(mine_box)
	(mine_box.get_parent() as Control).visible = target != actor
	if target == actor:
		return
	var head := UiKit.text("Drag here or press Take to bring something back")
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.set_drag_forwarding(Callable(), _can_drop_mine, _drop_mine)
	mine_box.add_child(head)
	for c: StringName in actor.inventory.search_containers():
		var list: Array = actor.inventory.containers.get(c, [])
		if list.is_empty():
			continue
		mine_box.add_child(UiKit.heading(actor.inventory.container_label(c)))
		for i in list.size():
			var it := ItemDB.get_item(StringName(String(list[i].id)))
			var label := "%s%s" % [it.name if it else String(list[i].id), " x%d" % int(list[i].count) if int(list[i].count) > 1 else ""]
			var row := HBoxContainer.new()
			var lab := UiKit.text("    " + label)
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(lab)
			var data := {"side": "mine", "from": "container:" + String(c), "index": i, "label": label}
			row.set_drag_forwarding(func(_at: Vector2) -> Variant: return data, Callable(), Callable())
			row.add_child(UiKit.button("Give", give.bind(c, i, place if place != "" else "auto"),
				"Give one %s" % ("to the picked place" if place != "" else "(wherever it goes)")))
			mine_box.add_child(row)


func _build_info() -> void:
	_clear(info_box)
	info_box.add_child(UiKit.heading("How they are" if target != actor else "You"))
	var lines := PackedStringArray()
	var n: Dictionary = info.get("needs", {})
	if not n.is_empty():
		for k: String in ["hunger", "thirst", "sleep", "warmth", "wet"]:
			if n.has(k):
				lines.append("%s: %s" % [k.capitalize(), String(n[k])])
	if info.has("band"):
		lines.append("Mood: %s (%.0f)" % [String(info.band), float(info.get("mood", 0.0))])
	var clothes: Array = info.get("clothes", Array(Clothing.lines_of(target.inventory, target.get_meta(&"needs", {}))))
	for l: Variant in clothes:
		lines.append(String(l))
	lines.append("Clothes keep off %d%% of the cold; steps x%.2f" % [roundi(float(info.get("warmth", Clothing.inv_warmth(target.inventory))) * 100.0), Clothing.noise_of(target.inventory)])
	lines.append("Carrying %.1f kg" % target.inventory.total_mass())
	var lab := UiKit.text("\n".join(lines))
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(lab)


func _build_kits() -> void:
	_clear(kits_box)
	kits_box.add_child(UiKit.heading("Saved kits"))
	kit_name = UiKit.search_field("Kit name...")
	kits_box.add_child(kit_name)
	kits_box.add_child(UiKit.button("Save their kit" if target != actor else "Save my kit", func() -> void: save_kit(kit_name.text), "Save what they wear and carry as a kit"))
	var names: Array = info.get("kits", CompanionGear.kits().keys() if multiplayer.is_server() else [])
	for k: Variant in names:
		kits_box.add_child(UiKit.button("Apply: %s" % String(k), apply_kit.bind(String(k)), "Put this kit on them from what you carry"))


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- Ops (each goes to the host: CompanionGear) ----------------------------------------------------

## One of yours (container `from`, entry `index`) into `to` of theirs ("auto": wherever it goes).
func give(from: StringName, index: int, to := "auto") -> String:
	return send({"op": "give", "from": "container:" + String(from), "index": index, "to": to})


## One of theirs (place `from`, entry `index` for a container) back to you.
func take(from: String, index := -1) -> String:
	return send({"op": "take", "from": from, "index": index, "to": "auto"})


## One of theirs from `from` into `to` of their own kit (filling a pouch, a pocket).
func move(from: String, index: int, to: String) -> String:
	return send({"op": "move", "from": from, "index": index, "to": to})


func save_kit(kit: String) -> String:
	return send({"op": "kit_save", "name": kit})


func apply_kit(kit: String) -> String:
	return send({"op": "kit_apply", "name": kit})


## Sends `op` to the host (on the host: does it now and returns why not, "" done).
func send(op: Dictionary) -> String:
	last = ""
	if multiplayer.is_server():
		last = CompanionGear.server_op(actor, target, op)
	else:
		var layer := SurvivorsLayer.find(actor)
		if layer:
			layer.request_talk.rpc_id(1, "gear", target.get_path(), op)
	if status:
		status.text = last
	_hash = 0
	if String(op.get("op", "")) != "info" and target != actor:
		_ask_info.call_deferred()
	return last


func _ask_info() -> void:
	if is_instance_valid(target) and target != actor and not multiplayer.is_server():
		send({"op": "info"})
	elif is_instance_valid(target) and target != actor:
		info = CompanionGear.info_of(target)
		_hash = 0


func _on_info(i: Dictionary) -> void:
	if target and is_instance_valid(target) and String(i.get("path", "")) == String(target.get_path()):
		info = i
		_hash = 0


# --- Drag and drop -------------------------------------------------------------------------------

func _can_drop_place(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("side")


func _drop_place(_at: Vector2, data: Variant, to: String) -> void:
	_drop_into(data as Dictionary, to)


func _can_drop_preview(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("side") and place_of_marker(preview.key_at(at)) != ""


func _drop_preview(at: Vector2, data: Variant) -> void:
	_drop_into(data as Dictionary, place_of_marker(preview.key_at(at)))


func _can_drop_mine(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and String((data as Dictionary).get("side", "")) == "theirs" and target != actor


func _drop_mine(_at: Vector2, data: Variant) -> void:
	var d := data as Dictionary
	take(String(d.from), int(d.index))


func _drop_into(d: Dictionary, to: String) -> void:
	if to == "":
		return
	if String(d.get("side", "")) == "mine":
		send({"op": "give", "from": String(d.from), "index": int(d.index), "to": to})
	else:
		move(String(d.from), int(d.index), to)


# --- Keys and closing ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.pressed and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif not get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()  # the editor has the keys, not the body behind it


func close() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var layer := get_parent()
	if layer and layer.name == NODE_NAME:
		layer.queue_free()
	else:
		queue_free()
