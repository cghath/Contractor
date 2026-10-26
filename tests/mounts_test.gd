extends Node
## Mounts (docs/survival_mounts.md; Contractor: Fallen calls 31, 35): a new survival world puts wild
## horses and a cart at the start farm; on a flat test deck over the zone a bicycle rides faster
## on asphalt than on grass and is silent; a horse is ridden at a walk, a trot and a gallop that
## spends its wind, its hooves are heard, a shot bolts it and throws a green rider; it needs feed
## and water (hungry it won't gallop, starved it dies) and carries packs; a wild horse is caught
## with a rope; a cart takes a horse in its shafts, holds a stash and a companion drives it; a
## companion mounts up and follows the player's horse in a column; "stay with the horses" holds a
## companion by a tied horse, calling out the dead; the dead bite a horse; mounts are saved with
## the zone and come back as they were left.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var people: SurvivorsLayer
var deck_y := 0.0
var origin := Vector3.ZERO
var _n := 0


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("MOUNTS TEST FAILED (timed out)")
		get_tree().quit(99))
	Vehicle.local_input = false  # the test rides by request
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_world()
	if level != null and player != null:
		_make_deck()
		await _frames(5)
		await _test_bicycle()
		await _test_horse_gaits()
		await _test_spook()
		_test_needs_and_packs()
		await _test_catch()
		await _test_cart()
		await _test_companion_follows()
		await _test_stay_with_horses()
		await _test_dead_bite()
		await _test_save_restore()
	_finish()


func _test_world() -> void:
	print("A new world: mounts at the start farm")
	check(Survival.server_new_world(main, "test_mounts" + tag, 4321), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	people = SurvivorsLayer.find(level)
	player.inventory.take(&"pack_daypack_20")  # (room for what the tests hand him)
	Survival.server_set_options({"dead": "low"})
	var mounts := Mounts.of(level)
	check(mounts != null, "the zone has its Mounts")
	await _wait_for(func() -> bool: return mounts != null and mounts.placed, 10.0)
	await _frames(3)
	var counts := Mount.counts_in_zone(level)
	check(int(counts.horse) >= Mounts.START_HORSES and int(counts.wild) >= Mounts.START_HORSES and int(counts.cart) >= 1,
		"wild horses and a cart wait at the start farm (%s)" % [counts])
	var start_horse := VehicleLayer.of(level).find("mnt_start_horse_0") as Mount
	check(start_horse != null and not start_horse.tamed and start_horse.global_position.distance_to(level.insertion_points()[0]) < 40.0,
		"one of them is a wild horse by the farm")


## A flat deck 30 m over the zone's ground, 300 m square: no buildings, trees or roaming dead in
## the way; ground patches laid over parts of it for the surfaces.
func _make_deck() -> void:
	var p := player.global_position
	var top := level.ground_height(p.x, p.z)
	for dx: float in [-120.0, 0.0, 120.0]:
		for dz: float in [-120.0, 0.0, 120.0]:
			top = maxf(top, level.ground_height(p.x + dx, p.z + dz))
	deck_y = top + 30.0
	origin = Vector3(p.x, deck_y, p.z)
	var body := StaticBody3D.new()
	body.name = "MountsTestDeck"
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 1.0, 300.0)
	col.shape = box
	body.add_child(col)
	level.add_child(body)
	body.global_position = origin - Vector3(0.0, 0.5, 0.0)
	# Asphalt to the east (x > 0), grass to the west, dirt north and south of the middle strip.
	VehicleDrive.add_patch(level, Rect2(origin.x - 150.0, origin.z - 150.0, 300.0, 300.0), &"dirt", Vector2(deck_y - 2.0, deck_y + 4.0))
	VehicleDrive.add_patch(level, Rect2(origin.x + 10.0, origin.z + 60.0, 130.0, 30.0), &"asphalt", Vector2(deck_y - 2.0, deck_y + 4.0))
	VehicleDrive.add_patch(level, Rect2(origin.x - 140.0, origin.z + 60.0, 130.0, 30.0), &"grass", Vector2(deck_y - 2.0, deck_y + 4.0))
	_put(player, Vector3(0.0, 0.0, 0.0))


func _at(off: Vector3) -> Vector3:
	return origin + Vector3(off.x, 0.05, off.z)


func _put(s: Soldier, off: Vector3) -> void:
	s.global_position = _at(off) + Vector3.UP * 0.05
	s.velocity = Vector3.ZERO


func _spawn(model: String, off: Vector3, yaw := 0.0, opts := {}) -> Mount:
	_n += 1
	var o := opts.duplicate()
	if not o.has("id"):
		o["id"] = "test_%s_%d" % [model, _n]
	return Mounts.server_spawn(level, model, _at(off), yaw, o)


## Rides `m` (the player at the reins) for `seconds` at `throttle`, `steer`. Returns the top speed.
func _ride(m: Mount, throttle: float, seconds: float, steer := 0.0) -> float:
	var top := 0.0
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		m.request_drive(throttle, steer, false)
		await get_tree().physics_frame
		top = maxf(top, m.forward_speed())
	return top


func _test_bicycle() -> void:
	print("A bicycle: fast on asphalt, slow on grass, silent")
	# yaw 90: facing -x would be west; ride along z on the patches instead (yaw 180: facing +z).
	var bike := _spawn(Mount.BICYCLE, Vector3(40.0, 0.0, 62.0), 180.0)
	check(bike != null and bike.mount_type == Mount.BICYCLE, "a bicycle stands on the road")
	if bike == null:
		return
	await _frames(3)
	check(bike.ground_here() == &"asphalt", "on asphalt (%s)" % bike.ground_here())
	check(bike.server_enter(player, 0) and Vehicle.ride_of(player) == bike, "the survivor gets on")
	var road := await _ride(bike, 1.0, 4.5)
	check(bike.last_noise_m == 0.0, "pedalling makes no noise the dead hear (%.0f m)" % bike.last_noise_m)
	bike.linear_velocity = Vector3.ZERO
	bike.global_position = _at(Vector3(-60.0, 0.0, 62.0))
	await _frames(3)
	check(bike.ground_here() == &"grass", "over on the grass (%s)" % bike.ground_here())
	var grass := await _ride(bike, 1.0, 4.5)
	check(road > 6.0 and grass < road * 0.6, "faster on the road than on grass (%.1f m/s vs %.1f m/s)" % [road, grass])
	check(not Mount.is_mount_model("matv") and Mount.is_mount_model("horse") and not VehicleSpecs.models().has("horse"),
		"mounts are vehicles of their own kind, kept off the campaign's lists")
	bike.server_exit(player)
	await _frames(2)


func _test_horse_gaits() -> void:
	print("A horse: walk, trot, gallop; wind and hooves")
	var horse := _spawn(Mount.HORSE, Vector3(0.0, 0.0, -20.0), 90.0)  # facing -x... yaw 90 faces -x: plenty of deck
	check(horse != null and horse.tamed, "a tame horse")
	if horse == null:
		return
	await _frames(3)
	check(horse.server_enter(player, 0) and Vehicle.ride_of(player) == horse, "mounted")
	horse.request_gait(Mount.Gait.WALK)
	var walk := await _ride(horse, 1.0, 2.0)
	check(horse.gait() == Mount.Gait.WALK and walk < 2.2 and walk > 1.2, "at a walk (%.1f m/s)" % walk)
	check(horse.last_noise_m >= 15.0 and horse.last_noise_m <= 25.0, "hooves heard about 20 m at a walk (%.0f m)" % horse.last_noise_m)
	horse.request_gait(Mount.Gait.TROT)
	var trot := await _ride(horse, 1.0, 2.5)
	check(horse.gait() == Mount.Gait.TROT and trot > 3.5 and trot < 5.0, "at a trot (%.1f m/s)" % trot)
	var wind := horse.stamina
	horse.request_gait(Mount.Gait.GALLOP)
	var gallop := await _ride(horse, 1.0, 4.0)
	check(gallop > 9.0 and horse.gait() == Mount.Gait.GALLOP, "at a gallop (%.1f m/s)" % gallop)
	check(horse.stamina < wind - 2.0, "the gallop spends its wind (%.0f -> %.0f)" % [wind, horse.stamina])
	check(horse.last_noise_m >= 50.0, "and the hooves carry (%.0f m)" % horse.last_noise_m)
	horse.stamina = 4.0
	await _ride(horse, 1.0, 2.5)
	check(horse.gait() != Mount.Gait.GALLOP and horse.allowed_gait() == Mount.Gait.TROT, "blown, it drops out of the gallop (%.1f m/s)" % horse.forward_speed())
	horse.stamina = 100.0
	await _ride(horse, 0.0, 3.5)
	check(absf(horse.forward_speed()) < 0.5, "reins slack, it stops (%.1f m/s)" % horse.forward_speed())
	var parts := horse.readout(0)
	check(parts.contains("Horse") and parts.contains("Wind"), "the rider's readout: %s" % parts)
	player.set_meta(&"test_horse", horse)


func _test_spook() -> void:
	print("A shot spooks a horse: it bolts and throws a green rider")
	var horse := player.get_meta(&"test_horse") as Mount
	if horse == null:
		return
	check(Vehicle.ride_of(player) == horse, "still in the saddle")
	check(Mount.fieldcraft_of(player) < Mount.THROW_FIELDCRAFT, "a new survivor's fieldcraft is low (%d)" % Mount.fieldcraft_of(player))
	var at := horse.global_position
	Survival.server_noise(level, at + Vector3(4.0, 0.0, 0.0), ZombieAI.SHOT_HEARD_M, ZombieAI.HEAR_SHOT)
	check(horse.spooked_s > 0.0, "the shot spooks it (%.1f s)" % horse.spooked_s)
	await _frames(2)
	check(Vehicle.ride_of(player) == null, "and throws its rider")
	await _seconds(1.5)
	check(horse.global_position.distance_to(at) > 4.0, "it bolts (%.1f m)" % horse.global_position.distance_to(at))
	await _wait_for(func() -> bool: return horse.spooked_s <= 0.0, 6.0)
	await _seconds(3.5)
	check(horse.spooked_s <= 0.0 and absf(horse.forward_speed()) < 1.0, "and settles")


func _test_needs_and_packs() -> void:
	print("Feed, water and packs")
	var horse := player.get_meta(&"test_horse") as Mount
	if horse == null:
		return
	horse.feed = 100.0
	horse.water = 100.0
	horse.step_needs(0.8, false)
	check(absf(horse.feed - 20.0) < 0.5 and absf(horse.water - 20.0) < 0.5, "most of a day uses most of its feed and water (%.0f, %.0f)" % [horse.feed, horse.water])
	check(horse.allowed_gait() == Mount.Gait.TROT, "hungry and thirsty, it won't gallop")
	horse.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
	horse.cargo_hold.take(Mount.FEED_ITEM, 2)  # (in its packs)
	horse.cargo_hold.take(&"water_bottle", 4)
	var fed := horse.server_action(player, "feed")
	check(horse.feed > 99.0, "oats from its packs fill it (%s: %.0f)" % [fed, horse.feed])
	var watered := horse.server_action(player, "water")
	check(horse.water > 30.0, "bottles from its packs water it (%s: %.0f)" % [watered, horse.water])
	var acts := InteractionMenu.actions_for(player, horse).map(func(a: Dictionary) -> String: return String(a.id))
	check(InteractionMenu.target_kind(player, horse) == InteractionMenu.MOUNT and acts.has("ride") and acts.has("feed") and acts.has("tie"),
		"the menu treats it as a mount: %s" % [acts])
	check(horse.cargo_hold != null and horse.cargo_hold.capacity_l >= 100.0 and horse.cargo_hold.take(&"canned_meat", 4) == 4,
		"it carries packs (%.0f L)" % horse.cargo_hold.capacity_l)
	var starver := _spawn(Mount.HORSE, Vector3(-30.0, 0.0, -40.0))
	if starver:
		starver.feed = 0.0
		starver.step_needs(Mount.STARVE_DAYS + 0.1, false)
		check(starver.wrecked and String(starver.get_meta(&"died_of", "")) == "starved", "without feed for days it dies (%s)" % starver.get_meta(&"died_of", "alive"))


func _test_catch() -> void:
	print("Catching a wild horse with a rope")
	var wild := _spawn(Mount.HORSE, Vector3(20.0, 0.0, -40.0), 0.0, {"wild": true})
	if wild == null:
		return
	await _frames(2)
	_put(player, Vector3(21.5, 0.0, -40.0))
	await _frames(2)
	check(not wild.server_enter(player, 0), "a wild horse can't be ridden")
	while player.inventory.count_of(Mount.ROPE) > 0:
		player.inventory.remove_one(Mount.ROPE)
	var no := wild.server_action(player, "catch")
	check(not wild.tamed and no.contains("rope"), "not without a rope (\"%s\")" % no)
	player.inventory.take(Mount.ROPE, 1)
	for i in 40:  # (a test survivor learns enough fieldcraft to try)
		if Rpg.gate(player, "fieldcraft", Mount.CATCH_FIELDCRAFT):
			break
		Rpg.xp(player, "fieldcraft", 50.0)
	var start := wild.server_action(player, "catch")
	await _seconds(Mount.CATCH_S + 0.6)
	check(wild.tamed and player.inventory.count_of(Mount.ROPE) == 0, "close by for a few seconds, it's caught (\"%s\", fieldcraft %d)" % [start, Rpg.level(player, "fieldcraft")])


func _test_cart() -> void:
	print("A cart: hitched, a stash, a companion at the reins")
	var cart := _spawn(Mount.CART, Vector3(-40.0, 0.0, 0.0), 0.0)
	var horse := _spawn(Mount.HORSE, Vector3(-40.0, 0.0, -3.0), 0.0)
	if cart == null or horse == null:
		return
	await _frames(3)
	check(not cart.can_drive(), "no horse, no going")
	var why := cart.server_hitch()
	check(why == "" and cart.horse() == horse and horse.hitched() == cart and cart.can_drive(), "a horse goes in the shafts (%s)" % why)
	check(cart.cargo_hold.capacity_l >= 1000.0 and cart.cargo_hold.take(&"water_bottle", 12) == 12, "a big stash on it (%.0f L)" % cart.cargo_hold.capacity_l)
	var c := _companion(Vector3(-38.0, 0.0, 2.0))
	check(c != null, "a companion")
	if c == null:
		return
	check(cart.server_enter(c, 0) and cart.driver() == c, "the companion takes the reins")
	var from := cart.global_position
	cart.server_drive_to(_at(Vector3(-40.0, 0.0, -45.0)))
	await _seconds(9.0)
	var moved := cart.global_position.distance_to(from)
	var off := VehicleSpecs.vec(cart.mspec.get("hitch"), Vector3(0, 0, -2.6))
	var in_shafts := horse.global_position.distance_to(cart.global_transform * off) < 0.5
	check(moved > 8.0 and in_shafts, "and drives it, the horse in the shafts (%.1f m)" % moved)
	cart.server_stop()
	cart.server_exit(c)
	await _frames(2)
	player.set_meta(&"test_companion", c)
	player.set_meta(&"test_cart", cart)


func _companion(off: Vector3) -> Soldier:
	if people == null:
		return null
	var rec := people.server_add_person(_at(off), {"traits": ["calm"], "want": {"kind": "place"}})
	var c := people.server_recruit(rec, player)
	if c:
		_put(c, off)
	return c


func _test_companion_follows() -> void:
	print("A companion mounts up and follows the player's horse")
	var lead := player.get_meta(&"test_horse") as Mount
	var c := player.get_meta(&"test_companion") as Soldier
	if lead == null or c == null:
		return
	lead.linear_velocity = Vector3.ZERO
	lead.global_position = _at(Vector3(0.0, 0.0, -60.0))
	lead.global_basis = Basis(Vector3.UP, deg_to_rad(90.0))
	var second := _spawn(Mount.HORSE, Vector3(6.0, 0.0, -60.0), 90.0)
	_put(player, Vector3(1.0, 0.0, -58.5))
	_put(c, Vector3(6.0, 0.0, -58.0))
	await _frames(3)
	check(lead.server_enter(player, 0), "the player mounts")
	var mounts := Mounts.of(level)
	var said := mounts.server_mount_up(player)
	await _wait_for(func() -> bool: return Vehicle.ride_of(c) != null, 8.0)
	check(Vehicle.ride_of(c) == second, "\"Everyone mount up\": the companion takes the other horse (%s)" % said)
	if Vehicle.ride_of(c) != second:
		second.server_enter(c, 0)
	await _seconds(TestTimes.CONVOY_SETTLE)
	var drivers := SquadDrivers.of(level)
	check(drivers != null and drivers.driven(player).has(second), "his horse is one the squad rides")
	var from := second.global_position
	lead.request_gait(Mount.Gait.TROT)
	await _ride(lead, 1.0, 12.0)
	await _seconds(3.0)
	var went := second.global_position.distance_to(from)
	check(went > 10.0, "he rides after the player (%.1f m)" % went)
	lead.server_exit(player)
	second.server_exit(c)
	await _frames(3)


func _test_stay_with_horses() -> void:
	print("Stay with the horses")
	var horse := player.get_meta(&"test_horse") as Mount
	var c := player.get_meta(&"test_companion") as Soldier
	if horse == null or c == null:
		return
	horse.linear_velocity = Vector3.ZERO
	await _frames(2)
	_put(player, Vector3(horse.global_position.x - origin.x + 1.5, 0.0, horse.global_position.z - origin.z))
	_put(c, Vector3(horse.global_position.x - origin.x + 5.0, 0.0, horse.global_position.z - origin.z + 3.0))
	await _frames(2)
	check(horse.server_action(player, "tie") == "Tied" and horse.tied and not horse.can_drive(), "tied, it stays")
	var why := Mounts.of(level).server_stay(player, horse)
	var brain := SquadAI.of(c)
	check(why == "" and horse.minder == c and Mounts.minding(c) and brain and brain.order == Squad.Order.HOLD, "a companion holds by the tied horse (%s)" % why)
	var heard := people.said.size()
	var z := Survival.server_spawn_zombie(level, horse.global_position + Vector3(18.0, 0.2, 0.0))
	await _seconds(2.5)
	var called := people.said.slice(heard).any(func(l: Dictionary) -> bool: return String(l.text) in Mounts.LINES_CALL)
	check(called, "and calls out the dead coming (%s)" % [people.said.slice(heard).map(func(l: Dictionary) -> String: return String(l.text))])
	if z:
		z.queue_free()
	horse._spooked_at = -100.0
	var bolted := 0
	for i in 10:
		horse._spooked_at = -100.0
		horse.spooked_s = 0.0
		if horse.server_spook(horse.global_position + Vector3(3, 0, 0), "shot", level):
			bolted += 1
	check(bolted == 0 and horse.global_position.distance_to(horse.home) < 1.0, "tied, a shot can't make it bolt")
	brain.on_order(Squad.Order.FOLLOW, player.global_position)
	await _seconds(1.5)
	check(horse.minder == null and not Mounts.minding(c), "told to follow, he leaves his post")


func _test_dead_bite() -> void:
	print("The dead attack a horse")
	var horse := _spawn(Mount.HORSE, Vector3(60.0, 0.0, -80.0))
	if horse == null:
		return
	await _frames(2)
	horse.tied = true  # (so it can't bolt off the deck)
	var z := Survival.server_spawn_zombie(level, horse.global_position + Vector3(1.0, 0.3, 0.0))
	for i in 40:  # (held at its side: the deck has no navmesh to walk)
		if z:
			z.global_position = horse.global_position + Vector3(1.0, 0.05, 0.0)
		await get_tree().physics_frame
	await _seconds(3.0)
	check(horse.health < float(horse.mspec.get("hp", 100.0)), "a walker at its side bites it (%.0f HP)" % horse.health)
	horse.server_hurt(500.0, "bitten")
	check(horse.is_dead() and not horse.can_drive() and not horse.server_enter(player, 0), "and it can die of it")
	if z:
		z.queue_free()
	await _frames(2)


func _test_save_restore() -> void:
	print("Saved with the zone")
	var horse := player.get_meta(&"test_horse") as Mount
	var cart := player.get_meta(&"test_cart") as Mount
	if horse == null or cart == null:
		return
	horse.feed = 61.0
	var hid := horse.vehicle_id
	var cid := cart.vehicle_id
	var horse_of_cart := cart.horse().vehicle_id if cart.horse() else ""
	var stash := cart.cargo_hold.count_of(&"water_bottle")
	var name := Survival.world
	Survival.server_save()
	Net.leave()
	await get_tree().process_frame
	check(Survival.server_continue(main, name), "Continue hosts the world again")
	level = SurvivalLevel.of(self)
	await _wait_for(func() -> bool: return level != null and level.players.get_node_or_null(^"1") != null, 20.0)
	await _frames(10)
	var layer := VehicleLayer.of(level)
	var h2: Mount = layer.find(hid) as Mount if layer else null
	var c2: Mount = layer.find(cid) as Mount if layer else null
	check(h2 != null and h2.tied and absf(h2.feed - 61.0) < 1.5 and h2.tamed, "the tied horse is back, tied, as fed as it was (%s)" % ["missing" if h2 == null else "feed %.0f" % h2.feed])
	check(c2 != null and c2.cargo_hold.count_of(&"water_bottle") == stash, "the cart is back with its stash (%d)" % (c2.cargo_hold.count_of(&"water_bottle") if c2 else -1))
	await _seconds(1.5)
	check(c2 != null and c2.horse() != null and c2.horse().vehicle_id == horse_of_cart, "with its horse in the shafts")
	var start: Mount = layer.find("mnt_start_horse_0") as Mount if layer else null
	check(start != null and Mount.counts_in_zone(level).horse >= 3, "and the farm's horses once, not twice (%s)" % [Mount.counts_in_zone(level)])


class TestTimes:
	const CONVOY_SETTLE := 2.5


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("MOUNTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
