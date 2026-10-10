class_name SoldierMovement
extends Node
## How a Soldier body moves: walking, sprinting, crouching, jumping, crawling while down,
## and the speed costs of load, aiming and carrying. Humans steer it with the keyboard
## (read here, on the owning peer); AI through the body's intent fields (move_input,
## want_sprint, want_crouch), written by SquadAI on the host.
## Stance, lean, weapon mount and momentum belong here too as they're built.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 2.0
const CRAWL_SPEED := 0.6
const ACCELERATION := 30.0
const JUMP_VELOCITY := 4.2
const STAND_HEAD_Y := 1.65
const CROUCH_HEAD_Y := 1.05
const DOWNED_HEAD_Y := 0.35
const ADS_SPEED_MULT := 0.6
## Speed while carrying or dragging a downed body.
const CARRY_BODY_SPEED_MULT := 0.55

@onready var body: Soldier = get_parent()


## One physics step for the body's owner (the human's peer, or the host for AI).
func step(delta: float) -> void:
	if not body.is_on_floor():
		body.velocity += body.get_gravity() * delta
	var steering := body.is_ai() or _captured()
	var down := not body.vitals.is_up()
	var crouching := steering and is_crouching() and not down
	var burdened := body.inventory.hands != &"" or body.carrying != null
	if not body.is_ai() and steering and Input.is_action_just_pressed(&"jump") and body.is_on_floor() and not burdened and not crouching and not down:
		body.velocity.y = JUMP_VELOCITY
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif steering and (body.want_sprint if body.is_ai() else Input.is_action_pressed(&"sprint")) and not burdened:
		speed = SPRINT_SPEED
	if body.is_aiming:
		speed = minf(speed, WALK_SPEED) * ADS_SPEED_MULT
	if down:
		speed = CRAWL_SPEED
	speed *= body.load_mult * body.vitals.speed_mult()
	if body.carrying != null:
		speed *= CARRY_BODY_SPEED_MULT
	var input := Vector2.ZERO
	if body.is_ai():
		input = body.move_input.limit_length(1.0)
	elif steering:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var target := (body.global_basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	body.velocity.x = move_toward(body.velocity.x, target.x, ACCELERATION * delta)
	body.velocity.z = move_toward(body.velocity.z, target.z, ACCELERATION * delta)
	body.move_and_slide()
	var head_y := DOWNED_HEAD_Y if down else (CROUCH_HEAD_Y if crouching else STAND_HEAD_Y)
	body.head.position.y = move_toward(body.head.position.y, head_y, 4.0 * delta)


func is_crouching() -> bool:
	return body.want_crouch if body.is_ai() else Input.is_action_pressed(&"crouch")


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
