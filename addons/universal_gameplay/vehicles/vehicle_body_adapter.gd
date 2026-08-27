class_name VehicleBodyAdapter
extends VehicleControllerAdapter
## The adapter that moves a real body. The only file in Vehicles that touches
## the physics server.
##
## Kinematic rather than a [VehicleBody3D] wrapper, deliberately. A
## [VehicleBody3D] is a fine choice for a project and a poor one for a
## framework default: it needs wheels, a mass, a suspension setup and a
## collision shape before it does anything at all, and none of that is
## something the framework can pick. This drives a [CharacterBody3D] from the
## handling profile, which works with a capsule and a box and is what most
## arcade driving actually wants.
##
## [b]A project that wants [VehicleBody3D] writes one more file like this one
## and changes nothing else.[/b] That is the point of the seam: it is the
## single deletable file between the framework and one concrete motion
## implementation, and everything upstream of it — seats, fuel, damage, AI
## driving — is unaware which is installed (rule 10, Implementation Plan 22).

## Gravity applied while airborne, metres per second squared. Positive is
## downwards.
@export_range(0.0, 100.0, 0.1, "or_greater") var gravity: float = 24.0

## Vertical speed is kept between steps so a vehicle that leaves the ground
## comes back down rather than gliding.
var _vertical: float = 0.0


func apply_motion(delta: float) -> void:
	var character := body as CharacterBody3D
	if character == null:
		# A body that is not a CharacterBody3D is not an error: the base class
		# integration is still correct and a project may be reading it to drive
		# something else. Rotating what we were given is still useful.
		_rotate_only()
		return
	if not character.is_inside_tree():
		return

	if character.is_on_floor():
		_vertical = 0.0
	else:
		_vertical -= gravity * delta

	character.rotation.y = get_heading()
	character.velocity = get_velocity()
	character.velocity.y = _vertical
	character.move_and_slide()

	# The body is the authority on what actually happened. Driving into a wall
	# must slow the vehicle down, and a speed that ignores the collision would
	# leave it grinding along at full throttle with the world refusing to move.
	var travelled := Vector3(character.velocity.x, 0.0, character.velocity.z)
	var forward := Vector3(sin(get_heading()), 0.0, cos(get_heading()))
	set_speed(travelled.dot(forward))
	_vertical = character.velocity.y


func get_vertical_speed() -> float:
	return _vertical


func _rotate_only() -> void:
	if body != null and body.is_inside_tree():
		body.rotation.y = get_heading()
