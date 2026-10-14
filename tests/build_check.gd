extends Node
## The join's build check (Net._hello, BuildInfo), by hand: two processes,
##   CONTRACTOR_PORT=P <godot> --headless --path . res://tests/build_check.tscn -- host
##   CONTRACTOR_PORT=P CONTRACTOR_BUILD_COMMIT=0000000 <godot> --headless --path . res://tests/build_check.tscn -- join
## The joiner prints "BUILD CHECK: refused ..." or "BUILD CHECK: welcomed" and quits; the host quits after 20 s.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	print("BUILD CHECK: this is %s (commit '%s')" % [BuildInfo.label(), BuildInfo.commit()])
	if "host" in args:
		Net.host()
		await get_tree().create_timer(20.0).timeout
		get_tree().quit(0)
		return
	Net.refused.connect(func(reason: String) -> void:
		print("BUILD CHECK: refused: " + reason)
		get_tree().quit(0))
	Net.join("127.0.0.1")
	await get_tree().create_timer(12.0).timeout
	print("BUILD CHECK: welcomed" if Net._welcomed else "BUILD CHECK: no answer")
	get_tree().quit(0)
