class_name PalletField
extends Node
## The supply pallets of a zone and what players have tagged (feat/pallet-tagging, Pallets,
## docs/pallets.md): a child of the zone level on every peer. Pallets are built on every peer
## from the same site table (Pallets.sites, by module), abandoned vehicles are parked by the host
## (server_spawn_vehicles); a TAG ("sell", or "gift" with a faction) is the only shared state. The
## host decides every tag (reach checked), tells everyone, tells a joiner them all, marks them on
## the map (MapMarkers) and, at extraction, lists them as lots (lots()).
##
## Keys: a pallet's uid ("<module>_pal<n>"), a vehicle's "v:<vehicle id>".

signal tags_changed

const GROUP := &"pallet_field"
const VEHICLE_PREFIX := "v:"
const SELL_COLOUR := Color("f0a030")
const GIFT_COLOUR := Color("4fd06a")

var level: Node
## Every peer: key -> {"mode": "sell" | "gift", "faction": String}.
var tags: Dictionary = {}
var pallets: Dictionary = {}  # uid -> SupplyPallet
var _markers: Dictionary = {}  # host: key -> MapMarkers id


func _init() -> void:
	name = "PalletField"


func _ready() -> void:
	add_to_group(GROUP)
	level = get_parent()
	Net.peer_joined.connect(_on_peer_joined)


static func of(node: Node) -> PalletField:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as PalletField


## Builds the pallets of `modules` (ZoneModule list) on the ground (`ground`: a Callable
## Vector3 -> Vector3, the zone's ground_point). Same on every peer.
func build(modules: Array, ground: Callable) -> void:
	for m: ZoneModule in modules:
		var i := 0
		for site: Dictionary in Pallets.sites(m.type):
			var uid := "%s_pal%d" % [m.module_id, i]
			i += 1
			if pallets.has(uid):
				continue
			var p := SupplyPallet.new(uid, String(site.kind))
			p.field = self
			add_child(p)
			p.global_position = (ground.call(m.to_global(Vector3(float(site.x), 0.0, float(site.z)))) as Vector3) - Vector3.UP * 0.1
			pallets[uid] = p


## Host: parks the abandoned vehicles of `modules` through the level's VehicleLayer.
func server_spawn_vehicles(modules: Array) -> void:
	var layer := get_parent().get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null or not multiplayer.is_server():
		return
	for m: ZoneModule in modules:
		var i := 0
		for e: Dictionary in Pallets.site_vehicles(m.type):
			var id := "%s_abv%d" % [m.module_id, i]
			i += 1
			var at: Vector3 = m.to_global(Vector3(float(e.x), 0.0, float(e.z)))
			var ground := get_parent().call(&"ground_point", at) as Vector3
			for v: Vehicle in layer.server_place_parked([{"id": id, "model": String(e.model), "faction": "hostile", "pos": ground, "yaw": float(e.get("yaw", 0.0))}]):
				v.set_meta(&"no_save", true)
				v.set_meta(&"abandoned", true)
				if bool(e.get("off", false)):
					v.server_set_fuel(0.0)


# --- Reading tags (every peer) ------------------------------------------------------------------

func tag_of(key: String) -> Dictionary:
	return tags.get(key, {})


static func vehicle_key(v: Vehicle) -> String:
	return VEHICLE_PREFIX + v.vehicle_id


## "TAG: SELL" / "GIFT: Name", "" when not tagged.
func tag_text(key: String) -> String:
	var t := tag_of(key)
	if t.is_empty():
		return ""
	return "TAG: SELL" if String(t.mode) == "sell" else "GIFT: %s" % MissionRegistry.faction_name(String(t.faction))


## The menu entries for tagging the thing with `key` (a pallet or vehicle `target`): Tag to sell,
## a "Tag for..." submenu of the employers, Untag when tagged.
func tag_entries(key: String, target: Node, _actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := tag_of(key)
	var field := self
	out.append({"id": &"tag_sell", "label": "Tag to sell", "disabled": "Already tagged to sell" if String(t.get("mode", "")) == "sell" else "",
		"target": target, "call": func() -> void: field.request_tag(key, "sell", "")})
	var items: Array[Dictionary] = []
	for f: String in Pallets.gift_factions():
		var faction := f
		var same: bool = String(t.get("mode", "")) == "gift" and String(t.get("faction", "")) == f
		items.append({"id": &"tag_gift", "label": MissionRegistry.faction_name(f), "disabled": "Already tagged for them" if same else "",
			"target": target, "call": func() -> void: field.request_tag(key, "gift", faction)})
	out.append({"id": &"tag_for", "label": "Tag for...", "disabled": "" if not items.is_empty() else "No faction to gift to", "items": items, "target": target})
	if not t.is_empty():
		out.append({"id": &"untag", "label": "Untag (%s)" % tag_text(key).to_lower(), "disabled": "", "target": target,
			"call": func() -> void: field.request_tag(key, "none", "")})
	return out


## Shows `text` to `actor` on its HUD (when it is the local player).
static func say(actor: Node, text: String) -> void:
	var s := actor as Soldier
	if s and s.player_input:
		s.player_input.flash(text)


# --- Tagging -----------------------------------------------------------------------------------

## Any peer: asks to tag (mode "sell" or "gift" with `faction`) or untag (mode "none").
func request_tag(key: String, mode: String, faction: String) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		server_tag(key, mode, faction, 1)
	else:
		_rq_tag.rpc_id(1, key, mode, faction)


@rpc("any_peer", "call_remote", "reliable")
func _rq_tag(key: Variant, mode: Variant, faction: Variant) -> void:
	if not multiplayer.is_server() or typeof(key) != TYPE_STRING or typeof(mode) != TYPE_STRING or typeof(faction) != TYPE_STRING:
		return
	server_tag(String(key), String(mode), String(faction), multiplayer.get_remote_sender_id())


## Host: tags `key` for `peer` if it is a real pallet or vehicle within reach and the tag is
## valid. Returns "" or why not.
func server_tag(key: String, mode: String, faction: String, peer := 1) -> String:
	var why := _tag_refusal(key, mode, faction, peer)
	if why != "":
		_say_to(peer, why)
		return why
	_apply.rpc(key, mode, faction)
	_set_marker(key, mode, faction)
	return ""


func _tag_refusal(key: String, mode: String, faction: String, peer: int) -> String:
	if mode not in ["sell", "gift", "none"]:
		return "Bad tag"
	if mode == "gift" and not faction in Pallets.gift_factions():
		return "Pick a faction to gift it to"
	var at: Variant = position_of(key)
	if at == null:
		return "Nothing there to tag"
	var is_vehicle := key.begins_with(VEHICLE_PREFIX)
	if is_vehicle:
		var v := vehicle_of(key)
		if v == null or v.faction == &"player" or not v.occupants().is_empty():
			return "That vehicle isn't yours to tag"
	var who := get_parent().get_node_or_null("Players/%d" % peer) as Node3D
	if who != null and who.global_position.distance_to(at as Vector3) > Pallets.num("reach_m", 7.0) + (4.0 if is_vehicle else 0.0):
		return "Too far away to tag"
	return ""


func _say_to(peer: int, text: String) -> void:
	if peer == 1 or not multiplayer.has_multiplayer_peer():
		say(get_parent().get_node_or_null(^"Players/1"), text)
	else:
		_note.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _note(text: String) -> void:
	say(get_parent().get_node_or_null("Players/%d" % multiplayer.get_unique_id()), text)


@rpc("authority", "call_local", "reliable")
func _apply(key: String, mode: String, faction: String) -> void:
	if mode == "none":
		tags.erase(key)
	else:
		tags[key] = {"mode": mode, "faction": faction if mode == "gift" else ""}
	_redraw(key)
	tags_changed.emit()


func _redraw(key: String) -> void:
	var text := tag_text(key)
	var colour := SELL_COLOUR if String(tag_of(key).get("mode", "")) == "sell" else GIFT_COLOUR
	if pallets.has(key):
		(pallets[key] as SupplyPallet).show_tag(text, colour)
	elif key.begins_with(VEHICLE_PREFIX):
		var v := vehicle_of(key)
		if v == null:
			return
		var label := v.get_node_or_null(^"TagLabel") as Label3D
		if text == "":
			if label:
				label.queue_free()
			return
		if label == null:
			label = Label3D.new()
			label.name = "TagLabel"
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 48
			label.pixel_size = 0.005
			label.no_depth_test = true
			label.position.y = 3.2
			v.add_child(label)
		label.text = text
		label.modulate = colour


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_snapshot.rpc_id(id, tags)


@rpc("authority", "call_remote", "reliable")
func _snapshot(all: Dictionary) -> void:
	tags = all.duplicate(true)
	for key: String in tags:
		_redraw(key)
	tags_changed.emit()


# --- Markers on the map (host) --------------------------------------------------------------------

func _set_marker(key: String, mode: String, faction: String) -> void:
	var markers := MapNodes.markers(self)
	if markers == null:
		return
	if _markers.has(key):
		markers.server_remove(int(_markers[key]))
		_markers.erase(key)
	var at: Variant = position_of(key)
	if mode == "none" or at == null:
		return
	var pos := at as Vector3
	var text := "Sell: %s" % _name_of(key) if mode == "sell" else "Gift %s: %s" % [MissionRegistry.faction_name(faction), _name_of(key)]
	var id := markers.server_add({"kind": "point", "points": PackedVector2Array([Vector2(pos.x, pos.z)]), "text": text,
		"colour": "orange" if mode == "sell" else "green", "channel": "field", "author": 0})
	if id > 0:
		_markers[key] = id


func _name_of(key: String) -> String:
	if pallets.has(key):
		return Pallets.kind_name((pallets[key] as SupplyPallet).kind)
	var v := vehicle_of(key)
	return v.display_name() if v else "vehicle"


# --- What's where -----------------------------------------------------------------------------------

## Where the tagged thing is (Vector3), or null if it's gone.
func position_of(key: String) -> Variant:
	if pallets.has(key):
		var p := pallets[key] as SupplyPallet
		return p.global_position if is_instance_valid(p) and not p.is_queued_for_deletion() else null
	if key.begins_with(VEHICLE_PREFIX):
		var v := vehicle_of(key)
		return v.global_position if v else null
	return null


func vehicle_of(key: String) -> Vehicle:
	var layer := get_parent().get_node_or_null(^"Vehicles") as VehicleLayer
	return layer.find(key.trim_prefix(VEHICLE_PREFIX)) if layer and key.begins_with(VEHICLE_PREFIX) else null


## Host: every tagged thing still there, as lots with their tag (report_from_level).
func lots() -> Array:
	var out: Array = []
	for key: String in tags:
		var t: Dictionary = tags[key]
		var lot := {}
		if pallets.has(key) and is_instance_valid(pallets[key]):
			lot = (pallets[key] as SupplyPallet).lot()
		elif key.begins_with(VEHICLE_PREFIX):
			var v := vehicle_of(key)
			if v:
				lot = Pallets.vehicle_lot(v.model, v.wrecked, key, v.display_name())
		if lot.is_empty():
			continue
		lot["tag"] = String(t.mode)
		lot["faction"] = String(t.get("faction", ""))
		out.append(lot)
	return out
