class_name MovementSolver
extends RefCounted
## Pure velocity maths for ground and air movement.
##
## Every function here is static and takes everything it needs as an argument.
## No node, no tree, no physics server, no frame. That is deliberate: rule 33
## wants domain logic testable without a live scene, and movement is the first
## place a framework usually loses that -- the maths ends up inside
## [code]_physics_process[/code] on a [CharacterBody3D], and from then on the
## only way to find out what a profile does is to play the game.
##
## Split out like this, "sprinting is faster than walking" and "a jump asked
## for one frame after leaving a ledge still fires" are unit tests that run in
## microseconds, and [MovementComponent] is left with the small job of feeding
## this the body's state and writing the answer back.


## Horizontal velocity after one step of acceleration toward the intent.
##
## [param velocity] is the full current velocity; only its x and z are used and
## returned. [param speed] is the target ground speed for the current stance.
static func solve_planar_velocity(
	velocity: Vector3,
	intent: MovementIntent,
	profile: MovementProfile,
	on_floor: bool,
	delta: float
) -> Vector3:
	if profile == null or delta <= 0.0:
		return Vector3(velocity.x, 0.0, velocity.z)

	var current := Vector3(velocity.x, 0.0, velocity.z)
	var direction := intent.get_planar_direction()
	var speed := profile.get_speed_for(intent.wants_sprint, intent.wants_crouch)
	var target := direction * speed

	var rate: float
	if not on_floor:
		# Air control scales the acceleration rather than the target speed, so
		# a character keeps the momentum it jumped with and steers within it.
		rate = profile.air_acceleration * profile.air_control
	elif direction == Vector3.ZERO:
		rate = profile.deceleration
	else:
		rate = profile.acceleration

	return current.move_toward(target, rate * delta)


## Vertical velocity after one step of gravity, clamped to terminal velocity.
static func solve_vertical_velocity(
	velocity: Vector3, profile: MovementProfile, on_floor: bool, delta: float
) -> float:
	if profile == null or delta <= 0.0:
		return velocity.y
	if on_floor and velocity.y <= 0.0:
		# A small downward bias keeps a character pinned to slopes and ramps.
		# Zero here makes it skip on every seam in the floor.
		return -0.1
	return maxf(velocity.y - profile.gravity * delta, -absf(profile.max_fall_speed))


## Whether a jump may fire, given how long ago the ground was left and how long
## ago the button was pressed.
##
## [param time_since_grounded] and [param time_since_jump_pressed] are seconds;
## a negative value means "never". Together they implement coyote time and jump
## buffering, which are the difference between a jump that feels responsive and
## one that feels broken -- and which no amount of playtesting fixes if the
## rule is buried in an input handler.
static func can_jump(
	profile: MovementProfile,
	on_floor: bool,
	time_since_grounded: float,
	time_since_jump_pressed: float
) -> bool:
	if profile == null or not profile.can_jump or profile.jump_velocity <= 0.0:
		return false
	if time_since_jump_pressed < 0.0 or time_since_jump_pressed > profile.jump_buffer:
		return false
	if on_floor:
		return true
	return time_since_grounded >= 0.0 and time_since_grounded <= profile.coyote_time


## Velocity with the jump impulse applied. Replaces vertical velocity rather
## than adding to it, so jumping while already rising cannot compound.
static func apply_jump(velocity: Vector3, profile: MovementProfile) -> Vector3:
	if profile == null:
		return velocity
	return Vector3(velocity.x, profile.jump_velocity, velocity.z)


## The stance a mover ends up in, after the profile has vetoed what it cannot
## do. Returns [code][sprinting, crouching][/code].
##
## Wanting to sprint and being able to are different questions, and keeping the
## answer here means [MovementComponent] never has to re-derive it and the two
## can never disagree (rule 4).
static func resolve_stance(intent: MovementIntent, profile: MovementProfile) -> Array:
	if profile == null:
		return [false, false]
	var crouching := intent.wants_crouch and profile.can_crouch
	var sprinting := intent.wants_sprint and profile.can_sprint
	if sprinting and crouching and profile.sprint_blocked_while_crouching:
		sprinting = false
	return [sprinting, crouching]
