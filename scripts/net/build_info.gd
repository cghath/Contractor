class_name BuildInfo
extends RefCounted
## Which build this is, for the main menu's title, the pause menu, the session log and the join
## check (Net: a host refuses a player on another commit). A test build (tools/make_build.sh)
## says "B0367 · dev ec22a34", from build_label.txt beside the game (make_build.sh writes it)
## or else the build folder's own name (contractor-<date>-<time>-B0367-dev-ec22a34); a run in
## the editor says "editor <branch> <commit>" from the checkout's git files.

static var _label := ""
static var _commit := ""


## "B0367 · dev ec22a34", "editor test/coop-soak 1a2b3c4", or "unknown build".
static func label() -> String:
	_resolve()
	return _label


## The commit the game was made from (7 characters), or "" when it can't be told.
static func commit() -> String:
	_resolve()
	return _commit


static func _resolve() -> void:
	if _label != "":
		return
	# Test-only (dev tools): pretend to be another commit, to try the join check.
	var fake := OS.get_environment("CONTRACTOR_BUILD_COMMIT")
	if fake != "" and DevTools.on():
		_commit = fake
		_label = "test %s" % fake
		return
	var pack_dir := _main_pack_dir()
	if OS.has_feature("editor") and pack_dir == "":
		var root := ProjectSettings.globalize_path("res://")
		_commit = SessionLog._git_sha(root)
		if _commit == "nosha":
			_commit = ""
		_label = "editor %s %s" % [_git_branch(root), _commit if _commit != "" else "nosha"]
		return
	var dir := pack_dir if pack_dir != "" else OS.get_executable_path().get_base_dir()
	var text := FileAccess.get_file_as_string(dir.path_join("build_label.txt")).strip_edges()
	if text == "":
		text = dir.get_file()
	var m := RegEx.create_from_string("(B\\d+)-(.+)-([0-9a-f]{7,40})$").search(text)
	if m:
		_commit = m.get_string(3).left(7)
		_label = "%s · %s %s" % [m.get_string(1), m.get_string(2), _commit]
		return
	# An older or renamed folder: BUILD.txt's "Contractor test build B0367: dev" and "commit ec22a34".
	var info := FileAccess.get_file_as_string(dir.path_join("BUILD.txt"))
	var b := RegEx.create_from_string("build (B\\d+): ?(.*)").search(info)
	var c := RegEx.create_from_string("commit ([0-9a-f]{7,40})").search(info)
	_commit = c.get_string(1).left(7) if c else ""
	if b or c:
		_label = "%s · %s %s" % [b.get_string(1) if b else "B?", b.get_string(2).strip_edges() if b else "", _commit if c else "?"]
	else:
		_label = "unknown build"


## The folder of the pack given with --main-pack (play.bat runs the editor binary that way).
static func _main_pack_dir() -> String:
	var args := OS.get_cmdline_args()
	var i := args.find("--main-pack")
	return args[i + 1].get_base_dir() if i >= 0 and i + 1 < args.size() else ""


## The checked-out branch of the checkout or worktree at `dir`, "detached", or "?".
static func _git_branch(dir: String) -> String:
	var git := dir.path_join(".git")
	if FileAccess.file_exists(git):  # a worktree: "gitdir: <path>"
		git = FileAccess.get_file_as_string(git).strip_edges().trim_prefix("gitdir:").strip_edges()
	var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
	if head.begins_with("ref:"):
		return head.trim_prefix("ref:").strip_edges().trim_prefix("refs/heads/")
	return "detached" if head != "" else "?"
