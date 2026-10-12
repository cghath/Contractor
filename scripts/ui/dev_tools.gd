class_name DevTools
extends RefCounted
## Whether the developer keys and readouts are on (Captain 2026-10-12): K hurts you, Shift+End
## extracts, the hot zone's readout (Page Up) and clock skip (Page Down). On in the editor and
## debug builds, and in any build started with --dev (the test builds' "Contractor (dev
## tools).bat"; our exports use a release template, so OS.is_debug_build() alone is never true
## there). Players of a normal build never see them.

const FLAG := "--dev"


static func on() -> bool:
	return OS.is_debug_build() or FLAG in OS.get_cmdline_args() or FLAG in OS.get_cmdline_user_args()
