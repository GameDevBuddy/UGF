class_name CameraAdapter
extends FrameworkComponent
## Drives an entity's camera rig from a [CameraProfile].
##
## An adapter, not an owner (rule 21). It reads look input and the mover's
## stance, and writes yaw, pitch and FOV to nodes it was handed. It never
## decides anything about gameplay, and nothing gameplay-side reads the camera
## back -- movement asks it for a basis, which is a query, not a dependency.
##
## The nodes are optional throughout. A camera-less entity -- a server-side
## character, an AI with nobody watching, a headless test -- still tracks yaw
## and pitch, so [method get_movement_basis] answers correctly for an entity
## that has no camera at all. That is what lets one character scene serve the
## player and every NPC in the game without a second variant.

## Emitted when the view angles change, for anything that needs to follow the
## look direction without polling.
signal look_changed(yaw: float, pitch: float)

## Camera configuration. Takes precedence over the definition's profile.
@export var profile_override: CameraProfile

## Node rotated around Y. Usually a child of the entity root.
@export var yaw_pivot: Node3D

## Node rotated around X, usually a child of [member yaw_pivot]. Falls back to
## the yaw pivot when unset, which is the first-person case.
@export var pitch_pivot: Node3D

## The camera itself, moved along the boom and blended for FOV.
@export var camera: Camera3D

## Optional mover, read for the sprint FOV cue. One-way: this component never
## commands movement.
@export var movement: MovementComponent

var _profile: CameraProfile = null
var _yaw: float = 0.0
var _pitch: float = 0.0
var _fov: float = 0.0


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if _profile != null:
		_fov = _profile.fov
	if camera != null and _profile != null:
		camera.fov = _profile.fov
	apply()


# --- Commands -------------------------------------------------------------

## Applies look input. [param look] is a raw delta -- mouse motion, or a stick
## axis scaled by frame time -- and the profile turns it into radians.
func add_look(look: Vector2) -> void:
	if _profile == null:
		return
	var angles := CameraSolver.apply_look(_yaw, _pitch, look, _profile)
	set_look(angles[0], angles[1])


## Sets absolute view angles in radians, clamping pitch to the profile.
func set_look(yaw: float, pitch: float) -> void:
	var clamped_pitch := pitch
	if _profile != null:
		clamped_pitch = clampf(pitch, _profile.get_pitch_min(), _profile.get_pitch_max())
	if is_equal_approx(yaw, _yaw) and is_equal_approx(clamped_pitch, _pitch):
		return
	_yaw = yaw
	_pitch = clamped_pitch
	apply()
	look_changed.emit(_yaw, _pitch)


## Writes the current angles to whichever rig nodes exist. Safe to call with
## none of them set.
func apply() -> void:
	if yaw_pivot != null:
		yaw_pivot.rotation.y = _yaw
	# With no separate pitch pivot the yaw node carries both, which is the
	# first-person rig: one node, two axes.
	var pitch_node := pitch_pivot if pitch_pivot != null else yaw_pivot
	if pitch_node != null:
		pitch_node.rotation.x = _pitch
	if camera != null and _profile != null:
		camera.position = CameraSolver.solve_camera_offset(_profile)


## Advances the FOV blend. Called by whatever owns the frame; there is no
## [method Node._process] here, because a camera with no FOV cue configured
## should cost nothing to have (rule 26).
func tick(delta: float) -> void:
	if _profile == null or camera == null:
		return
	var sprinting := movement != null and movement.is_sprinting()
	_fov = CameraSolver.solve_fov(_fov, sprinting, _profile, delta)
	camera.fov = _fov


## Makes this entity's camera the one the viewport renders from.
##
## Possession decides this, not the scene: every NPC in a game is built from
## the same character scene, and whichever spawned first would otherwise own
## the viewport. Godot makes a camera current automatically when no other one
## is, so the framework never marks one current on spawn -- it waits to be
## told (rule 21: presentation does as it is told).
func make_current() -> bool:
	if camera == null or not camera.is_inside_tree():
		return false
	camera.make_current()
	return true


func is_current() -> bool:
	return camera != null and camera.current


# --- Queries --------------------------------------------------------------

func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


func get_fov() -> float:
	return _fov


func get_profile() -> CameraProfile:
	return _profile


## The basis camera-relative movement should be built from: yaw only.
##
## This is the one thing gameplay asks a camera for, and it is a pure query.
## Movement calling this does not make the camera authoritative over movement
## (rule 21) -- it makes "forward means where I am looking" expressible without
## the character scene hard-coding a camera.
func get_movement_basis() -> Basis:
	return CameraSolver.get_movement_basis(_yaw)


# --- Internals ------------------------------------------------------------

## Read by property name rather than by casting to a character definition, so
## a vehicle or a turret with its own definition type can reuse this adapter
## without Camera importing another module's types (rule 9).
func _resolve_profile() -> CameraProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "camera" in definition:
		var candidate: Variant = definition.get("camera")
		if candidate is CameraProfile:
			return candidate as CameraProfile
	return null
