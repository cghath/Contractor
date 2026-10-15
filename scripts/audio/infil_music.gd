class_name InfilMusic
extends Node
## Infil music. Captain, 2026-10-14: "can we add Ride of the Valkyries to the infils
## temporarily lol" -- temporary, take it out (this script, HeliSupports' music lines, the
## "infil_music" setting and audio/music/) when it's had its fun.
##
## Every peer has one (HeliSupports makes it: freed with the level, so a level switch stops
## it). The host arms it on every peer when a helicopter insertion lifts off with the squad
## aboard (HeliSupports.server_music_start, with how far into the track it is so late arrivals
## line up) and disarms it at touchdown ("On the ground ... Out, out, out!") or when that call
## ends. Armed, this peer's player hears the track (non-positional, the Music bus) while sitting
## in that helicopter and the "infil_music" setting is on: fading in over FADE_IN_S, out over
## FADE_OUT_S at touchdown, on leaving the helicopter or the setting turned off. Never on an
## extraction or resupply: only insertions arm it. Headless (the dummy audio driver) it runs
## the same, silently, so the tests see it.

const NODE_NAME := "InfilMusic"
const PATH := "res://audio/music/ride_of_the_valkyries_1921.mp3"
const BUS := &"Music"
const FADE_IN_S := 1.0
const FADE_OUT_S := 3.0
## The track's level under the Music bus (dB): an old mono recording, kept under the rotors.
const VOLUME_DB := -6.0

enum State { IDLE, PLAYING, FADING }

var state := State.IDLE
## The armed insertion helicopter's node name ("" when nothing's armed).
var heli_name := ""
## Fade level, 0..1.
var level := 0.0
var player: AudioStreamPlayer

var _offset_s := 0.0  # how far into the track the host was when it armed this (s)
var _armed_at := 0    # Time.get_ticks_msec() when armed here


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "Player"
	player.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
	player.volume_db = -80.0
	player.finished.connect(func() -> void: state = State.IDLE)
	add_child(player)


## Whether the player wants it ("Infil music" in the Audio settings).
static func enabled() -> bool:
	return bool(GameSettings.get_value("audio", "infil_music"))


## The level's InfilMusic (or null).
static func of(from: Node) -> InfilMusic:
	var sup := HeliSupports.of(from)
	return sup.get_node_or_null(NodePath(NODE_NAME)) as InfilMusic if sup else null


## Every peer: the insertion helicopter `heli` (its node name) lifted off `elapsed_s` ago. Sent
## again for a late boarder: the same helicopter keeps its first time.
func arm(heli: String, elapsed_s: float) -> void:
	if heli == heli_name:
		return
	heli_name = heli
	_offset_s = maxf(elapsed_s, 0.0)
	_armed_at = Time.get_ticks_msec()
	if is_inside_tree() and state != State.PLAYING and _aboard() and enabled():
		_start()  # aboard already (the host's own player): at once, not from the next frame


## Every peer: touchdown (or the call's over): fades out what plays.
func disarm() -> void:
	heli_name = ""
	_fade_out()


## Where in the track it is now (s).
func track_pos() -> float:
	return _offset_s + float(Time.get_ticks_msec() - _armed_at) / 1000.0


func _process(delta: float) -> void:
	if heli_name != "":
		var aboard := _aboard()
		if state != State.PLAYING and aboard and enabled():
			_start()
		elif state == State.PLAYING and (not aboard or not enabled()):
			heli_name = ""  # left the helicopter (or turned it off): fades out, not again this flight
			_fade_out()
	if state == State.PLAYING and level < 1.0:
		level = minf(level + delta / FADE_IN_S, 1.0)
	elif state == State.FADING:
		level = maxf(level - delta / FADE_OUT_S, 0.0)
		if level <= 0.0:
			player.stop()
			state = State.IDLE
	player.volume_db = VOLUME_DB + linear_to_db(maxf(level, 0.0001))


## Whether this peer's player sits in the armed helicopter.
func _aboard() -> bool:
	var ride := Vehicle.ride_of(MapNodes.local_player(self))
	return ride != null and String(ride.name) == heli_name


func _start() -> void:
	var stream := load(PATH) as AudioStream
	if stream == null:
		heli_name = ""
		return
	var at := track_pos()
	if stream.get_length() > 0.0 and at >= stream.get_length():
		heli_name = ""  # the track's over already
		return
	player.stream = stream
	player.play(at)
	if state == State.IDLE:
		level = 0.0
	state = State.PLAYING


func _fade_out() -> void:
	if state == State.PLAYING:
		state = State.FADING
