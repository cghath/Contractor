class_name SurvivalLevel
extends ZoneLevel
## A zone of a survival world (docs/survival.md): one of the campaign's zones, overrun. Built as
## the ZoneLevel it is, with the living taken out: no garrisons, no patrols or QRFs, no US sites
## or faction skirmishes (ZoneLevel asks is_survival()), and no squad of bots filling the slots
## (players only; companions come from the world, S4). What's dropped stays (ZoneCleanup keeps
## drops in survival: a dead survivor's kit lies where he fell). The world itself, the needs and
## the dead are Survival's (the autoload).


func level_info() -> Dictionary:
	return {"level": "survival", "def": def}


func _ready() -> void:
	def["survival"] = true
	def["no_pallets"] = true  # (no supply pallets: nobody's resupplying anyone)
	super._ready()
	add_child(ZoneDead.new())  # the crowd tier of the dead (S3), the same path on every peer
	if multiplayer.is_server():
		Survival.server_level_ready(self)


## Host: a survivor comes in with his saved kit and needs (or a fresh survivor's).
func _add_player(id: int) -> void:
	super._add_player(id)
	var p := players.get_node_or_null(str(id)) as Soldier
	if p:
		Survival.server_survivor_joined(p)


## Host: nobody holds the sites.
func garrison_size(_module_id: String) -> int:
	return 0


## Host: the squad is the players (and the companions they've recruited, S4); no bots fill the
## empty slots.
func _spawn_squadmate(_slot: int, _role: StringName, _team: int) -> Soldier:
	return null


## Host: the players' squad only; the enemy's answer (patrols, QRF waves, hunters) never starts.
func _spawn_ai() -> void:
	_ai_ready = true
	rebalance_squad()


## Host: a survivor comes back at the world's safehouse (Survival.respawn_at), else as any zone.
func respawn_point(player: Soldier) -> Vector3:
	var at: Variant = Survival.respawn_at(self, player)
	return at if at is Vector3 else super.respawn_point(player)


## The level `node` is in, if it's a survival zone.
static func of(node: Node) -> SurvivalLevel:
	return CompoundLevel.current(node) as SurvivalLevel
