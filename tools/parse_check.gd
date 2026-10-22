extends SceneTree
## Loads the given scripts and says which fail to compile (a quick check before a suite run):
##   <godot> --headless --path . -s res://tools/parse_check.gd -- res://scripts/ui/a.gd ...


func _initialize() -> void:
	var bad := 0
	for p: String in OS.get_cmdline_user_args():
		var s := load(p) as Script
		if s == null or not s.can_instantiate():
			print("PARSE FAIL ", p)
			bad += 1
		else:
			print("ok ", p)
	quit(1 if bad > 0 else 0)
