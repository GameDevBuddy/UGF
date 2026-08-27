class_name AnimationAdapter
extends FrameworkComponent
## Writes movement state into an [AnimationTree], and nothing else.
##
## This is rule 21 as a class. Presentation observes authority; it never
## becomes one. The adapter subscribes to [MovementComponent]'s signals and
## reads its public queries, and there is deliberately no path in this file
## that calls back into movement, changes stance, or decides anything a save
## file would care about. An animation that fails to play is a cosmetic bug,
## and that is the only kind of bug this file can cause.
##
## [b]It works with no [AnimationTree].[/b] Every write goes through
## [method _write], which records the value whether or not a tree is attached,
## so [method get_applied] can be asserted against in a headless test. A
## framework whose presentation layer can only be verified by looking at it is
## one whose presentation layer is never verified.

## Emitted after each apply, carrying the parameters written this frame. The
## hook a debug panel uses to show what the tree is being told.
signal parameters_applied(parameters: Dictionary)

## Animation configuration. Takes precedence over the definition's profile.
@export var profile_override: AnimationProfile

## The tree to drive. Null is a supported state, not a misconfiguration.
@export var animation_tree: AnimationTree

## The mover to observe. Wired at composition time rather than found by
## walking the tree (rules 20 to 22).
@export var movement: MovementComponent

## Drive from [method Node._process]. Off when something else owns the frame.
@export var auto_tick: bool = true

var _profile: AnimationProfile = null
var _applied: Dictionary[String, Variant] = {}
var _blended_speed: float = 0.0


func _ready() -> void:
	# Recomputed rather than disabled: a binder above this node in the scene
	# has already initialised it by the time this runs (see MovementComponent
	# for the full note).
	set_process(is_initialized() and auto_tick and _profile != null and movement != null)


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	_connect_movement()
	# Nothing to observe, or nowhere to write it: cost nothing (rule 26).
	set_process(auto_tick and _profile != null and movement != null)
	apply(0.0)


func _process(delta: float) -> void:
	apply(delta)


func _exit_tree() -> void:
	_disconnect_movement()


## Samples the mover and writes every configured parameter.
##
## Public so a networked or paused world can drive presentation on its own
## schedule. Safe to call with no profile, no tree and no mover.
func apply(delta: float = 0.0) -> void:
	if _profile == null or movement == null:
		return

	var ratio := movement.get_speed_ratio()
	if _profile.speed_blend_rate > 0.0 and delta > 0.0:
		_blended_speed = move_toward(
			_blended_speed, ratio, _profile.speed_blend_rate * delta
		)
	else:
		_blended_speed = ratio

	_write(_profile.speed_parameter, _blended_speed)
	_write(_profile.speed_metres_parameter, movement.get_planar_speed())
	_write(_profile.airborne_parameter, movement.is_airborne())
	_write(_profile.crouch_parameter, movement.is_crouching())
	_write(_profile.sprint_parameter, movement.is_sprinting())
	_write(_profile.moving_parameter, movement.is_moving())

	parameters_applied.emit(_applied.duplicate())


## Values written on the last apply, keyed by parameter path.
##
## The whole state of this component is here; it holds no gameplay fact of its
## own, which is what makes it safe for it to be wrong.
func get_applied() -> Dictionary:
	return _applied.duplicate()


func get_applied_value(parameter: String) -> Variant:
	return _applied.get(parameter)


func get_profile() -> AnimationProfile:
	return _profile


func has_animation_tree() -> bool:
	return animation_tree != null


# --- Observers ------------------------------------------------------------

func _on_jumped() -> void:
	_fire_one_shot(_profile.jump_request_parameter)


func _on_landed(fall_speed: float) -> void:
	if fall_speed < _profile.land_request_min_speed:
		return
	_fire_one_shot(_profile.land_request_parameter)


func _on_stance_changed(_sprinting: bool, _crouching: bool) -> void:
	# Stance changes are picked up by the next apply. Reacting immediately
	# would double-write on a frame where both happen, for no visible gain.
	pass


# --- Internals ------------------------------------------------------------

func _connect_movement() -> void:
	if movement == null or _profile == null:
		return
	if not movement.jumped.is_connected(_on_jumped):
		movement.jumped.connect(_on_jumped)
	if not movement.landed.is_connected(_on_landed):
		movement.landed.connect(_on_landed)
	if not movement.stance_changed.is_connected(_on_stance_changed):
		movement.stance_changed.connect(_on_stance_changed)


func _disconnect_movement() -> void:
	if movement == null:
		return
	if movement.jumped.is_connected(_on_jumped):
		movement.jumped.disconnect(_on_jumped)
	if movement.landed.is_connected(_on_landed):
		movement.landed.disconnect(_on_landed)
	if movement.stance_changed.is_connected(_on_stance_changed):
		movement.stance_changed.disconnect(_on_stance_changed)


func _fire_one_shot(parameter: String) -> void:
	if parameter.is_empty():
		return
	_applied[parameter] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	if animation_tree != null:
		animation_tree.set(parameter, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	parameters_applied.emit(_applied.duplicate())


## Records the value, and forwards it to the tree when there is one.
##
## Recording unconditionally is what makes this component testable without an
## [AnimationTree], a rig, or a rendering context.
func _write(parameter: String, value: Variant) -> void:
	if parameter.is_empty():
		return
	_applied[parameter] = value
	if animation_tree != null:
		animation_tree.set(parameter, value)


## Read by property name rather than by casting to a character definition, so
## a vehicle or a creature with its own definition type reuses this adapter
## without Animation importing another module's types (rule 9).
func _resolve_profile() -> AnimationProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "animation" in definition:
		var candidate: Variant = definition.get("animation")
		if candidate is AnimationProfile:
			return candidate as AnimationProfile
	return null
