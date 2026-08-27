class_name VehicleAIDriver
extends FrameworkComponent
## Drives a vehicle towards somewhere. The other half of the M13 exit gate.
##
## [b]It has no privileged access to anything.[/b] It calls exactly the four
## methods [VehicleControllerComponent] calls, on exactly the same
## [VehicleComponent], and it could not tell whether a player controller exists
## on the same entity. That is what "player and AI drive through the same
## adapter" means in practice, and it is the same relationship
## [AIControllerComponent] has with [MovementComponent] (rule 14, Implementation
## Plan 22).
##
## The steering is a pursuit controller and nothing more: face the target, open
## the throttle when pointed at it, brake when overshooting. Traffic laws,
## lane discipline and overtaking are a project's brain, not a framework
## default (rule 29).

## Emitted when the destination is reached.
signal arrived(destination: Vector3)
## Emitted when a destination is set or cleared.
signal destination_changed(destination: Vector3, has_destination: bool)

## The vehicle this drives. Found among this entity's own components when not
## wired.
@export var vehicle: VehicleComponent

## How close counts as arrived, in metres.
@export_range(0.1, 100.0, 0.1, "or_greater") var arrival_distance: float = 4.0

## How far off-heading the driver will still use full throttle, in degrees.
## Beyond it the throttle eases off so the vehicle can turn.
@export_range(1.0, 180.0, 1.0) var throttle_cone_degrees: float = 45.0

## Beyond this angle the driver slows right down to get the nose round. A car
## pointing away from where it is going should not be at full speed.
@export_range(1.0, 180.0, 1.0) var brake_cone_degrees: float = 110.0

## Speed the driver aims for, as a fraction of the vehicle's maximum. What a
## traffic agent turns down and a chase turns up.
@export_range(0.05, 1.0, 0.01) var cruise_fraction: float = 0.7

## Optional navigation, so an AI driver follows a road network when there is
## one and drives straight at the target when there is not. The same adapter
## the on-foot AI uses (rule 23).
@export var navigation: NavigationAdapter

## Whether to start the engine when given somewhere to go.
@export var auto_start: bool = true

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _active: bool = true


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _has_destination)


func initialize(context: EntityContext) -> void:
	super(context)
	if vehicle == null:
		vehicle = _find(VehicleComponent) as VehicleComponent
	if navigation == null:
		navigation = _find(NavigationAdapter) as NavigationAdapter
	set_physics_process(auto_tick and _has_destination)


func _physics_process(delta: float) -> void:
	drive(delta)


# --- Commands -------------------------------------------------------------

func drive_to(destination: Vector3) -> FrameworkResult:
	if vehicle == null:
		return FrameworkResult.fail(
			&"ai_driver.no_vehicle", "There is no vehicle to drive."
		)
	_destination = destination
	_has_destination = true
	if navigation != null:
		navigation.set_destination(destination)
	if auto_start and not vehicle.is_running():
		vehicle.start_engine()
	set_physics_process(auto_tick)
	destination_changed.emit(destination, true)
	return FrameworkResult.ok(destination)


## Gives up on the destination and comes to a stop.
func stop() -> void:
	_has_destination = false
	set_physics_process(false)
	if vehicle != null:
		vehicle.set_throttle(0.0)
		vehicle.set_steering(0.0)
		vehicle.set_brake(1.0)
	destination_changed.emit(_destination, false)


## Switched off while a player is driving and back on when they let go. The
## handoff is the whole of possession from the AI's side.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if not active and vehicle != null:
		vehicle.release_controls()
	set_physics_process(auto_tick and _active and _has_destination)


func is_active() -> bool:
	return _active


func has_destination() -> bool:
	return _has_destination


func get_destination() -> Vector3:
	return _destination


func get_distance_to_destination() -> float:
	var here := _position()
	if not _has_destination:
		return 0.0
	return Vector2(here.x, here.z).distance_to(Vector2(_destination.x, _destination.z))


func has_arrived() -> bool:
	return _has_destination and get_distance_to_destination() <= arrival_distance


# --- Driving --------------------------------------------------------------

## Issues one step of commands. Public and steppable so a test can drive a
## whole journey without a frame (rule 33).
func drive(delta: float) -> void:
	if not _active or vehicle == null or not _has_destination or delta <= 0.0:
		return

	if has_arrived():
		_has_destination = false
		vehicle.set_throttle(0.0)
		vehicle.set_steering(0.0)
		vehicle.set_brake(1.0)
		set_physics_process(false)
		arrived.emit(_destination)
		return

	if navigation != null:
		navigation.tick(delta)
	var target := _next_point()
	var error := _heading_error_to(target)
	var magnitude := absf(error)

	# Steering is the sign of the error, at a strength proportional to it. Full
	# lock for anything past the throttle cone; proportional inside it, so the
	# vehicle stops sawing at the wheel as it lines up.
	var cone := deg_to_rad(throttle_cone_degrees)
	vehicle.set_steering(signf(error) * clampf(magnitude / cone, 0.0, 1.0))

	if magnitude >= deg_to_rad(brake_cone_degrees):
		# Pointing away from where we are going. Slow down and turn, rather
		# than driving further away at speed.
		vehicle.set_throttle(0.0)
		vehicle.set_brake(1.0)
		return

	vehicle.set_brake(0.0)
	# Off-heading eases the throttle rather than closing it, so a car taking a
	# bend keeps rolling.
	var ease := 1.0 - clampf(magnitude / deg_to_rad(brake_cone_degrees), 0.0, 1.0)
	var demand := cruise_fraction * maxf(ease, 0.2)
	# Cruise is a target speed, not a pedal position: at speed the throttle
	# comes off, which is what stops an AI driver oscillating between flat out
	# and flat stop.
	if vehicle.get_speed_fraction() >= cruise_fraction and vehicle.get_speed() > 0.0:
		demand = 0.0
	vehicle.set_throttle(demand)


# --- Internals ------------------------------------------------------------

## Where to aim right now. With a navigator that is the next point on the
## path, projected a little ahead so the driver steers towards the road rather
## than at its own bumper; without one it is the destination itself, and the
## vehicle drives straight at it. A missing navigation module is a valid
## configuration, not an error (rule 31).
func _next_point() -> Vector3:
	if navigation != null:
		var direction := navigation.get_desired_direction()
		if not direction.is_zero_approx():
			return _position() + direction * arrival_distance
	return _destination


func _position() -> Vector3:
	var entity := get_entity() as Node3D
	if entity == null or not entity.is_inside_tree():
		return Vector3.ZERO
	return entity.global_position


## Signed angle between where the vehicle is pointed and where it wants to go,
## wrapped to -PI..PI so turning right through north is a small error and not
## nearly a full circle.
func _heading_error_to(target: Vector3) -> float:
	var here := _position()
	var to_target := Vector3(target.x - here.x, 0.0, target.z - here.z)
	if to_target.length_squared() < 0.0001:
		return 0.0
	var wanted := atan2(to_target.x, to_target.z)
	var facing := vehicle.adapter.get_heading() if vehicle.adapter != null else 0.0
	return wrapf(wanted - facing, -PI, PI)


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
