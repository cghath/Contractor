extends Node
## Pictures of a city (queue item 1.5) and the generated village (queue item 1.6; docs/
## building_gen.md "City zones", "Village houses"), headless: no window opens. Drawn the way
## tests/landmark_shots.gd draws (its own flat-shaded drawing of the boxes through a depth buffer,
## from the front-right and above: the shapes, colours and layout, not the game's look).
##   <voxel godot exe> --headless --path . res://tests/city_shots.tscn -- [output folder] [city seed]
## Default folder: %TEMP%\contractor_world_shots (never the repo), seed the Old Quarter's. PNGs:
## city_whole.png (every block), city_tower_block.png, city_core_block.png, city_outskirts_block.png,
## village.png. Keep the run as an S run (docs/debugging.md) when it's for a record.

const OLD_QUARTER_SEED := 204917


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if args.size() > 0 and String(args[0]) != "" else OS.get_environment("TEMP").path_join("contractor_world_shots")
	var seed_value := int(args[1]) if args.size() > 1 else OLD_QUARTER_SEED
	DirAccess.make_dir_recursive_absolute(out)
	var drawer: Node = load("res://tests/landmark_shots.gd").new()  # (its drawing only: never in the tree)
	var layout := BuildingGen.city_layout(seed_value)
	var whole := {"boxes": [], "skin": [], "streets": [], "pad_sea": NAN}
	var picked := {}
	for at: Vector2i in layout.blocks:
		var info: Dictionary = layout.blocks[at]
		var started := Time.get_ticks_msec()
		var blk := BuildingGen.city_block(seed_value, at.x, at.y)
		var c: Vector2 = info.centre
		var off := Vector3(c.x, 0, c.y)
		for bx: Array in blk.boxes:
			(whole.boxes as Array).append([(bx[0] as Vector3) + off, (bx[1] as Vector3) + off, bx[2]])
		for bx: Array in blk.skin:
			(whole.skin as Array).append([(bx[0] as Vector3) + off, (bx[1] as Vector3) + off, bx[2]])
		for r: Rect2 in blk.streets:
			(whole.streets as Array).append(Rect2(r.position + c, r.size))
		var kind := "tower" if info.tower else ("core" if info.core else "outskirts")
		if not picked.has(kind):
			picked[kind] = true
			var path := out.path_join("city_%s_block.png" % kind)
			drawer._draw({"boxes": blk.boxes, "skin": blk.skin, "streets": blk.streets, "pad_sea": NAN}, path)
			print("[shots] %s: block %s, %d buildings (%s), %d boxes, %d skin, %d ms" % [path, at, (blk.buildings as Array).size(),
				", ".join((blk.buildings as Array).map(func(bt: Dictionary) -> String: return "%s %d" % [bt.type, bt.data.storeys])),
				(blk.boxes as Array).size(), (blk.skin as Array).size(), Time.get_ticks_msec() - started])
	var path := out.path_join("city_whole.png")
	var t0 := Time.get_ticks_msec()
	drawer._draw(whole, path)
	print("[shots] %s: %d blocks, %d boxes, %d skin, %d ms" % [path, layout.blocks.size(), (whole.boxes as Array).size(), (whole.skin as Array).size(), Time.get_ticks_msec() - t0])
	var village := {"boxes": ZoneModules.boxes("village"), "skin": ZoneModules.skin("village"), "streets": [], "pad_sea": NAN}
	path = out.path_join("village.png")
	drawer._draw(village, path)
	print("[shots] %s: %d boxes, %d skin" % [path, (village.boxes as Array).size(), (village.skin as Array).size()])
	drawer.free()
	print("[shots] done: %s" % out)
	get_tree().quit()
