class_name CommandMenu
extends PanelContainer
## Arma 3-style squad command menu, local to the player who opens it.
##
## F1-F8 select squadmates by their slot in the squad (fire team A is F1-F4, B is F5-F8;
## players can't be ordered), Shift adds to the selection, ` (tilde) selects them all, and
## Team > Select picks a fire team or colour team; selecting opens the menu. In the menu,
## 1-9 and 0 pick an entry, or scroll the
## mouse wheel to highlight one and click the middle mouse button. Backspace goes back a
## level and Esc closes. Orders go to the host as Soldier._server_squad_command.
##
## Entries with "cmd" are orders ("point": at the spot under the crosshair, "aim": at the
## enemy under it; "hvt": at the HVT under it; "squadmate": at the squadmate under it); entries with "select" change the selection (fire team or colour team)
## and keep the menu open. Status > Report enemy position ("radio_report", people, wave 4)
## reports the enemies under the crosshair by radio (PeopleLayer.request_report).
##
## ui-modern (Captain, 2026-10-20: "common sense layout tools"): the highlighted row has a
## background and an accent bar, and with the mouse free (Alt, or any screen that frees it) a
## row is hovered and clicked like a button. A footer says the keys.
##
## Holding T and saying an order (VoiceOrder, voice_commands.gd) is an alternate way to send
## the same key presses through handle_input() - it isn't a second command path. Holding T
## while looking at a friendly or civilian instead asks them a question (VoiceQuestions).

const MENU := {
	"title": "Command",
	"items": [
		{"key": "1", "label": "Move", "items": [
			{"key": "1", "label": "Return to formation", "cmd": "follow"},
			{"key": "2", "label": "Move there", "cmd": "move", "point": true},
			{"key": "3", "label": "Stop", "cmd": "hold"},
			{"key": "4", "label": "Bound there (buddy covers)", "cmd": "bound", "point": true},
			{"key": "5", "label": "Take cover", "cmd": "take_cover"},
			{"key": "6", "label": "Fall back", "cmd": "fall_back"},
			{"key": "7", "label": "Garrison that building", "cmd": "garrison", "point": true},
			{"key": "9", "label": "Climb up there (wall, roof)", "cmd": "climb", "point": true},
			{"key": "8", "label": "Clear", "items": [  # Captain, 2026-10-16: stack, breach, clear; whole towns
				{"key": "1", "label": "That building (no bang; a breacher makes the way in)", "cmd": "clear", "point": true},
				{"key": "2", "label": "That building, flashbang first", "cmd": "clear:flash", "point": true},
				{"key": "3", "label": "That building, frag first", "cmd": "clear:frag", "point": true},
				{"key": "4", "label": "That building, blow a way in (charge)", "cmd": "clear:charge", "point": true},
				{"key": "5", "label": "The town there, building by building", "cmd": "clear_town", "point": true},
				{"key": "6", "label": "The town there, flashbangs", "cmd": "clear_town:flash", "point": true},
				{"key": "7", "label": "That building, on me (they stack, you lead in)", "cmd": "clear:onme", "point": true},
				## Captain, 2026-10-20: breachers (Squad.breach_plan): the breacher kicks it in or
				## shotguns the hinge (the first in the stack, with no breacher), or eases it open.
				{"key": "8", "label": "That building, kick it in", "cmd": "clear:kick", "point": true},
				{"key": "9", "label": "That building, shotgun the door", "cmd": "clear:shotgun", "point": true},
				{"key": "0", "label": "That building, quietly (eased open, no bang)", "cmd": "clear:open", "point": true},
			]},
			## Captain, 2026-10-17: a squad he leads no longer flanks or assaults on its own.
			{"key": "0", "label": "Attack", "items": [
				{"key": "1", "label": "Flank the enemy there", "cmd": "flank", "point": true},
				{"key": "2", "label": "Flank known enemy", "cmd": "flank:known"},
				{"key": "3", "label": "Assault the enemy there", "cmd": "assault", "point": true},
				{"key": "4", "label": "Assault known enemy", "cmd": "assault:known"},
			]},
		]},
		{"key": "2", "label": "Target", "items": [
			{"key": "1", "label": "Target that enemy", "cmd": "target", "aim": true},
			{"key": "2", "label": "No target", "cmd": "target:"},
			{"key": "3", "label": "Suppress there", "cmd": "suppress", "point": true},
			{"key": "4", "label": "Suppress known enemy", "cmd": "suppress:known"},
			{"key": "5", "label": "Watch that sector", "cmd": "watch", "point": true},
		]},
		{"key": "3", "label": "Engage", "items": [
			{"key": "1", "label": "Open fire", "cmd": "open_fire"},
			{"key": "2", "label": "Hold fire", "cmd": "hold_fire"},
			{"key": "3", "label": "Stance", "items": [
				{"key": "1", "label": "Stand", "cmd": "stance:up"},
				{"key": "2", "label": "Crouch", "cmd": "stance:crouch"},
				{"key": "3", "label": "Prone", "cmd": "stance:prone"},
				{"key": "4", "label": "Their choice", "cmd": "stance:auto"},
			]},
		]},
		{"key": "4", "label": "Mount", "items": [  # wave 5 (VehicleLayer); the full set is V4's
			{"key": "1", "label": "Get in that vehicle", "cmd": "mount", "point": true},
			{"key": "2", "label": "Get out", "cmd": "dismount"},
			## Captain, 2026-10-15: a selected squadmate mans that vehicle's gun.
			{"key": "3", "label": "Take the gun", "cmd": "take_gun", "point": true},
			## Captain, 2026-10-19: the squad's AI drives (SquadDrivers); part 2 (2026-10-20):
			## mount up, carry us there, columns, contact by threat and armour.
			{"key": "4", "label": "Take the wheel", "cmd": "take_wheel", "point": true},
			{"key": "5", "label": "Mount up (our vehicles)", "cmd": "mount_up"},
			{"key": "6", "label": "Drive", "items": [
				{"key": "1", "label": "Drive there (by road)", "cmd": "drive_to", "point": true},
				{"key": "2", "label": "Drive there cross-country", "cmd": "drive_offroad", "point": true},
				{"key": "3", "label": "Carry us there (dismount short)", "cmd": "carry", "point": true},
				{"key": "4", "label": "Follow me in vehicles", "cmd": "convoy"},
				{"key": "5", "label": "Come pick us up", "cmd": "pickup"},
				{"key": "6", "label": "Stop the vehicles", "cmd": "drive_stop"},
			]},
			{"key": "7", "label": "On contact: judge it / drive through", "cmd": "contact_dismount"},
		]},
		{"key": "5", "label": "Status", "items": [
			{"key": "1", "label": "Report status", "cmd": "report"},
			{"key": "2", "label": "Report enemy position (radio)", "cmd": "radio_report"},
			## Captain, 2026-10-19: ask for a medic, or tell the selected squadmate to treat you.
			{"key": "3", "label": "Medic! (call for help)", "cmd": "call_medic"},
			{"key": "4", "label": "Treat me (the one selected)", "cmd": "treat_me"},
		]},
		{"key": "6", "label": "Action", "items": [
			{"key": "1", "label": "Throw smoke there", "cmd": "throw_smoke", "point": true},
			{"key": "2", "label": "Throw frag there", "cmd": "throw_frag", "point": true},
			{"key": "3", "label": "Fire launcher there", "cmd": "fire_launcher", "point": true},
			{"key": "4", "label": "Launcher out", "cmd": "launcher_out"},
			{"key": "5", "label": "Heal up", "cmd": "heal"},
			{"key": "6", "label": "Gear", "items": [
				{"key": "1", "label": "Rearm from that body", "cmd": "scavenge", "point": true},
				{"key": "2", "label": "Scavenge freely", "cmd": "scavenge_on"},
				{"key": "3", "label": "Don't scavenge", "cmd": "scavenge_off"},
				{"key": "4", "label": "Give me ammo", "cmd": "give_ammo"},
				{"key": "5", "label": "Drop packs here", "cmd": "drop_packs"},
				{"key": "6", "label": "Pick packs up", "cmd": "pick_packs"},
				{"key": "7", "label": "Climb into the HX-1", "cmd": "exo_in"},
				{"key": "8", "label": "Climb out of the suit", "cmd": "exo_out"},
			]},
			{"key": "7", "label": "Casualties", "items": [
				{"key": "1", "label": "Treat that casualty", "cmd": "treat", "squadmate": true},
				{"key": "2", "label": "Bring casualties there", "cmd": "ccp", "point": true},
				{"key": "3", "label": "Bring casualties to me", "cmd": "ccp_me"},
				{"key": "4", "label": "Stop bringing casualties", "cmd": "ccp_off"},
			]},
			{"key": "0", "label": "Weapons team", "items": [  # G-25 part d: the squadmates carrying a static weapon's loads
				{"key": "1", "label": "Set up the gun there", "cmd": "wt_setup", "point": true},
				{"key": "2", "label": "Set up on high ground", "cmd": "wt_high"},
				{"key": "3", "label": "Mortar: fire on that point", "cmd": "wt_fire", "point": true},
				{"key": "4", "label": "Pack up and follow", "cmd": "wt_pack"},
			]},
			{"key": "8", "label": "Escort that HVT", "cmd": "escort", "hvt": true},
			{"key": "9", "label": "Stop escorting", "cmd": "escort:"},
		]},
		{"key": "7", "label": "Combat mode", "items": [
			{"key": "1", "label": "Safe", "cmd": "mode:safe"},
			{"key": "2", "label": "Aware", "cmd": "mode:aware"},
			{"key": "3", "label": "Combat", "cmd": "mode:combat"},
			{"key": "4", "label": "Stealth", "cmd": "mode:stealth"},
		]},
		{"key": "8", "label": "Formation", "items": [
			{"key": "1", "label": "Wedge", "cmd": "formation:wedge"},
			{"key": "2", "label": "File", "cmd": "formation:file"},
			{"key": "3", "label": "Line", "cmd": "formation:line"},
			{"key": "4", "label": "Staggered column", "cmd": "formation:staggered column"},
			# Captain, 2026-10-14: "so long as I can set them to be dynamic": Dynamic (the default)
			# lets the squad pick by where it is (Squad._update_context). For the squad, or the
			# fire team selected.
			{"key": "5", "label": "Column", "cmd": "formation:column"},
			{"key": "6", "label": "Dynamic", "cmd": "formation:dynamic"},
			{"key": "7", "label": "Spacing", "items": [
				{"key": "1", "label": "Tight", "cmd": "spacing:tight"},
				{"key": "2", "label": "Normal", "cmd": "spacing:normal"},
				{"key": "3", "label": "Wide", "cmd": "spacing:wide"},
				{"key": "4", "label": "Dynamic", "cmd": "spacing:dynamic"},
			]},
		]},
		{"key": "9", "label": "Team", "items": [
			{"key": "1", "label": "Select fire team A", "select": "fire:0"},
			{"key": "2", "label": "Select fire team B", "select": "fire:1"},
			{"key": "5", "label": "Move selected to fire team", "items": [  # Captain, 2026-10-16: any split, not 4 + 4
				{"key": "1", "label": "Fire team A (with me)", "cmd": "fireteam:0"},
				{"key": "2", "label": "Fire team B", "cmd": "fireteam:1"},
			]},
			{"key": "3", "label": "Assign to team", "items": [
				{"key": "1", "label": "Red", "cmd": "team:red"},
				{"key": "2", "label": "Green", "cmd": "team:green"},
				{"key": "3", "label": "Blue", "cmd": "team:blue"},
				{"key": "4", "label": "Yellow", "cmd": "team:yellow"},
				{"key": "5", "label": "White (no team)", "cmd": "team:white"},
			]},
			{"key": "4", "label": "Select team", "items": [
				{"key": "1", "label": "Red", "select": "color:red"},
				{"key": "2", "label": "Green", "select": "color:green"},
				{"key": "3", "label": "Blue", "select": "color:blue"},
				{"key": "4", "label": "Yellow", "select": "color:yellow"},
			]},
			{"key": "6", "label": "Assign role", "items": [  # Captain, 2026-10-20: breacher roles (Squad.assign_role; the kit stays)
				{"key": "1", "label": "Breacher", "cmd": "role:breacher"},
				{"key": "2", "label": "Team Leader", "cmd": "role:team_leader"},
				{"key": "3", "label": "Medic", "cmd": "role:medic"},
				{"key": "4", "label": "Autorifleman", "cmd": "role:autorifleman"},
				{"key": "5", "label": "Grenadier", "cmd": "role:grenadier"},
				{"key": "6", "label": "Marksman", "cmd": "role:marksman"},
				{"key": "7", "label": "Rifleman", "cmd": "role:rifleman"},
				{"key": "8", "label": "Anti-Tank", "cmd": "role:anti_tank"},
				{"key": "9", "label": "Heavy Gunner", "cmd": "role:heavy_gunner"},
				{"key": "0", "label": "Ammo Bearer", "cmd": "role:ammo_bearer"},
			]},
		]},
		{"key": "0", "label": "Support", "items": [  # wave 5b: handlers registered with Supports
			{"key": "1", "label": "Helicopter transport", "items": [  # V3: HeliSupports (marker = a grid on the map)
				{"key": "1", "label": "Pick up at my map marker", "cmd": "support:transport:marker"},
				{"key": "2", "label": "Pick up there", "cmd": "support:transport:here", "point": true},
				{"key": "3", "label": "Pick up on smoke (green, blue)", "cmd": "support:transport:smoke"},
				{"key": "4", "label": "Fly to my map marker", "cmd": "support:transport:dest"},
				{"key": "5", "label": "Fly us on to the next zone (toward my map marker)", "cmd": "support:transport:zone"},
				{"key": "6", "label": "Send it home", "cmd": "support:transport:cancel"},
			]},
			{"key": "2", "label": "Resupply drop", "items": [
				{"key": "1", "label": "At my map marker", "cmd": "support:resupply:marker"},
				{"key": "2", "label": "There", "cmd": "support:resupply:here", "point": true},
				{"key": "3", "label": "On smoke (green, yellow)", "cmd": "support:resupply:smoke"},
				{"key": "4", "label": "Send it home", "cmd": "support:resupply:cancel"},
			]},
			## Fire support (2026-10-20): FireSupport's fire missions and UavSupport's recon UAV. "lase":
			## through binoculars the point is lased (FireSupport.lase_point: further, a smaller error).
			{"key": "3", "label": "Fire support", "items": [
				{"key": "1", "label": "Mortars: fire mission at my map marker", "cmd": "support:fire:call:mortar:marker"},
				{"key": "2", "label": "Mortars: fire mission there", "cmd": "support:fire:call:mortar:here", "point": true, "lase": true},
				{"key": "3", "label": "Artillery: fire mission at my map marker", "cmd": "support:fire:call:artillery:marker"},
				{"key": "4", "label": "Artillery: fire mission there", "cmd": "support:fire:call:artillery:here", "point": true, "lase": true},
				{"key": "5", "label": "Adjust fire", "items": [
					{"key": "1", "label": "Add 100", "cmd": "support:fire:adjust::add 100"},
					{"key": "2", "label": "Add 50", "cmd": "support:fire:adjust::add 50"},
					{"key": "3", "label": "Drop 50", "cmd": "support:fire:adjust::drop 50"},
					{"key": "4", "label": "Drop 100", "cmd": "support:fire:adjust::drop 100"},
					{"key": "5", "label": "Left 50", "cmd": "support:fire:adjust::left 50"},
					{"key": "6", "label": "Left 25", "cmd": "support:fire:adjust::left 25"},
					{"key": "7", "label": "Right 25", "cmd": "support:fire:adjust::right 25"},
					{"key": "8", "label": "Right 50", "cmd": "support:fire:adjust::right 50"},
					{"key": "9", "label": "Repeat (another round, same aim)", "cmd": "support:fire:repeat:"},
				]},
				{"key": "6", "label": "Fire for effect", "items": [
					{"key": "1", "label": "HE, 3 rounds", "cmd": "support:fire:ffe::he:3"},
					{"key": "2", "label": "HE, 6 rounds", "cmd": "support:fire:ffe::he:6"},
					{"key": "3", "label": "Smoke, 3 rounds", "cmd": "support:fire:ffe::smoke:3"},
					{"key": "4", "label": "Smoke, 6 rounds", "cmd": "support:fire:ffe::smoke:6"},
				]},
				{"key": "7", "label": "Confirm danger close", "cmd": "support:fire:confirm:"},
				{"key": "8", "label": "End of mission", "cmd": "support:fire:end:"},
				{"key": "9", "label": "Fire mission panel (type corrections, grids)", "cmd": "local:fire_panel"},
				{"key": "0", "label": "Recon UAV", "items": [
					{"key": "1", "label": "Over my map marker", "cmd": "support:uav:marker"},
					{"key": "2", "label": "Over there", "cmd": "support:uav:here", "point": true, "lase": true},
					{"key": "3", "label": "Over us", "cmd": "support:uav:me"},
					{"key": "4", "label": "Open the UAV feed", "cmd": "local:uav_feed"},
					{"key": "5", "label": "Send it home", "cmd": "support:uav:home"},
				]},
			]},
			{"key": "4", "label": "Helicopter extraction", "items": [
				{"key": "1", "label": "At my map marker", "cmd": "support:extraction:marker"},
				{"key": "2", "label": "There", "cmd": "support:extraction:here", "point": true},
				{"key": "3", "label": "On purple smoke", "cmd": "support:extraction:smoke"},
				{"key": "4", "label": "Near us: the pilot picks an LZ in dead ground", "cmd": "support:extraction:near"},
				{"key": "5", "label": "Send it home", "cmd": "support:extraction:cancel"},
			]},
			{"key": "6", "label": "Medevac (Dustoff)", "items": [  # Captain, 2026-10-16: loads the downed and carried, flies them out alive
				{"key": "1", "label": "At my map marker", "cmd": "support:medevac:marker"},
				{"key": "2", "label": "There", "cmd": "support:medevac:here", "point": true},
				{"key": "3", "label": "On smoke (yellow, green)", "cmd": "support:medevac:smoke"},
				{"key": "4", "label": "Near us: the pilot picks an LZ", "cmd": "support:medevac:near"},
				{"key": "5", "label": "Send it home", "cmd": "support:medevac:cancel"},
			]},
			## The locals' call-ins (RebelCalls; rebel support): free, by their support in the region.
			{"key": "9", "label": "Rebels", "items": [
				{"key": "1", "label": "Lookouts (they mark the gunmen near you)", "cmd": "support:rebel_lookouts"},
				{"key": "2", "label": "Diversion: open fire there", "cmd": "support:rebel_diversion", "point": true},
				{"key": "3", "label": "Rebel fighters", "cmd": "support:rebel_fighters"},
				{"key": "4", "label": "Vehicle drop there", "cmd": "support:rebel_vehicle_drop", "point": true},
				{"key": "5", "label": "Mortar there", "cmd": "support:rebel_mortar", "point": true},
			]},
			{"key": "7", "label": "Cargo run (loot home)", "items": [  # Captain, 2026-10-16: a chopper to send loot back to base
				{"key": "1", "label": "At my map marker", "cmd": "support:cargo:marker"},
				{"key": "2", "label": "There", "cmd": "support:cargo:here", "point": true},
				{"key": "3", "label": "On smoke (green, blue)", "cmd": "support:cargo:smoke"},
				{"key": "4", "label": "Send it home with what's aboard", "cmd": "support:cargo:cancel"},
			]},
			{"key": "5", "label": "AAV", "items": [
				{"key": "1", "label": "Call an AAV", "cmd": "support:aav_call"},
				{"key": "2", "label": "Move there", "cmd": "support:aav_move", "point": true},
				{"key": "3", "label": "Hold", "cmd": "support:aav_hold"},
				{"key": "4", "label": "Follow me", "cmd": "support:aav_follow"},
				{"key": "5", "label": "Squad get in", "cmd": "support:aav_mount"},
				{"key": "6", "label": "Dismount", "cmd": "support:aav_dismount"},
				{"key": "7", "label": "Return to base", "cmd": "support:aav_return"},
			]},
			{"key": "8", "label": "Allied troops", "items": [  # wave 6e: AlliedTroops; orders go to every element (the host's high command; one at a time: right click the map)
				{"key": "1", "label": "Call a rifle squad", "cmd": "support:allied_call:rifle"},
				{"key": "2", "label": "Call a weapons team (M2, MG + AT)", "cmd": "support:allied_call:weapons"},
				{"key": "3", "label": "All: move there", "cmd": "support:allied_move", "point": true},
				{"key": "4", "label": "All: hold", "cmd": "support:allied_hold"},
				{"key": "5", "label": "All: assault there", "cmd": "support:allied_assault", "point": true},
				{"key": "6", "label": "All: flank there", "cmd": "support:allied_flank", "point": true},
				{"key": "7", "label": "All: follow me", "cmd": "support:allied_follow"},
				{"key": "8", "label": "All: fall back there", "cmd": "support:allied_fall_back", "point": true},
				{"key": "9", "label": "Release all", "cmd": "support:allied_release"},
				{"key": "0", "label": "Call a company squad (hired)", "cmd": "support:allied_call:company"},
			]},
			## An operation's own (cg_brief queue item 3.3, OpSupport and the types' mechanics): the
			## armour attached to the company, the employer's guns, the column, the bridge, the town.
			{"key": "0", "label": "Operation", "items": [
				{"key": "1", "label": "Attached armour", "items": [
					{"key": "1", "label": "Overwatch our task", "cmd": "support:op_attached:task"},
					{"key": "2", "label": "Move there", "cmd": "support:op_attached:move", "point": true},
					{"key": "3", "label": "Hold", "cmd": "support:op_attached:hold"},
					{"key": "4", "label": "Follow me", "cmd": "support:op_attached:follow"},
					{"key": "5", "label": "Take its gun (aboard)", "cmd": "support:op_attached:gun"},
					{"key": "6", "label": "Give its gun back", "cmd": "support:op_attached:crew"},
				]},
				{"key": "2", "label": "Allied fires", "items": [
					{"key": "1", "label": "Mortars there", "cmd": "support:op_fire:mortar", "point": true},
					{"key": "2", "label": "Artillery there", "cmd": "support:op_fire:artillery", "point": true},
					{"key": "3", "label": "Naval gunfire there", "cmd": "support:op_fire:naval", "point": true},
				]},
				{"key": "3", "label": "Column: bypass the position off-road", "cmd": "support:op_column:bypass"},
				{"key": "4", "label": "Column: move on now", "cmd": "support:op_column:go"},
				{"key": "5", "label": "Cut the firing wire", "cmd": "support:op_cut"},
				{"key": "6", "label": "Field defences", "items": [
					{"key": "1", "label": "Sandbag wall", "cmd": "local:op_defence:sandbags"},
					{"key": "2", "label": "HESCO bastion", "cmd": "local:op_defence:hesco"},
					{"key": "3", "label": "Concertina wire", "cmd": "local:op_defence:wire"},
				]},
			]},
		]},
	],
}
const NUMBER_KEYS := {KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4", KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9", KEY_0: "0"}
const F_KEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]
## How far "Target that enemy" looks under the crosshair.
const AIM_RANGE := PlayerInput.ORDER_RANGE_M  # (was 300 m: Captain, 2026-10-20, longer order range)

## The selection path wraps past this width (logical px).
const TITLE_W := 300.0
## The footer of keys shows on windows at least this tall (logical px): the longest menus need
## the room on a short one.
const KEYS_MIN_HEIGHT := 700.0

var player: Soldier
## Names of the selected squadmates.
var selected := PackedStringArray()
var _stack: Array = []  # menu levels from the root down
var _highlight := 0
## The row under the mouse (-1: none).
var _hovered := -1
var _title: Label
## A short note after the title (the HUD's "+n squad lines below" when the open menu leaves the
## squad list no line at all; review of ui/hud-pass, 2026-10-14: cut to fit, never silently).
var note := "":
	set(value):
		if note != value:
			note = value
			if visible and not _stack.is_empty():
				_redraw()
var _rows: VBoxContainer
## The footer line of keys.
var _keys: Label
## The width the selection path wraps at: TITLE_W, or less in the HUD's left column (Hud._layout
## sets it) so the open menu stays out of the centre column at a big UI scale.
var title_width := TITLE_W:
	set(value):
		if not is_equal_approx(title_width, value):
			title_width = value
			_fit_title()


func _init(p_player: Soldier) -> void:
	player = p_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	## The shared look (Captain, 2026-10-14: "all the UIs need a pass"; docs/ui_audit.md P2-19):
	## the theme's panel instead of a hand-made StyleBox, a heading for the selection path, and
	## rows of a key chip and a label in the theme's colours.
	UiKit.apply(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	add_child(box)
	_title = UiKit.heading("")
	## Eight names in the path ran the panel off a small window; it wraps at title_width instead.
	UiKit._follow_window(_title, _fit_title)
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 2)
	box.add_child(_rows)
	_keys = UiKit.hint("1-9 pick   Wheel + middle click   Backspace back   Esc close")
	_keys.name = "Keys"
	_keys.custom_minimum_size.x = TITLE_W
	box.add_child(_keys)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	## Grows both ways from the left middle (a long submenu stayed below the centre line), kept
	## UiKit.EDGE from the window's edge.
	grow_vertical = Control.GROW_DIRECTION_BOTH
	position.x += UiKit.EDGE
	visible = false


## The title's wrap width: title_width, cut to the window (as UiKit.fit_width).
func _fit_title() -> void:
	if _title == null or not _title.is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var room := view.x - UiKit.EDGE * 2.0 - 40.0
	_title.custom_minimum_size.x = maxf(minf(title_width, room), 120.0)
	if _keys != null:
		# As wide as the title (a wrapping label with no width asks to be one word wide and very
		# tall, and the panel, growing both ways from the middle, kept that height).
		_keys.custom_minimum_size.x = _title.custom_minimum_size.x
		_keys.visible = view.y >= KEYS_MIN_HEIGHT  # a short window keeps its room for the rows


func is_open() -> bool:
	return visible


## The squad as numbered in the menu: by squad slot (fire team A, then B), so F1 is the
## first slot. Anyone without a slot yet comes last, players first. A dead squadmate's body
## isn't listed (it left the squad: Squad.members).
func roster() -> Array[Soldier]:
	var out: Array[Soldier] = []
	var level := CompoundLevel.current(self) if is_inside_tree() else null
	if level == null or player == null:
		return out
	for h in level.players.get_children():
		if h is Soldier and not h.is_queued_for_deletion():
			out.append(h as Soldier)
	for s in level.ai.get_children():
		if s is Soldier and s.faction == player.faction and not s.is_queued_for_deletion() and not (s as Soldier).vitals.is_dead() \
				and (s as Soldier).hc_id == &"" and (s as Soldier).iff not in [&"allied", &"rebel"]:  # G3: the player squad's men only (not hero squads, elements, US troops)
			out.append(s as Soldier)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool: return _roster_key(a) < _roster_key(b))
	return out


static func _roster_key(s: Soldier) -> String:
	if s.squad_slot >= 0:
		return "0%02d" % s.squad_slot
	return ("1%06d" % s.name.to_int()) if not s.is_ai() else "2" + String(s.name)


## "A, Team Leader" (plus the colour team if any): a squad member's place in the squad.
static func unit_tag(s: Soldier) -> String:
	var parts := PackedStringArray()
	if s.fire_team >= 0 and s.fire_team < Roles.TEAMS.size():
		parts.append(Roles.TEAMS[s.fire_team])
	if s.role != &"":
		parts.append(Roles.display_name(s.role))
	if s.color_team != "":
		parts.append(s.color_team.capitalize())
	return ", ".join(parts)


## Returns true if the event was a command-menu input.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key in F_KEYS:
			_select_number(F_KEYS.find(key) + 1, event.shift_pressed or event.ctrl_pressed)
			return true
		if key == KEY_QUOTELEFT:
			_select_all()
			return true
		if not visible:
			return false
		if NUMBER_KEYS.has(key):
			_pick_key(NUMBER_KEYS[key])
			return true
		if key == KEY_BACKSPACE:
			_back()
			return true
		if key == KEY_ESCAPE:
			close()
			return true
	if visible and event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_highlight = posmod(_highlight - 1, _level_items().size())
				_restyle()
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_highlight = posmod(_highlight + 1, _level_items().size())
				_restyle()
				return true
			MOUSE_BUTTON_MIDDLE:
				_pick(_highlight)
				return true
	return false


func open() -> void:
	_stack = [MENU]
	_highlight = 0
	visible = true
	_redraw()


func close() -> void:
	visible = false
	_stack.clear()


func _select_number(n: int, add: bool) -> void:
	var units := roster()
	if n > units.size():
		return
	var unit := units[n - 1]
	if not unit.is_ai():
		player._hud.flash("%d is %s: you can't order players" % [n, "you" if unit == player else "a player"])
		return
	var callsign := String(unit.name)
	if not add and not visible:
		selected = PackedStringArray()
	if callsign in selected:
		selected.remove_at(selected.find(callsign))
	else:
		selected.append(callsign)
	if selected.is_empty():
		close()
	elif not visible:
		open()
	else:
		_redraw()


func _select_all() -> void:
	var all := PackedStringArray()
	for s in roster():
		if s.is_ai():
			all.append(String(s.name))
	if visible and selected.size() == all.size():
		selected = PackedStringArray()
		close()
		return
	selected = all
	open()


func _level_items() -> Array:
	return _stack[-1]["items"] if not _stack.is_empty() else []


func _pick_key(key: String) -> void:
	var items := _level_items()
	for i in items.size():
		if items[i]["key"] == key:
			_pick(i)
			return


func _pick(i: int) -> void:
	var items := _level_items()
	if i < 0 or i >= items.size():
		return
	var item: Dictionary = items[i]
	if item.has("items"):
		if (item["items"] as Array).is_empty():
			player._hud.flash("%s isn't in this build yet" % item["label"])
			return
		_stack.append(item)
		_highlight = 0
		_redraw()
		return
	if item.has("select"):
		_select_group(item["select"], item["label"])
		return
	var cmd: String = item.get("cmd", "")
	if cmd == "":
		player._hud.flash("%s isn't in this build yet" % item["label"])
		return
	if cmd == "report":
		_report()
		close()
		return
	if cmd == "radio_report":
		_radio_report()
		return
	if cmd.begins_with("local:"):  # fire support's own screens (the fire mission panel, the UAV feed)
		close()
		if cmd.begins_with("local:op_defence:"):  # (an operation's field defences: OpTown, cg_brief 3.3)
			OpTown.local_command(player, cmd.trim_prefix("local:"))
			return
		FireSupport.local_command(player, cmd.trim_prefix("local:"))
		return
	var point := player.global_position
	if item.get("point", false):
		var lased: bool = item.get("lase", false) and player.binoculars_up
		var hit: Variant = FireSupport.lase_point(player) if lased else player.crosshair_ground()
		if hit == null:
			player._hud.flash("Look at a spot on the ground")
			return
		point = hit
		if lased and cmd.begins_with("support:fire:"):
			cmd += ":lased"
	if item.get("aim", false):
		var enemy := enemy_under_crosshair()
		if enemy == null:
			player._hud.flash("Look at an enemy")
			return
		cmd = "%s:%s" % [cmd, enemy.name]
	if item.get("squadmate", false):
		var mate := soldier_under_crosshair()
		if mate == null or mate.faction != player.faction or mate.vitals.is_dead():
			player._hud.flash("Look at a wounded squadmate")
			return
		cmd = "%s:%s" % [cmd, mate.name]
	if item.get("hvt", false):
		var hvt := soldier_under_crosshair()
		if hvt == null or not Person.is_hvt(hvt) or hvt.vitals.is_dead():
			player._hud.flash("Look at the HVT")
			return
		cmd = "%s:%s" % [cmd, hvt.name]
	player._server_squad_command.rpc_id(1, cmd, point, selected)
	player._hud.flash("%s: %s" % [_names(), item["label"]])
	close()


## The living enemy under the crosshair (hitbox or body, up to AIM_RANGE), or null.
func enemy_under_crosshair() -> Soldier:
	var enemy := soldier_under_crosshair()
	if enemy == null or enemy.faction == player.faction or not enemy.vitals.is_up() or Person.is_noncombatant(enemy):
		return null
	return enemy


## Whoever is under the crosshair (hitbox or body, up to AIM_RANGE), or null.
func soldier_under_crosshair() -> Soldier:
	var camera := player.camera
	var from := camera.global_position
	var exclude: Array[RID] = [player.get_rid()]
	for child in player.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * AIM_RANGE,
		1 | Soldier.HITBOX_MASK | Soldier.BODY_LAYER, exclude)
	query.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	var enemy: Soldier = collider as Soldier
	if enemy == null and collider is Area3D:
		var vitals := Vitals.find_on(collider)
		enemy = vitals.get_parent() as Soldier if vitals else null
	return enemy


## Status > Report enemy position: the enemies around the one under the crosshair (or the spot
## it's on) go to the host as a radio report (PeopleLayer.request_report: banked as intel).
func _radio_report() -> void:
	var enemy := enemy_under_crosshair()
	var point: Variant = enemy.global_position if enemy else player.crosshair_ground()
	if point == null:
		player._hud.flash("Look at the enemy position")
		return
	var layer := PeopleLayer.find(player)
	if layer:
		layer.request_report.rpc_id(1, point)
	close()


## Team menu: selects fire team "fire:<0|1>" or colour team "color:<colour>" (AI only).
func _select_group(spec: String, label: String) -> void:
	var parts := spec.split(":")
	var names := PackedStringArray()
	for s in roster():
		if not s.is_ai():
			continue
		if (parts[0] == "fire" and s.fire_team == parts[1].to_int()) or (parts[0] == "color" and s.color_team == parts[1]):
			names.append(String(s.name))
	if names.is_empty():
		player._hud.flash("Nobody to select: %s" % label)
		return
	selected = names
	_stack = [MENU]
	_highlight = 0
	_redraw()
	player._hud.flash("%s: %s" % [label.trim_prefix("Select "), ", ".join(names)])


func _back() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_highlight = 0
		_redraw()
	else:
		close()


func _report() -> void:
	var lines := PackedStringArray()
	for s in roster():
		if String(s.name) in selected:
			lines.append("%s [%s]: %s (%s)" % [s.display_name(), unit_tag(s), s.ai_status, s.vitals.condition_text()])
	player._hud.flash("\n".join(lines))


func _names() -> String:
	var all := 0
	for s in roster():
		if s.is_ai():
			all += 1
	if selected.size() == all:
		return "All"
	var shown := PackedStringArray()
	for s in roster():
		if String(s.name) in selected:
			shown.append(s.display_name())  # selection is by callsign; show their names
	return ", ".join(shown)


func _redraw() -> void:
	var path := PackedStringArray([_names()])
	for i in range(1, _stack.size()):
		path.append(_stack[i]["label"])
	_title.text = "  >  ".join(path) + ("  (%s)" % note if note != "" else "")
	for child in _rows.get_children():
		child.queue_free()
	var items := _level_items()
	for i in items.size():
		var item: Dictionary = items[i]
		var disabled: bool = (item.has("items") and (item["items"] as Array).is_empty()) or (item.has("cmd") and item["cmd"] == "")
		## A row: the key chip and the label in a box that shows the highlight (HudRowHot) and
		## the hover (HudRowHover), and takes a click.
		var frame := PanelContainer.new()
		frame.name = "Row%d" % i
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.tooltip_text = ""
		frame.set_meta(&"disabled", disabled)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", UiKit.SPACE_S)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(row)
		var chip := Label.new()
		chip.text = String(item["key"])
		chip.theme_type_variation = &"KeyLabel"
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var label := Label.new()
		label.text = "%s%s" % [item["label"], "  >" if item.has("items") and not disabled else ""]
		label.theme_type_variation = &"MutedLabel" if disabled else &""
		row.add_child(label)
		var index := i
		frame.mouse_entered.connect(func() -> void:
			_hovered = index
			_restyle())
		frame.mouse_exited.connect(func() -> void:
			if _hovered == index:
				_hovered = -1
				_restyle())
		frame.gui_input.connect(func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				frame.accept_event()
				_highlight = index
				_pick.call_deferred(index))
		_rows.add_child(frame)
	_restyle()


## The rows' looks: the highlighted one (keys, wheel) bright with an accent bar, the hovered one
## faintly lit, a row that can't be picked dim.
func _restyle() -> void:
	if _rows == null:
		return
	var i := 0
	for frame: Node in _rows.get_children():
		if frame.is_queued_for_deletion() or not frame is PanelContainer:
			continue
		var f := frame as PanelContainer
		f.theme_type_variation = &"HudRowHot" if i == _highlight else (&"HudRowHover" if i == _hovered else &"HudRow")
		var label := f.get_child(0).get_child(1) as Label
		if bool(f.get_meta(&"disabled", false)):
			label.theme_type_variation = &"MutedLabel"
		else:
			label.theme_type_variation = &"AccentLabel" if i == _highlight else &""  # body size: the row keeps its height
		i += 1
