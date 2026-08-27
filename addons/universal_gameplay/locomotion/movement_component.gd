class_name MovementComponent
extends FrameworkComponent
## The capability of moving. Owns velocity and stance for one entity.
##
## Every mover in the framework goes through this one API. A player's
## controller calls [method set_move_direction] and [method request_jump]; so
## does a guard's AI brain, so does a scripted cutscene, so would a replay.
## None of them is privileged and none of them is detectable from in here,
## which is what rule 14 means in practice -- and it is why an AI written
## against this in M7 needs no cooperation from M2 to work.
##
## [b]The maths is not here.[/b] It is in [MovementSolver], which is static and
## takes no node. What is left in this component is the part that genuinely
## needs a node: reading the body's floor state, remembering how long ago the
## ground was left, and writing the answer back. That split is what keeps
## "does sprinting go faster?" a unit test rather than a playtest (rule 33).
##
## The component works with no body attached, integrating velocity on its own.
## That is not a test affordance -- it is how a networked client predicts, and
## how an entity simulated outside the physics world keeps moving.

## Emitted when the effective stance changes. Both flags are post-veto: a
## profile that cannot sprint never reports sprinting (rule 4).
signal stance_changed(sprinting: bool, crouching: bool)
## Emitted on the frame a jump actually fires, not when one is requested.
signal jumped
## Emitted on the frame the entity returns to the ground.
signal landed(fall_speed: float)
## Emitted when the entity starts or stops moving under its own power.
signal movement_changed(moving: bool)

## Movement configuration. Takes precedence over the definition's profile,
## which is how one authored entity is made heavier than its definition
## without a second definition.
@export var profile_override: MovementProfile

## Body this component drives. Defaults to the entity root when that root is a
## [CharacterBody3D]. Left null with no such root, the component simulates
## velocity without moving anything.
@export var body: CharacterBody3D

## Optional [SemanticState] to mirror stance onto, wired at composition time
## rather than discovered by walking the tree (rules 20 to 22).
##
## The mirror is one-way and advisory. This component owns the stance; the tags
## only advertise it so an animation or AI layer can read it without holding a
## reference here (rule 4).
@export var semantic_state: SemanticState

## Whether to drive the body from [method Node._physics_process]. Turn it off
## when something else owns the tick -- a networked authority, or a test.
@export var auto_tick: bool = true

var _velocity: Vector3 = Vector3.ZERO
var _intent: MovementIntent = MovementIntent.new()
var _profile: MovementProfile = null
var _sprinting: bool = false
var _crouching: bool = false
var _moving: bool = false
var _on_floor: bool = true
var _time_since_grounded: float = 0.0
var _time_since_jump_pressed: float = -1.0
## Height above the ground plane, used only when there is no body to ask.
var _virtual_height: float = 0.0


func _ready() -> void:
	# Rule 26: nothing ticks by default. Enabled by initialisation, or by an
	# explicit tick from whatever owns the frame.
	#
	# Recomputed rather than blindly disabled, because a sibling
	# [DefinitionBinder] may already have initialised this component: Godot
	# readies children in tree order, so a binder sitting above this node in
	# the scene binds it before this runs. A bare set_physics_process(false)
	# here would silently switch the character off, and only for scenes whose
	# node order happened to put the binder first.
	set_physics_process(is_initialized() and auto_tick and body != null)


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if body == null:
		body = get_entity() as CharacterBody3D
	if body != null:
		_on_floor = body.is_on_floor()
	set_physics_process(auto_tick and body != null)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Commands -------------------------------------------------------------
#
# The API an AI brain, a player controller and a cutscene all use. Nothing
# below can tell which one is calling.

## Sets the desired world-space direction. Length above 1 is normalised.
func set_move_direction(direction: Vector3) -> void:
	_intent.direction = direction


## Sets direction from a 2D input vector relative to [param basis].
##
## The convenience matters: without it every caller re-derives forward from a
## basis, and half of them get the sign wrong.
func set_move_input(input: Vector2, basis: Basis = Basis.IDENTITY) -> void:
	_intent.direction = MovementIntent.from_input(input, basis).direction


## Replaces the whole intent in one call. Used by anything that computes intent
## wholesale -- an AI brain producing a navigation step, a replay reading a
## recorded frame.
func set_intent(intent: MovementIntent) -> void:
	if intent == null:
		return
	_intent.direction = intent.direction
	_intent.wants_sprint = intent.wants_sprint
	_intent.wants_crouch = intent.wants_crouch
	if intent.jump_requested:
		request_jump()


func set_sprinting(sprinting: bool) -> void:
	_intent.wants_sprint = sprinting


func set_crouching(crouching: bool) -> void:
	_intent.wants_crouch = crouching


## Asks for a jump. Whether one happens is decided on the next tick, by the
## profile and the solver -- so a press slightly before landing is honoured
## through the jump buffer rather than dropped.
func request_jump() -> void:
	_time_since_jump_pressed = 0.0


## Clears movement intent. Does not zero velocity: a character that stops
## steering should decelerate, not stop dead.
func stop() -> void:
	_intent.direction = Vector3.ZERO
	_intent.wants_sprint = false


## Zeroes velocity outright. For teleports, cutscene handoff and respawns,
## where carrying momentum across would be wrong.
func halt() -> void:
	_velocity = Vector3.ZERO
	_virtual_height = 0.0
	_time_since_jump_pressed = -1.0
	stop()
	if body != null:
		body.velocity = Vector3.ZERO
	_set_moving(false)


# --- Tick -----------------------------------------------------------------

## Advances movement by [param delta] seconds.
##
## Public so something other than the physics frame can own the timing: a
## networked authority resimulating, a test stepping deterministically, a
## paused world advancing one frame. The body is optional throughout.
func tick(delta: float) -> void:
	if _profile == null:
		_profile = _resolve_profile()
	if _profile == null or delta <= 0.0:
		return

	if body != null:
		_velocity = body.velocity
		_on_floor = body.is_on_floor()

	if _on_floor:
		_time_since_grounded = 0.0
	else:
		_time_since_grounded += delta
	if _time_since_jump_pressed >= 0.0:
		_time_since_jump_pressed += delta

	var stance := MovementSolver.resolve_stance(_intent, _profile)
	_set_stance(stance[0], stance[1])

	var planar := MovementSolver.solve_planar_velocity(
		_velocity, _intent, _profile, _on_floor, delta
	)
	_velocity.x = planar.x
	_velocity.z = planar.z
	_velocity.y = MovementSolver.solve_vertical_velocity(
		_velocity, _profile, _on_floor, delta
	)

	if MovementSolver.can_jump(
		_profile, _on_floor, _time_since_grounded, _time_since_jump_pressed
	):
		_velocity = MovementSolver.apply_jump(_velocity, _profile)
		_time_since_jump_pressed = -1.0
		_time_since_grounded = _profile.coyote_time + 1.0
		_on_floor = false
		jumped.emit()
	elif _time_since_jump_pressed > _profile.jump_buffer:
		# The buffered press expired unfulfilled. Dropping it here rather than
		# letting it linger is what stops a jump firing seconds later.
		_time_since_jump_pressed = -1.0

	_set_moving(_intent.is_moving())

	var floor_before_move := _on_floor
	var impact_speed := maxf(-_velocity.y, 0.0)

	if body != null:
		body.velocity = _velocity
		body.move_and_slide()
		_velocity = body.velocity
		_set_floor_state(body.is_on_floor(), floor_before_move, impact_speed)
	else:
		_integrate_without_body(delta, floor_before_move, impact_speed)


## Advances a body-less entity against a ground plane at height zero.
##
## Not a test affordance. A networked client predicting movement, an entity
## simulated outside the physics world, and a headless authority all need
## movement to advance without a [CharacterBody3D] to ask. Keeping the fallback
## real means those cases share this component instead of reimplementing it.
func _integrate_without_body(
	delta: float, floor_before_move: bool, impact_speed: float
) -> void:
	_virtual_height = maxf(0.0, _virtual_height + _velocity.y * delta)
	var now_on_floor := is_zero_approx(_virtual_height)
	if now_on_floor and _velocity.y < 0.0:
		_velocity.y = 0.0
	_set_floor_state(now_on_floor, floor_before_move, impact_speed)


func _set_floor_state(
	now_on_floor: bool, floor_before_move: bool, impact_speed: float
) -> void:
	_on_floor = now_on_floor
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_AIRBORNE, not _on_floor)
	if now_on_floor and not floor_before_move:
		landed.emit(impact_speed)


# --- Queries --------------------------------------------------------------

func get_velocity() -> Vector3:
	return _velocity


func get_planar_speed() -> float:
	return Vector2(_velocity.x, _velocity.z).length()


## Current speed as a fraction of this profile's fastest ground speed, 0 to 1.
##
## The number an animation blend wants. Computed here because this component
## owns the speeds; an animation layer deriving it would be a second authority
## on the same fact (rule 4).
func get_speed_ratio() -> float:
	if _profile == null:
		return 0.0
	var top := maxf(
		_profile.walk_speed, _profile.sprint_speed if _profile.can_sprint else 0.0
	)
	if top <= 0.0:
		return 0.0
	return clampf(get_planar_speed() / top, 0.0, 1.0)


func is_sprinting() -> bool:
	return _sprinting


func is_crouching() -> bool:
	return _crouching


func is_moving() -> bool:
	return _moving


func is_on_floor() -> bool:
	return _on_floor


func is_airborne() -> bool:
	return not _on_floor


func get_profile() -> MovementProfile:
	return _profile


func get_intent() -> MovementIntent:
	return _intent


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves stance, not position.
##
## Position belongs to the entity record's transform, which [EntitySerializer]
## already owns; writing it here too would give one fact two owners and let a
## save disagree with itself (rule 4, rule 22).
func capture_state() -> Dictionary:
	return {
		"sprinting": _sprinting,
		"crouching": _crouching,
		"velocity": [_velocity.x, _velocity.y, _velocity.z],
	}


func restore_state(data: Dictionary) -> void:
	_intent.wants_sprint = bool(data.get("sprinting", false))
	_intent.wants_crouch = bool(data.get("crouching", false))
	var stance := MovementSolver.resolve_stance(_intent, _profile)
	_set_stance(stance[0], stance[1])
	var stored: Array = data.get("velocity", [])
	if stored.size() == 3:
		_velocity = Vector3(float(stored[0]), float(stored[1]), float(stored[2]))
		if body != null:
			body.velocity = _velocity


# --- Internals ------------------------------------------------------------

## Finds the profile: an authored override first, then the definition's.
##
## The definition is read by property name rather than by casting to
## [code]CharacterDefinition[/code] on purpose. Locomotion is a sibling of
## Character, and a sibling that imports another module's types to read one
## field is the hidden coupling rule 9 exists to prevent -- it would stop a
## vehicle, a turret or a drone reusing this component with its own definition
## type. Any definition offering a [MovementProfile] under [code]movement[/code]
## works here, and one offering nothing is a valid state, not an error.
func _resolve_profile() -> MovementProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "movement" in definition:
		var candidate: Variant = definition.get("movement")
		if candidate is MovementProfile:
			return candidate as MovementProfile
	return null


func _set_stance(sprinting: bool, crouching: bool) -> void:
	if sprinting == _sprinting and crouching == _crouching:
		return
	_sprinting = sprinting
	_crouching = crouching
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_SPRINTING, _sprinting)
		semantic_state.set_state(GameplayNames.STATE_CROUCHING, _crouching)
	stance_changed.emit(_sprinting, _crouching)


func _set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_MOVING, _moving)
	movement_changed.emit(_moving)
