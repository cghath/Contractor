extends SceneTree
## Writes the license notices of the engine that runs it (Godot's own MIT text, then every
## third-party part the binary was built with and the full text of each license they use) to
## the file given, so a build that ships the engine (the Voxel Tools editor, or a Contractor.exe
## made from its template) carries them (tools/ci_build.sh):
##   <godot> --headless --path . -s res://tools/engine_licenses.gd -- <out file>
## Voxel Tools' own license isn't in the engine's list (it's a module built in from outside the
## engine's tree); ci_build.sh adds it beside this file.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("engine_licenses: give the file to write")
		quit(1)
		return
	var lines: PackedStringArray = []
	var v := Engine.get_version_info()
	lines.append("Godot Engine %s (%s), the engine this build runs on" % [v.get("string", "?"), v.get("hash", "?")])
	lines.append("")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("== Third-party parts of the engine")
	var parts := Engine.get_copyright_info()
	for part: Dictionary in parts:
		lines.append("")
		lines.append(str(part.get("name", "?")))
		for p: Dictionary in part.get("parts", []):
			for c: String in p.get("copyright", []):
				lines.append("  Copyright " + c)
			lines.append("  License: " + str(p.get("license", "?")))
	var texts := Engine.get_license_info()
	for license: String in texts:
		lines.append("")
		lines.append("== License: " + license)
		lines.append("")
		lines.append(str(texts[license]))
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		printerr("engine_licenses: can't write ", args[0])
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("engine_licenses: wrote ", args[0], " (", parts.size(), " parts, ", texts.size(), " licenses)")
	quit(0)
