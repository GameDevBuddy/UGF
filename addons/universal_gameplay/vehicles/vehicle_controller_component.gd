class_name VehicleControllerComponent
extends FrameworkComponent
## Turns player input into driving commands. The vehicle's answer to
## [CharacterController], and deliberately its mirror image.
##
## It reads an [InputRouter] and calls [method VehicleComponent.set_throttle],
## [method VehicleComponent.set_brake], [method VehicleComponent.set_steering]
## and [method VehicleComponent.set_handbrake] — the same four methods
## [VehicleAIDriver] calls. Delete this component and the vehicle is traffic;
## add it back and it is the player's car. Nothing else in the entity changes,
## which is the whole of "player and AI drive through the same adapter".
##
## The movement actions are the on-foot ones by design: forward is forward and
## left is left whether you are walking or driving, so possession swaps the
## listener rather than the vocabulary (Implementation Plan 22, 24).

## Emitted when this controller takes or releases control.
signal control_changed(controlling: bool)

## The vehicle this drives. Wired at composition time (rule 20).
@export var vehicle: VehicleComponent

## Optional camera used while driving. Absent, the driver keeps their own.
@export var camera: CameraAdapter

## Input context pushed while driving. Takes precedence over the seat's; blank
## falls back to the standard vehicle-driver context.
@export var context_override: InputContext

## Forward mouse motion to the camera while driving.
@export var mouse_look: bool = true

var _router: InputRouter = null
var _input_context: InputContext = null
var _controlling: bool = false


func _ready() -> void:
	# Recomputed rather than disabled: a binder above this node may already
	# have initialised it (see MovementComponent for the full note).
	_set_ticking(_controlling)


func initialize(context: EntityContext) -> void:
	super(context)
	# An injected router wins: split-screen hands each controller its own, and
	# resolving over the top of one would put both players back on the same
	# router.
	if _router == null:
		_router = _resolve_router()
	if vehicle == null:
		vehicle = _find(VehicleComponent) as VehicleComponent
	# Never while driving. Replacing the context object mid-control strands the
	# instance already on the router's stack: release removes by instance, so
	# it would take the new one, miss, and leave the old one pushed forever.
	if not _controlling:
		_input_context = _resolve_input_context()


func _exit_tree() -> void:
	if _controlling:
		release_control()


# --- Possession -----------------------------------------------------------

## Takes control: pushes the driving context and starts reading input.
func take_control() -> FrameworkResult:
	if _controlling:
		return FrameworkResult.fail(
			&"driver.already_controlling", "This controller already has control."
		)
	if vehicle == null:
		return FrameworkResult.fail(
			&"driver.no_vehicle", "VehicleControllerComponent has no vehicle to drive."
		)
	if _router == null:
		_router = _resolve_router()
	if _router == null:
		return FrameworkResult.fail(
			&"driver.no_input_router",
			"No input service is available, so there is nothing to take control from."
		)

	if _input_context == null:
		_input_context = _resolve_input_context()
	var pushed := _router.push_context(_input_context)
	if pushed.is_err():
		return pushed

	_controlling = true
	_set_ticking(true)
	if camera != null:
		camera.make_current()
	control_changed.emit(true)
	return FrameworkResult.ok(self)


## Releases control and lets go of every pedal.
##
## The release matters for the same reason it does on foot: without it a
## vehicle handed over mid-corner keeps the steering it was given, because the
## last command it received is still set.
func release_control() -> FrameworkResult:
	if not _controlling:
		return FrameworkResult.fail(
			&"driver.not_controlling", "This controller does not have control."
		)
	_controlling = false
	_set_ticking(false)
	if _router != null and _input_context != null:
		# By instance, not by id: two players both driving push contexts with
		# the same id, and removing by id would take whichever pushed last.
		_router.remove_context_instance(_input_context)
	if vehicle != null:
		vehicle.release_controls()
	control_changed.emit(false)
	return FrameworkResult.ok(self)


func is_controlling() -> bool:
	return _controlling


func set_router(router: InputRouter) -> void:
	_router = router


func get_router() -> InputRouter:
	return _router


func get_input_context() -> InputContext:
	return _input_context


# --- Driving --------------------------------------------------------------

func _process(delta: float) -> void:
	drive(delta)


## Reads input once and issues the resulting commands.
##
## Public and side-effect-free beyond the commands it issues, so a test can
## step it deterministically without a frame.
func drive(delta: float) -> void:
	if not _controlling or _router == null or vehicle == null:
		return

	if _router.is_control_suppressed():
		# A menu or a cutscene is up. Let go rather than leaving the car
		# holding the last throttle it saw.
		vehicle.release_controls()
		return

	# Forward/back is the throttle and left/right is the steering, read from
	# the same semantic axes a character walks with.
	#
	# The y is negated. get_move_vector() returns forward as negative y,
	# matching Godot's screen-space convention so the value drops into a camera
	# basis without a sign flip -- but a throttle is not a basis, and taking it
	# raw makes pressing forward reverse the car.
	var move := _router.get_move_vector()
	vehicle.set_throttle(-move.y)
	vehicle.set_steering(move.x)
	vehicle.set_brake(1.0 if _router.is_pressed(GameplayNames.ACTION_CROUCH) else 0.0)
	vehicle.set_handbrake(_router.is_pressed(GameplayNames.ACTION_JUMP))

	if camera != null:
		camera.tick(delta)


## Applies look input to the camera, the way [CharacterController] does.
func apply_look(look: Vector2) -> void:
	if _controlling and mouse_look and camera != null:
		camera.add_look(look)


# --- Internals ------------------------------------------------------------

func _set_ticking(active: bool) -> void:
	set_process(active)


func _resolve_input_context() -> InputContext:
	if context_override != null:
		return context_override
	return InputContexts.vehicle_driver()


func _resolve_router() -> InputRouter:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_INPUT) as InputRouter


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
