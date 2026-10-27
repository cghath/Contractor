extends Node3D
## Headless checks for what treatment and the casualty's state show on the body: BodyDevices
## (tourniquets with their time tag, splints, the pelvic binder, the sling, IV and IO lines,
## the hung bag emptying, the NPA, the blanket, bone at an open fracture), WoundMarks' dressings
## (pressure bandage, packed gauze, chest seal), BodyCondition (burns, pallor, blue lips, blood
## at the mouth, shivering), blood on a treater's hands and the smear a dragged casualty leaves.
## Each device: it appears when applied, sits on the right part, and goes when it comes off.
## (The same on a client: net_test, "devices drawn on a client".)
##   <voxel godot exe> --headless --path . res://tests/devices_test.tscn
## Exits with the number of failures.

const SPOT := Vector3(0, 0.1, 20)

var failures := 0
var level: CompoundLevel
var player: Soldier
var casualty: Soldier


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("DEVICES TEST FAILED (timed out)")
		get_tree().quit(99))
	await _start_session()
	_test_tourniquet()
	_test_dressings()
	_test_splints()
	await _test_lines()
	_test_npa_and_blanket()
	_test_open_fracture()
	_test_burns()
	await _test_pallor_and_signs()
	await _test_hands()
	await _test_smear()
	GameState.delete_save()
	print("DEVICES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _start_session() -> void:
	GameState.zone_id = "test_devices" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	player.global_position = SPOT
	player.rotation = Vector3.ZERO
	casualty = level.spawn_soldier({"name": "Casualty", "faction": "friendly", "variant": "multicam", "pos": SPOT + Vector3(0, 0, -1.2),
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(casualty).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(10)


# --- Devices ------------------------------------------------------------------------------

func _test_tourniquet() -> void:
	print("Tourniquet")
	_reset(casualty)
	var d := _devices(casualty)
	var at := Vector3(-0.075, 0.6, -0.085)  # the front of the left thigh
	_wound(casualty, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l", at)
	check(d.shown(&"tourniquet").is_empty(), "no tourniquet before one goes on")
	check(casualty.vitals.server_apply_treatment(&"tourniquet", Vitals.THIGH_L, true), "a tourniquet goes on the left thigh (rushed)")
	var tq := d.shown(&"tourniquet")
	_on_part(casualty, &"tourniquet", Vitals.THIGH_L)
	var expected := minf(at.y + CharacterModel.TOURNIQUET_HIGH, BodyMap.PART_BOXES[Vitals.THIGH_L][0][0].y + 0.195 - BodyDevices.TOP_MARGIN)
	check(tq.size() == 1 and absf(Vector3(tq[0].at).y - expected) < 0.015,
		"high and tight: 12 cm above the wound (at %.3f m, the wound at %.3f m)" % [Vector3(tq[0].at).y if tq.size() == 1 else -1.0, at.y])
	var times := d.tourniquet_times(Vitals.THIGH_L)
	check(times.size() == 1 and String(times[0]).length() == 4 and String(times[0]).is_valid_int(), "its tag has the time written on it (%s)" % [times])
	var one := d.voxels_on(Vitals.THIGH_L)
	casualty.vitals.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)  # beside the rushed one
	check(d.tourniquet_times(Vitals.THIGH_L).size() == 2 and d.voxels_on(Vitals.THIGH_L) > one * 1.6, "a second one beside it (%d voxels, one was %d)" % [d.voxels_on(Vitals.THIGH_L), one])
	check(casualty.vitals.server_apply_treatment(&"hemostatic_gauze", Vitals.THIGH_L), "the wound packed")
	check(casualty.vitals.server_remove_tourniquets(Vitals.THIGH_L) == 2, "both come off")
	check(d.shown(&"tourniquet").is_empty() and d.voxels_on(Vitals.THIGH_L) == 0 and d.tourniquet_times(Vitals.THIGH_L).is_empty(), "and they're gone from the leg")
	check(_marks(casualty).dressing_on(Vitals.THIGH_L) == &"gauze", "the packed wound shows gauze (%s)" % _marks(casualty).dressing_on(Vitals.THIGH_L))
	# On an arm, a wound low on the forearm: the tourniquet on the upper arm sits high on it.
	_reset(casualty)
	_wound(casualty, Vitals.FOREARM_R, "arterial", 0.6, &"radial_r", Vector3(0.25, 0.86, -0.04))
	casualty.vitals.server_apply_treatment(&"tourniquet", Vitals.UPPER_ARM_R)
	var arm := d.shown(&"tourniquet")
	var top: float = BodyMap.PART_BOXES[Vitals.UPPER_ARM_R][0][0].y + 0.16
	check(arm.size() == 1 and arm[0].part == Vitals.UPPER_ARM_R and absf(Vector3(arm[0].at).y - (top - BodyDevices.TOP_MARGIN)) < 0.015,
		"for a forearm wound, high on the upper arm (%s)" % [arm])
	_reset(casualty)
	check(d.shown(&"tourniquet").is_empty(), "a reset takes it off")


func _test_dressings() -> void:
	print("Dressings")
	_reset(casualty)
	var marks := _marks(casualty)
	_wound(casualty, Vitals.FOREARM_R, "muscle", 0.25, &"", Vector3(0.25, 0.95, -0.05))
	var bare := _wound_voxels(casualty, Vitals.FOREARM_R)
	check(marks.dressing_on(Vitals.FOREARM_R) == &"", "an untreated wound has no dressing")
	casualty.vitals.server_apply_treatment(&"pressure_bandage", Vitals.FOREARM_R)
	check(marks.dressing_on(Vitals.FOREARM_R) == &"bandage" and _wound_voxels(casualty, Vitals.FOREARM_R) > bare + 40,
		"a pressure bandage wraps the forearm, its bar over the hole (%d voxels, %d bare)" % [_wound_voxels(casualty, Vitals.FOREARM_R), bare])
	_wound(casualty, Vitals.CHEST, "chest", 0.15, &"lung_r", Vector3(0.08, 1.3, -0.11))
	casualty.vitals.server_apply_treatment(&"chest_seal", Vitals.CHEST)
	check(marks.dressing_on(Vitals.CHEST) == &"seal", "a chest seal on the chest wound, not a bandage (%s)" % marks.dressing_on(Vitals.CHEST))
	_wound(casualty, Vitals.NECK, "junctional", 0.5, &"carotid", Vector3(0.04, 1.48, -0.06))
	casualty.vitals.server_apply_treatment(&"hemostatic_gauze", Vitals.NECK)
	check(marks.dressing_on(Vitals.NECK) == &"gauze", "packed gauze at the neck (%s)" % marks.dressing_on(Vitals.NECK))
	_reset(casualty)
	check(marks.dressing_on(Vitals.FOREARM_R) == &"" and marks.dressing_on(Vitals.CHEST) == &"", "healed: the dressings go")


func _test_splints() -> void:
	print("Splints, binder, sling")
	_reset(casualty)
	var d := _devices(casualty)
	_wound(casualty, Vitals.THIGH_R, "fracture", 0.05, &"femur_r")
	_wound(casualty, Vitals.PELVIS, "fracture", 0.15, &"pelvis")
	_wound(casualty, Vitals.CHEST, "fracture", 0.0, &"clavicle_l")
	check(d.shown(&"splint").is_empty() and d.shown(&"pelvic_binder").is_empty(), "nothing on an untreated break")
	check(casualty.vitals.server_apply_treatment(&"splint", Vitals.THIGH_R), "a splint on the right thigh")
	_on_part(casualty, &"splint", Vitals.THIGH_R)
	check(casualty.vitals.server_apply_treatment(&"pelvic_binder", Vitals.PELVIS), "a pelvic binder")
	_on_part(casualty, &"pelvic_binder", Vitals.PELVIS)
	var binder := d.shown(&"pelvic_binder")
	check(binder.size() == 1 and absf(Vector3(binder[0].at).y - 0.915) < 0.03, "round the hips (%s)" % [binder])
	check(casualty.vitals.server_apply_treatment(&"splint", Vitals.CHEST), "the collarbone: a sling")
	_on_part(casualty, &"sling", Vitals.CHEST)
	_reset(casualty)
	check(d.shown(&"splint").is_empty() and d.shown(&"pelvic_binder").is_empty() and d.shown(&"sling").is_empty(), "healed: all gone")


func _test_lines() -> void:
	print("IV, IO and the bag")
	_reset(casualty)
	var d := _devices(casualty)
	casualty.vitals._model.blood = 0.8
	casualty.vitals._after_change(true)
	casualty.vitals.care_rng.seed = 3
	check(casualty.vitals.server_apply_treatment(&"iv_18", Vitals.FOREARM_L) and casualty.vitals.access().get("part") == Vitals.FOREARM_L,
		"an IV in the left forearm (%s)" % [casualty.vitals.access()])
	_on_part(casualty, &"iv", Vitals.FOREARM_L)
	check(d.shown(&"bag").is_empty() and d.bag_fill() < 0.0, "no bag yet")
	check(casualty.vitals.server_apply_treatment(&"saline_500", Vitals.FOREARM_L), "a 500 mL bag on the line")
	_on_part(casualty, &"bag", Vitals.CHEST)
	check(d.bag_fill() > 0.95, "hung on the chest, full (%.2f)" % d.bag_fill())
	await _frames(2)
	var line: MultiMeshInstance3D = d.get_node_or_null(^"IVLine")
	check(line != null and line.multimesh.visible_instance_count == BodyDevices.LINE_SEGMENTS, "its line runs to the forearm")
	var full := d.voxels_on(Vitals.CHEST)
	casualty.vitals._model.infusion.left = 200.0
	casualty.vitals._after_change(true)
	check(absf(d.bag_fill() - 0.4) < 0.06, "it empties as it goes in (%.2f with 200 of 500 mL left)" % d.bag_fill())
	check(casualty.vitals.server_apply_treatment(&"pressure_bag", Vitals.FOREARM_L) and d.voxels_on(Vitals.CHEST) > full, "a pressure bag's cuff round it")
	casualty.vitals._model.infusion = {}
	casualty.vitals._after_change(true)
	check(d.shown(&"bag").is_empty() and not d.shown(&"iv").is_empty() and not d.is_processing(), "the bag run through: gone, the line stays in")
	_reset(casualty)
	check(d.shown(&"iv").is_empty(), "the line out on a reset")
	casualty.vitals._model.blood = 0.8
	check(casualty.vitals.server_apply_treatment(&"io_kit", Vitals.CHEST), "an IO in the sternum")
	_on_part(casualty, &"io", Vitals.CHEST)
	_reset(casualty)


func _test_npa_and_blanket() -> void:
	print("NPA and blanket")
	_reset(casualty)
	var d := _devices(casualty)
	var m: WoundModel = casualty.vitals._model
	m.knockout_left = 60.0
	m.update_state(0.0)
	casualty.vitals._after_change(true)
	check(casualty.vitals.server_apply_treatment(&"npa", Vitals.HEAD), "an NPA in an unconscious casualty")
	_on_part(casualty, &"npa", Vitals.FACE)
	var npa := d.shown(&"npa")
	var pivot := BodyVolume.pivot_at(Vitals.HEAD)
	check(npa.size() == 1 and Vector3(npa[0].at).z < pivot.z - 0.09 and absf(Vector3(npa[0].at).y - pivot.y - 0.13) < 0.03,
		"its flange at the nostril (%s)" % [npa])
	check(casualty.vitals.server_apply_treatment(&"hypothermia_blanket", Vitals.TORSO), "a blanket round them")
	var wrapped := d.shown(&"blanket").map(func(e: Dictionary) -> StringName: return e.part)
	check(Vitals.CHEST in wrapped and Vitals.THIGH_L in wrapped and Vitals.UPPER_ARM_R in wrapped and Vitals.FACE not in wrapped,
		"wrapped round the trunk, arms and legs, not the face (%s)" % [wrapped])
	_reset(casualty)
	check(d.shown(&"npa").is_empty() and d.shown(&"blanket").is_empty(), "both gone on a reset")


func _test_open_fracture() -> void:
	print("Open fracture")
	_reset(casualty)
	var d := _devices(casualty)
	var m: WoundModel = casualty.vitals._model
	var w := _wound(casualty, Vitals.SHIN_L, "fracture", 0.0, &"tibia_l", Vector3(-0.075, 0.25, -0.06))
	check(d.shown(&"bone").is_empty(), "a closed break shows no bone")
	m._open_break(w, "test")
	m.wounds[-1]["at"] = Vector3(-0.075, 0.25, -0.06)
	casualty.vitals._after_change(true)
	_on_part(casualty, &"bone", Vitals.SHIN_L)
	check(casualty.vitals.server_apply_treatment(&"pressure_bandage", Vitals.SHIN_L) and d.shown(&"bone").is_empty(), "dressed: the bone covered")
	_reset(casualty)


# --- Condition ------------------------------------------------------------------------------

func _test_burns() -> void:
	print("Burns")
	_reset(casualty)
	var c := _condition(casualty)
	check(c.overlaid().is_empty(), "unhurt: no overlay on the body")
	casualty.vitals.server_burn(0.3)
	var meshes := c.overlaid()
	var mat: ShaderMaterial = meshes[0].material_overlay if not meshes.is_empty() else null
	check(meshes.size() >= 10 and mat != null and is_equal_approx(float(mat.get_shader_parameter(&"burn")), 0.3),
		"30%% burns: the scorch overlay on every body part (%d meshes)" % meshes.size())
	check(BodyCondition.SHADER.contains("charred") and float(mat.get_shader_parameter(&"pallor")) == 0.0 if mat else false, "burns darken the voxels they reach, the skin otherwise as it was")
	casualty.vitals._model.burn_dressings = 2
	casualty.vitals._after_change(true)
	check(mat != null and float(mat.get_shader_parameter(&"dressed")) > 0.0, "dressings cover some of it (%.2f)" % (float(mat.get_shader_parameter(&"dressed")) if mat else -1.0))
	_reset(casualty)
	check(c.overlaid().is_empty() and c.burn() == 0.0, "healed: the overlay comes off")


func _test_pallor_and_signs() -> void:
	print("Pallor, lips, blood at the mouth, shivering")
	_reset(casualty)
	var c := _condition(casualty)
	var m: WoundModel = casualty.vitals._model
	var last := -1.0
	var rising := true
	for blood: float in [0.95, 0.8, 0.7, 0.6, 0.5]:
		m.blood = blood
		casualty.vitals._after_change(true)
		rising = rising and c.pallor() >= last
		last = c.pallor()
	check(rising and last > 0.9, "pallor follows the blood lost (%.2f at 50%%)" % last)
	# Captain, 2026-10-21: "hair blues/gets pallor when it shouldnt": the head's overlay knows the
	# face's own skin and hair (FaceRig's palette), and hair and eyes are never pale or blue.
	var head_mi: MeshInstance3D = c.body_meshes()[0]
	var hmat := head_mi.material_overlay as ShaderMaterial
	var scheme := c.scheme_of(head_mi)
	var spec := VoxelArt.spec(scheme)
	var same := func(param: StringName, hex: String) -> bool: return hmat != null and (hmat.get_shader_parameter(param) as Vector3).distance_to(Vector3(Color(hex).r, Color(hex).g, Color(hex).b)) < 0.002
	check(same.call(&"skin", String(spec.skin)) and same.call(&"hair", String(spec.hair)) and BodyCondition.SHADER.contains("bool kept"),
		"the head's overlay is its own face's: skin %s, hair %s (%s), hair and eyes kept" % [spec.skin, spec.hair, scheme])
	m.blood = 0.95
	casualty.vitals._after_change(true)
	check(c.pallor() == 0.0 and c.overlaid().is_empty(), "barely any lost: normal skin")
	m.spo2 = 80.0
	casualty.vitals._after_change(true)
	check(c.lips_blue() and "Blue lips" in casualty.vitals.signs(), "SpO2 80%: blue lips, as the sign says")
	m.blast_lung = true
	casualty.vitals._after_change(true)
	var mouth: MultiMeshInstance3D = casualty.model.part_node(Vitals.HEAD).get_node_or_null(^"MouthBlood")
	check(c.mouth_blood() and mouth != null and mouth.multimesh.visible_instance_count > 6, "coughing blood: blood at the mouth")
	_reset(casualty)
	check(not c.lips_blue() and not c.mouth_blood() and (mouth == null or mouth.multimesh.visible_instance_count == 0), "well again: gone")
	m.blood = 0.6
	m.still_s = WoundModel.HYPOTHERMIA_STILL_S + 10.0
	casualty.vitals._after_change(true)
	var meshes := c.body_meshes()
	var rest: Array = meshes.map(func(x: MeshInstance3D) -> Vector3: return x.position)
	await _frames(4)
	var moved := false
	for i in meshes.size():
		moved = moved or meshes[i].position.distance_to(rest[i]) > 0.0002
	check(c.shivering() and moved and "Shivering, skin cold" in casualty.vitals.signs(), "hypothermic: they shiver")
	casualty.vitals.server_apply_treatment(&"hypothermia_blanket", Vitals.TORSO)
	await _frames(2)
	var still := true
	for i in meshes.size():
		still = still and meshes[i].position.is_equal_approx(rest[i])
	check(not c.shivering() and still, "under a blanket: still again")
	_reset(casualty)


# --- Blood on the hands, the drag smear ------------------------------------------------------

func _test_hands() -> void:
	print("Bloody hands")
	_reset(casualty)
	_reset(player)
	var marks := _marks(player)
	check(marks.hand_blood(true) == 0 and marks.hand_blood(false) == 0, "clean hands to start")
	_wound(casualty, Vitals.FOREARM_R, "muscle", 0.25, &"", Vector3(0.25, 0.95, -0.05))
	player.inventory.take(&"pressure_bandage")
	player._server_treat.rpc_id(1, casualty.get_path(), &"pressure_bandage", Vitals.FOREARM_R)
	await _seconds(3.0)
	check(marks.hand_blood(true) > 2 and marks.hand_blood(false) > 2, "bandaging a bleeding arm: blood on both hands (%d, %d)" % [marks.hand_blood(true), marks.hand_blood(false)])
	check(marks.hand_blood(true) <= WoundMarks.HAND_CELLS, "within its cap")
	await _seconds(3.0)
	_reset(casualty)


func _test_smear() -> void:
	print("Drag smear")
	_reset(casualty)
	_reset(player)
	var marks := _marks(casualty)
	var m: WoundModel = casualty.vitals._model
	_wound(casualty, Vitals.THIGH_L, "arterial", 1.2, &"femoral_l", Vector3(-0.075, 0.6, -0.085))
	m.blood = 0.9
	m.knockout_left = 120.0
	m.update_state(0.0)
	casualty.vitals._after_change(true)
	await _frames(5)
	player.global_position = casualty.global_position + Vector3(0, 0, -0.9)
	check(player.server_pick_up_body(casualty, Soldier.DRAG, INF), "the player drags the bleeding casualty")
	await _seconds(1.5)  # the grab and the casualty's turn onto its back
	var before := marks.smear_size()
	check(before == 0, "no smear while the dragger stands (%d cells)" % before)
	for i in 60:  # 3 m at 5 cm a frame
		player.global_position += Vector3(0.05, 0, 0)
		await get_tree().process_frame
	var smeared := marks.smear_size() - before
	check(smeared >= 25, "3 m dragged: a smear along the way (%d cells)" % smeared)
	var off := 0
	for c: Dictionary in marks._smear:
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.pos) + Vector3.UP * 0.2, Vector3(c.pos) + Vector3.DOWN * 0.2, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or absf(float(hit.position.y) - Vector3(c.pos).y) > 0.003:
			off += 1
	check(off == 0, "every streak lies on the ground under it (%d off it)" % off)
	for i in 200:  # 10 m more
		player.global_position += Vector3(0.05, 0, 0)
		await get_tree().process_frame
	check(marks.smear_size() == WoundMarks.MAX_SMEAR, "and never more than its cap (%d of %d)" % [marks.smear_size(), WoundMarks.MAX_SMEAR])
	player.release_carried()
	casualty.vitals.server_apply_treatment(&"tourniquet", Vitals.THIGH_L)
	_reset(casualty)


# --- Helpers ----------------------------------------------------------------------------------

func _marks(s: Soldier) -> WoundMarks:
	return s.model.get_node(^"WoundMarks")


func _devices(s: Soldier) -> BodyDevices:
	return _marks(s).devices


func _condition(s: Soldier) -> BodyCondition:
	return _marks(s).condition


## A device of `kind` shows on `part`: listed there, centred inside the part's box (with room for
## what lies off the skin), and drawn on that part's bone.
func _on_part(s: Soldier, kind: StringName, part: StringName) -> void:
	var found := _devices(s).shown(kind).filter(func(e: Dictionary) -> bool: return e.part == part)
	var box: Array = BodyMap.PART_BOXES[part][0]
	var inside := false
	if part in [Vitals.CHEST, Vitals.ABDOMEN, Vitals.PELVIS]:
		box = BodyMap.SEGMENTS[&"torso"]
	if part == Vitals.FACE:
		box = BodyMap.SEGMENTS[&"head"]
	if not found.is_empty():
		inside = AABB(Vector3(box[0]) - Vector3(box[1]) * 0.5, Vector3(box[1])).grow(0.08).has_point(found[0].at)
	var drawn: MultiMeshInstance3D = s.model.part_node(part).get_node_or_null(^"Devices")
	check(found.size() >= 1 and inside and drawn != null and drawn.multimesh.visible_instance_count > 0,
		"%s on the %s (at %s, %d voxels on its bone)" % [kind, part, found[0].at if not found.is_empty() else "none", drawn.multimesh.visible_instance_count if drawn else 0])


## The voxels drawn on `part`'s bone for its wounds: the coarse holes and blood, and the dressings.
func _wound_voxels(s: Soldier, part: StringName) -> int:
	var n := 0
	for node_name: String in ["WoundMark", "WoundDressing"]:
		var drawn := s.model.part_node(part).get_node_or_null(node_name) as MultiMeshInstance3D
		n += drawn.multimesh.visible_instance_count if drawn else 0
	return n


## A wound added straight into the body's model at rest-pose point `at` (published at once).
func _wound(s: Soldier, part: StringName, kind: String, rate: float, name: StringName, at: Variant = null) -> Dictionary:
	var m: WoundModel = s.vitals._model
	var w := m._add_wound(part, kind, rate, name)
	if at is Vector3:
		w["at"] = at
	m.update_state(0.0)
	s.vitals._after_change(true)
	return w


func _reset(s: Soldier) -> void:
	s.vitals.server_reset_health()
	s._server_busy_until = 0.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
