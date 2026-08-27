class_name MovementIntent
extends RefCounted
## What something wants a character to do this frame.
##
## The whole point of this class is that it has no idea who filled it in
## (rule 14). A player's controller reads it off an [InputRouter]; a patrolling
## guard's brain computes it from a navigation path; a replay reads it from a
## file. [MovementComponent] takes intent and cannot tell the difference, which
## is what makes "AI drives the same API the player does" true rather than
## aspirational.
##
## Intent is a request, not a result. Whether the character may sprint, and
## whether the jump actually happens, is decided by the profile and the solver.

## Desired direction in world space, on the horizontal plane. Length 0 to 1;
## anything longer is normalised by the solver, so a diagonal is not faster.
var direction: Vector3 = Vector3.ZERO

## Whether the mover wants to be sprinting.
var wants_sprint: bool = false

## Whether the mover wants to be crouched.
var wants_crouch: bool = false

## Set for the frame a jump is asked for. The component consumes it; the
## buffering that makes a slightly-early press still work lives there, because
## it needs to persist across frames and intent does not.
var jump_requested: bool = false


static func create(
	p_direction: Vector3 = Vector3.ZERO,
	p_wants_sprint: bool = false,
	p_wants_crouch: bool = false,
	p_jump_requested: bool = false
) -> MovementIntent:
	var intent := MovementIntent.new()
	intent.direction = p_direction
	intent.wants_sprint = p_wants_sprint
	intent.wants_crouch = p_wants_crouch
	intent.jump_requested = p_jump_requested
	return intent


## Builds intent from a 2D input vector and a facing basis.
##
## [param input] is x-strafe, y-forward with forward negative, matching
## [method InputRouter.get_move_vector]. [param basis] is whatever the movement
## should be relative to -- the camera for third-person, the character for
## tank controls -- and its pitch is discarded so looking down does not walk
## the character into the floor.
static func from_input(
	input: Vector2,
	basis: Basis = Basis.IDENTITY,
	p_wants_sprint: bool = false,
	p_wants_crouch: bool = false,
	p_jump_requested: bool = false
) -> MovementIntent:
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() > 0.0:
		forward = forward.normalized()
	if right.length_squared() > 0.0:
		right = right.normalized()
	var direction := right * input.x + forward * -input.y
	return create(direction, p_wants_sprint, p_wants_crouch, p_jump_requested)


## The horizontal direction, normalised, or zero when there is none.
func get_planar_direction() -> Vector3:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() <= 0.0:
		return Vector3.ZERO
	return planar.normalized()


func is_moving() -> bool:
	return get_planar_direction() != Vector3.ZERO


func clear() -> void:
	direction = Vector3.ZERO
	wants_sprint = false
	wants_crouch = false
	jump_requested = false
