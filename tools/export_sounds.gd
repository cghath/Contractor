extends SceneTree
## Writes every sound's generated variants (Sfx.synth, data/sounds.json) as WAV files into
## the folder given after --, so they can be listened to outside the game:
##   <voxel godot exe> --headless --path . -s res://tools/export_sounds.gd -- <out folder>
## Quits by itself (a script error would otherwise leave it idling: docs/debugging.md).

const SOUNDS := "res://data/sounds.json"
const VARIANTS := 3  # Sfx.SYNTH_VARIANTS


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://sounds"
	DirAccess.make_dir_recursive_absolute(out)
	var defs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS)).sounds
	var n := 0
	for id: String in defs:
		var recipe: Dictionary = defs[id].get("synth", {})
		for v in VARIANTS:
			var wav: AudioStreamWAV = SfxSynth.make(recipe, hash(id) + v * 7919)
			if wav.save_to_wav(out.path_join("%s_%d.wav" % [id, v + 1])) == OK:
				n += 1
	print("exported %d sounds to %s" % [n, out])
	quit(0)
