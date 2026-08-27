class_name CameraSolver
extends RefCounted
## Pure maths for look input, pitch clamping and boom placement.
##
## Static and node-free for the same reason [MovementSolver] is: "does looking
## all the way down stop at the limit?" and "does inverting Y invert Y?" should
## be unit tests, not something a human verifies by dragging a mouse (rule 33).


## Yaw and pitch after applying look input, with pitch clamped to the profile.
##
## Returns [code][yaw, pitch][/code] in radians. Yaw is deliberately not
## wrapped: a caller that wants it wrapped can do so, and wrapping here would
## make a continuous spin read as a discontinuity to anything watching.
static func apply_look(
	yaw: float, pitch: float, look: Vector2, profile: CameraProfile
) -> Array:
	if profile == null:
		return [yaw, pitch]
	var vertical := look.y * (1.0 if profile.invert_y else -1.0)
	var new_yaw := yaw - look.x * profile.sensitivity
	var new_pitch := clampf(
		pitch + vertical * profile.sensitivity,
		profile.get_pitch_min(),
		profile.get_pitch_max()
	)
	return [new_yaw, new_pitch]


## Camera offset from the pitch pivot, in that pivot's local space.
##
## Deliberately independent of pitch. The pivot is already rotated by pitch, so
## swinging the boom here as well would apply the rotation twice -- the camera
## would rise at double the rate the view tilted, and looking down would put it
## somewhere behind the character's head. The boom is a fixed arm; the pivot
## does the swinging.
##
## First person returns the shoulder offset alone: the camera sits at the pivot.
static func solve_camera_offset(profile: CameraProfile) -> Vector3:
	if profile == null:
		return Vector3.ZERO
	if profile.is_first_person():
		return Vector3(profile.shoulder_offset, 0.0, 0.0)
	return Vector3(profile.shoulder_offset, 0.0, profile.boom_length)


## Where the pivot sits relative to the entity origin.
static func solve_pivot_offset(profile: CameraProfile) -> Vector3:
	if profile == null:
		return Vector3.ZERO
	return Vector3(0.0, profile.pivot_height, 0.0)


## FOV after one step of blending toward the sprint or base value.
static func solve_fov(
	current_fov: float, sprinting: bool, profile: CameraProfile, delta: float
) -> float:
	if profile == null:
		return current_fov
	var target := profile.sprint_fov if sprinting else profile.fov
	if profile.fov_blend_speed <= 0.0 or delta <= 0.0:
		return target
	return move_toward(current_fov, target, profile.fov_blend_speed * delta)


## The horizontal basis a camera-relative movement vector should be built from.
##
## Yaw only: pitch must not tilt movement, or looking at the sky walks the
## character backwards.
static func get_movement_basis(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw)
