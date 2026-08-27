class_name VehicleComponent
extends FrameworkComponent
## The vehicle itself: engine, clock, and the one command API everything drives
## through.
##
## [b]This is where the exit gate is met.[/b] A player controller, an AI driver
## and a scripted sequence all call [method set_throttle], [method set_brake],
## [method set_steering] and [method set_handbrake] — the same four methods,
## with no privileged path and nothing an AI would have to work around
## (rule 14). Which of them is driving is a question only [SeatComponent]
## answers.
##
## It owns the clock so that stepping is one call in one place (rule 4): the
## adapter integrates, fuel is spent, and a stalled engine coasts to a stop.

## Emitted when the engine starts or stops.
signal engine_changed(running: bool)
## Emitted when the engine stops for a reason worth reporting: out of fuel,
## destroyed. Presentation and missions both want the reason, not just the fact.
signal engine_stalled(reason: StringName)
## Emitted when the vehicle is wrecked.
signal destroyed

## What this vehicle is. Takes precedence over the definition's.
@export var vehicle_override: VehicleDefinition

## Where commands go. Found among this entity's own components when not wired,
## and created as a bare [VehicleControllerAdapter] when there is none — a
## vehicle with no physics still integrates, which is what a headless server
## and a test both need.
@export var adapter: VehicleControllerAdapter

## The tank. Absent, the vehicle never runs out (rule 31).
@export var fuel: FuelComponent

## Who is aboard. Absent, the vehicle can still be driven by anything holding a
## reference to it — an AI, a script, a remote client.
@export var seats: SeatComponent

## Health, so a wreck is the generic death of a generic entity.
@export var health: HealthComponent

## States mirrored from the engine and motion.
@export var semantic_state: SemanticState

## Tick from [method Node._physics_process]. Off when something else owns time
## — a replay, a network client, a test.
@export var auto_tick: bool = true

## Whether the engine starts when a driver sits down. Off is a vehicle that
## needs the key turned, which is what a hotwire interaction is for.
@export var start_on_driver: bool = true

## Push [member VehicleDefinition.maximum_health] onto the health component at
## initialisation.
##
## [HealthComponent] reads its maximum from its own export or from a stat, and
## has no idea what a vehicle definition is -- rightly, because it serves
## characters, crates and doors too. Something has to carry "this model of car
## takes 600 damage" from the content to the component, and the vehicle is the
## only thing that knows both. Off leaves the health component's own number
## alone, which is what a hand-tuned unique vehicle wants.
@export var apply_definition_health: bool = true

var _definition: VehicleDefinition = null
var _running: bool = false


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	_definition = _resolve_definition()
	if adapter == null:
		adapter = _find(VehicleControllerAdapter) as VehicleControllerAdapter
	if adapter == null:
		adapter = VehicleControllerAdapter.new()
		adapter.name = "VehicleControllerAdapter"
		add_child(adapter)
		adapter.initialize(context)
	if adapter.handling == null:
		adapter.handling = get_handling()

	if fuel == null:
		fuel = _find(FuelComponent) as FuelComponent
	if seats == null:
		seats = _find(SeatComponent) as SeatComponent
	if health == null:
		health = _find(HealthComponent) as HealthComponent
	_apply_definition_health()
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState

	if seats != null and not seats.occupant_entered.is_connected(_on_occupant_entered):
		seats.occupant_entered.connect(_on_occupant_entered)
		seats.occupant_exited.connect(_on_occupant_exited)
	if health != null and not health.died.is_connected(_on_died):
		health.died.connect(_on_died)
	set_physics_process(auto_tick)


func _exit_tree() -> void:
	if seats != null and seats.occupant_entered.is_connected(_on_occupant_entered):
		seats.occupant_entered.disconnect(_on_occupant_entered)
		seats.occupant_exited.disconnect(_on_occupant_exited)
	if health != null and health.died.is_connected(_on_died):
		health.died.disconnect(_on_died)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

func get_vehicle() -> VehicleDefinition:
	return _definition


func get_handling() -> HandlingProfile:
	return _definition.handling if _definition != null else null


func is_running() -> bool:
	return _running


func get_speed() -> float:
	return adapter.get_speed() if adapter != null else 0.0


func get_speed_fraction() -> float:
	return adapter.get_speed_fraction() if adapter != null else 0.0


func get_motion_state() -> VehicleControllerAdapter.MotionState:
	if adapter == null:
		return VehicleControllerAdapter.MotionState.STOPPED
	return adapter.get_motion_state()


func is_moving() -> bool:
	return adapter != null and adapter.is_moving()


func get_driver() -> Node:
	return seats.get_driver() if seats != null else null


func is_wrecked() -> bool:
	return health != null and health.is_dead()


func has_vehicle_tag(tag: StringName) -> bool:
	return _definition != null and _definition.has_vehicle_tag(tag)


# --- The command API ------------------------------------------------------
#
# Four methods. Everything that drives -- player, AI, script, network -- calls
# exactly these, and none of them can tell which of the others exist.

func set_throttle(value: float) -> void:
	if adapter == null:
		return
	# A dead engine has no throttle. Coasting is what a stalled car does, and
	# letting the pedal work anyway is how "out of fuel" becomes cosmetic.
	adapter.set_throttle(value if _running else 0.0)


func set_brake(value: float) -> void:
	# Brakes work with the engine off. They are the one control that must.
	if adapter != null:
		adapter.set_brake(value)


func set_steering(value: float) -> void:
	if adapter != null:
		adapter.set_steering(value)


func set_handbrake(active: bool) -> void:
	if adapter != null:
		adapter.set_handbrake(active)


## Releases every control. What a driver getting out calls, so a vehicle does
## not drive off holding the throttle they were pressing.
func release_controls() -> void:
	if adapter != null:
		adapter.release_controls()


# --- Engine ---------------------------------------------------------------

func start_engine() -> FrameworkResult:
	if _running:
		return FrameworkResult.fail(&"vehicle.already_running", "It is already running.")
	if is_wrecked():
		return FrameworkResult.fail(&"vehicle.wrecked", "It is wrecked.")
	if fuel != null and fuel.is_empty():
		return FrameworkResult.fail(&"vehicle.no_fuel", "The tank is empty.")
	_set_running(true)
	return FrameworkResult.ok(self)


func stop_engine(reason: StringName = &"stopped") -> void:
	if not _running:
		return
	_set_running(false)
	if adapter != null:
		adapter.set_throttle(0.0)
	if reason != &"stopped":
		engine_stalled.emit(reason)


# --- Time -----------------------------------------------------------------

## Advances the vehicle one step: burns fuel, integrates motion, mirrors state.
##
## Fuel is spent before the step rather than after, so a tank that runs dry
## this frame stops the engine before the frame's throttle is applied. The
## other order gives one free frame of power out of an empty tank, which is
## invisible at 60Hz and obvious in a replay.
func tick(delta: float) -> void:
	if delta <= 0.0 or adapter == null:
		return
	_burn_fuel(delta)
	adapter.step(delta)
	_update_states()


# --- Persistence ----------------------------------------------------------
#
# Engine and motion. Fuel is the tank's, occupancy is the seats', contents are
# the inventory's -- each component saves what it owns and nothing else, which
# is what makes "vehicle persists" a property of the composition rather than a
# serialiser that knows about cars.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {
		"running": _running,
		"speed": get_speed(),
		"heading": adapter.get_heading() if adapter != null else 0.0,
	}


func restore_state(data: Dictionary) -> void:
	if adapter != null:
		adapter.release_controls()
		adapter.set_heading(float(data.get("heading", 0.0)))
		adapter.set_speed(float(data.get("speed", 0.0)))
	_set_running(bool(data.get("running", false)))
	_update_states()


# --- Internals ------------------------------------------------------------

## Carries the definition's toughness onto the health component, once.
##
## Guarded on [method VehicleDefinition.is_destructible], so a set-piece
## vehicle authored with zero health stays indestructible rather than being
## given a maximum of zero -- which would make it start the game already dead.
func _apply_definition_health() -> void:
	if not apply_definition_health or health == null or _definition == null:
		return
	if not _definition.is_destructible():
		return
	# A stat already driving the maximum wins: an upgrade granting
	# stat.health.max is exactly the sort of thing that should beat the base
	# model's number, and clobbering it here would make the upgrade do nothing.
	if health.stats != null and health.stats.has_stat(health.maximum_stat):
		return
	var previous := health.maximum_health
	if is_equal_approx(previous, _definition.maximum_health):
		return
	# Whether it was full has to be read before the maximum moves, or a fresh
	# car goes from 100/100 to 100/600 and starts the game already wrecked-ish.
	var was_full := is_equal_approx(health.get_current(), previous)
	health.maximum_health = _definition.maximum_health
	if was_full or health.get_current() <= 0.0:
		health.set_current(_definition.maximum_health)


func _burn_fuel(delta: float) -> void:
	if not _running or fuel == null or not fuel.has_tank():
		return
	var used := VehicleSolver.solve_fuel_use(
		adapter.get_throttle(), _running, get_handling(), delta
	)
	fuel.consume(used)
	if fuel.is_empty():
		stop_engine(&"vehicle.no_fuel")


func _set_running(running: bool) -> void:
	if running == _running:
		return
	_running = running
	_set_state(GameplayNames.STATE_ENGINE_RUNNING, running)
	engine_changed.emit(running)


func _update_states() -> void:
	_set_state(GameplayNames.STATE_DRIVING, _running and is_moving())


func _set_state(state: StringName, active: bool) -> void:
	if semantic_state != null:
		semantic_state.set_state(state, active)


func _on_occupant_entered(_occupant: Node, seat: SeatDefinition) -> void:
	if start_on_driver and seat != null and seat.is_driver():
		start_engine()


func _on_occupant_exited(_occupant: Node, seat: SeatDefinition) -> void:
	if seat != null and seat.is_driver():
		# Whoever was driving is not any more. Leaving the pedals where they
		# were is how an abandoned car drives itself into the sea.
		release_controls()


func _on_died(_context: DamageContext) -> void:
	stop_engine(&"vehicle.destroyed")
	if adapter != null:
		adapter.halt()
	if seats != null:
		seats.eject_all(&"vehicle.destroyed")
	destroyed.emit()


## Read by property name rather than by casting, so a boat or a mech with its
## own definition type is drivable (rule 9).
func _resolve_definition() -> VehicleDefinition:
	if vehicle_override != null:
		return vehicle_override
	var definition := get_definition()
	if definition is VehicleDefinition:
		return definition as VehicleDefinition
	if definition != null and "vehicle" in definition:
		var candidate: Variant = definition.get("vehicle")
		if candidate is VehicleDefinition:
			return candidate as VehicleDefinition
	return null


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
