extends FrameworkTestCase
## Covers VehicleComponent, FuelComponent and VehicleControllerAdapter: the
## engine, the tank, the command API and what a wreck does.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var car: Node3D = null
var vehicle: VehicleComponent = null
var adapter: VehicleControllerAdapter = null
var fuel: FuelComponent = null
var seats: SeatComponent = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	car = VehicleFixtures.vehicle("Sedan")
	add_test_node(car)
	VehicleFixtures.assemble(car, core)
	vehicle = VehicleFixtures.vehicle_of(car)
	adapter = VehicleFixtures.adapter_of(car)
	fuel = VehicleFixtures.fuel_of(car)
	seats = VehicleFixtures.seats_of(car)


func _drive(seconds: float, step: float = 0.25) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		vehicle.tick(step)
		elapsed += step


# --- Resolution ------------------------------------------------------------

func test_the_vehicle_finds_its_definition_and_handling() -> void:
	assert_not_null(vehicle.get_vehicle())
	assert_not_null(vehicle.get_handling())
	assert_eq(vehicle.get_vehicle().id, &"vehicle.sedan")


func test_the_adapter_is_given_the_handling_profile() -> void:
	assert_eq(adapter.handling, vehicle.get_handling())


func test_a_vehicle_with_no_adapter_gets_one() -> void:
	# A vehicle with no physics still integrates, which is what a headless
	# server and a test both need.
	var bare := Node3D.new()
	bare.name = "Bare"
	var component := VehicleComponent.new()
	component.name = "VehicleComponent"
	component.vehicle_override = VehicleFixtures.definition()
	component.auto_tick = false
	bare.add_child(component)
	add_test_node(bare)
	VehicleFixtures.assemble(bare, core)

	assert_not_null(component.adapter)
	assert_ok(component.start_engine())
	component.set_throttle(1.0)
	component.tick(1.0)
	assert_true(component.get_speed() > 0.0)


func test_the_definitions_toughness_reaches_the_health_component() -> void:
	# HealthComponent has never heard of a vehicle definition, rightly. Someone
	# has to carry "this model takes 600" across, and the vehicle is the only
	# thing that knows both.
	var health := VehicleFixtures.find(car, HealthComponent) as HealthComponent
	assert_almost_eq(health.get_maximum(), 600.0)
	assert_almost_eq(health.get_current(), 600.0, 0.001, "and it starts full, not at 100")


func test_a_set_piece_vehicle_with_no_health_stays_indestructible() -> void:
	var definition := VehicleFixtures.definition(&"vehicle.prop", 1, 0.0, 0.0)
	var prop := VehicleFixtures.vehicle("Prop", definition)
	add_test_node(prop)
	VehicleFixtures.assemble(prop, core)
	var health := VehicleFixtures.find(prop, HealthComponent) as HealthComponent
	assert_true(health.get_maximum() > 0.0, "not given a maximum of zero")
	assert_true(health.is_alive(), "and not dead on arrival")


# --- Engine ----------------------------------------------------------------

func test_the_engine_starts_and_stops() -> void:
	assert_false(vehicle.is_running())
	assert_ok(vehicle.start_engine())
	assert_true(vehicle.is_running())
	vehicle.stop_engine()
	assert_false(vehicle.is_running())


func test_starting_twice_is_refused() -> void:
	assert_ok(vehicle.start_engine())
	assert_err(vehicle.start_engine(), &"vehicle.already_running")


func test_an_empty_tank_refuses_to_start() -> void:
	fuel.drain()
	assert_err(vehicle.start_engine(), &"vehicle.no_fuel")


func test_the_engine_is_mirrored_onto_semantic_state() -> void:
	var state := VehicleFixtures.find(car, SemanticState) as SemanticState
	assert_ok(vehicle.start_engine())
	assert_true(state.has_state(GameplayNames.STATE_ENGINE_RUNNING))
	vehicle.stop_engine()
	assert_false(state.has_state(GameplayNames.STATE_ENGINE_RUNNING))


func test_the_engine_change_is_announced() -> void:
	var changes: Array = []
	vehicle.engine_changed.connect(func(running: bool) -> void: changes.append(running))
	assert_ok(vehicle.start_engine())
	vehicle.stop_engine()
	assert_eq(changes, [true, false])


func test_a_driver_sitting_down_starts_the_engine() -> void:
	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_true(vehicle.is_running())


func test_a_passenger_sitting_down_does_not() -> void:
	var rider := VehicleFixtures.occupant("Rider")
	add_test_node(rider)
	VehicleFixtures.assemble(rider, core)
	assert_ok(seats.enter(rider, &"seat.passenger0"))
	assert_false(vehicle.is_running())


func test_a_vehicle_that_needs_the_key_turned_does_not_start_itself() -> void:
	vehicle.start_on_driver = false
	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_false(vehicle.is_running())
	assert_ok(vehicle.start_engine())


# --- The command API -------------------------------------------------------

func test_throttle_moves_the_vehicle() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(1.0)
	assert_true(vehicle.get_speed() > 0.0)
	assert_true(vehicle.is_moving())


func test_a_dead_engine_has_no_throttle() -> void:
	# Otherwise "out of fuel" is cosmetic.
	vehicle.set_throttle(1.0)
	_drive(1.0)
	assert_almost_eq(vehicle.get_speed(), 0.0)


func test_the_brakes_work_with_the_engine_off() -> void:
	# The one control that must. A car whose engine cuts mid-corner still stops.
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(2.0)
	var rolling := vehicle.get_speed()
	assert_true(rolling > 1.0)

	vehicle.stop_engine()
	vehicle.set_brake(1.0)
	vehicle.tick(0.1)
	assert_true(vehicle.get_speed() < rolling)


func test_steering_turns_the_vehicle() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(2.0)
	var before := adapter.get_heading()
	vehicle.set_steering(1.0)
	_drive(1.0)
	assert_ne(adapter.get_heading(), before)


func test_the_handbrake_stops_it() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(2.0)
	assert_true(vehicle.get_speed() > 1.0)
	vehicle.set_throttle(0.0)
	vehicle.set_handbrake(true)
	_drive(3.0)
	assert_almost_eq(vehicle.get_speed(), 0.0)


func test_releasing_the_controls_lets_go_of_everything() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	vehicle.set_steering(0.5)
	vehicle.set_handbrake(true)
	vehicle.release_controls()
	assert_almost_eq(adapter.get_throttle(), 0.0)
	assert_almost_eq(adapter.get_steering(), 0.0)
	assert_false(adapter.is_handbrake_on())


func test_a_driver_getting_out_lets_go_of_the_pedals() -> void:
	# Otherwise an abandoned car drives itself into the sea.
	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	assert_ok(seats.enter(driver, &"seat.driver"))
	vehicle.set_throttle(1.0)
	assert_ok(seats.exit(driver))
	assert_almost_eq(adapter.get_throttle(), 0.0)


# --- Motion reporting ------------------------------------------------------

func test_the_motion_state_reads_what_the_vehicle_is_doing() -> void:
	assert_eq(vehicle.get_motion_state(), VehicleControllerAdapter.MotionState.STOPPED)
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(1.0)
	assert_eq(
		vehicle.get_motion_state(), VehicleControllerAdapter.MotionState.ACCELERATING
	)
	vehicle.set_throttle(0.0)
	assert_eq(vehicle.get_motion_state(), VehicleControllerAdapter.MotionState.CRUISING)
	vehicle.set_brake(1.0)
	assert_eq(vehicle.get_motion_state(), VehicleControllerAdapter.MotionState.BRAKING)


func test_reversing_is_reported_as_reversing() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(-1.0)
	_drive(2.0)
	assert_true(vehicle.get_speed() < 0.0)
	assert_eq(vehicle.get_motion_state(), VehicleControllerAdapter.MotionState.REVERSING)


func test_starting_and_stopping_moving_is_announced_once_each() -> void:
	var changes: Array = []
	adapter.motion_changed.connect(func(moving: bool) -> void: changes.append(moving))
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(2.0)
	vehicle.set_throttle(0.0)
	vehicle.set_brake(1.0)
	_drive(5.0)
	assert_eq(changes, [true, false])


# --- Fuel ------------------------------------------------------------------

func test_the_tank_starts_from_the_definition() -> void:
	assert_almost_eq(fuel.get_capacity(), 50.0)
	assert_almost_eq(fuel.get_level(), 50.0)
	assert_true(fuel.is_full())


func test_a_half_full_definition_starts_half_full() -> void:
	var definition := VehicleFixtures.definition(&"vehicle.used")
	definition.starting_fuel_fraction = 0.5
	var used := VehicleFixtures.vehicle("Used", definition)
	add_test_node(used)
	VehicleFixtures.assemble(used, core)
	assert_almost_eq(VehicleFixtures.fuel_of(used).get_level(), 25.0)


func test_driving_burns_fuel() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(4.0, 1.0)
	assert_almost_eq(fuel.get_level(), 46.0)


func test_idling_burns_fuel_more_slowly() -> void:
	assert_ok(vehicle.start_engine())
	_drive(4.0, 1.0)
	var idled := 50.0 - fuel.get_level()
	assert_true(idled > 0.0, "idling is not free")
	assert_true(idled < 4.0, "but it is cheaper than driving, got %f" % idled)


func test_a_stopped_engine_burns_nothing() -> void:
	_drive(10.0, 1.0)
	assert_almost_eq(fuel.get_level(), 50.0)


func test_running_out_stops_the_engine() -> void:
	fuel.set_level(1.0)
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(3.0, 1.0)
	assert_true(fuel.is_empty())
	assert_false(vehicle.is_running())


func test_running_out_is_announced_with_its_reason() -> void:
	var stalls: Array = []
	vehicle.engine_stalled.connect(func(reason: StringName) -> void: stalls.append(reason))
	fuel.set_level(0.5)
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	_drive(2.0, 1.0)
	assert_eq(stalls, [&"vehicle.no_fuel"])


func test_an_empty_tank_gives_no_free_frame_of_power() -> void:
	# Fuel is spent before the step, not after. The other order lets a dry tank
	# deliver one more frame of throttle, which is invisible at 60Hz and
	# obvious in a replay.
	fuel.set_level(0.4)
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	vehicle.tick(1.0)
	assert_false(vehicle.is_running())
	assert_almost_eq(vehicle.get_speed(), 0.0)


func test_refuelling_returns_what_actually_fitted() -> void:
	fuel.set_level(45.0)
	assert_almost_eq(fuel.refuel(20.0), 5.0, 0.001, "a jerrycan does not all fit")
	assert_true(fuel.is_full())


func test_the_low_warning_fires_once_on_the_way_down() -> void:
	var warnings: Array = []
	fuel.fuel_low.connect(func(low: bool) -> void: warnings.append(low))
	fuel.set_level(6.0)
	fuel.set_level(5.0)
	assert_eq(warnings, [true])
	fuel.fill()
	assert_eq(warnings, [true, false])


func test_emptying_is_announced() -> void:
	var emptied: Array = []
	fuel.fuel_emptied.connect(func() -> void: emptied.append(1))
	fuel.drain()
	assert_size(emptied, 1)


func test_a_vehicle_with_no_tank_never_runs_out() -> void:
	# A bicycle. Rule 31: a missing capability is a valid configuration.
	var definition := VehicleFixtures.definition(&"vehicle.bike", 1, 0.0)
	var bike := VehicleFixtures.vehicle("Bike", definition)
	add_test_node(bike)
	VehicleFixtures.assemble(bike, core)

	var tank := VehicleFixtures.fuel_of(bike)
	var engine := VehicleFixtures.vehicle_of(bike)
	assert_false(tank.has_tank())
	assert_false(tank.is_empty(), "no tank is not an empty tank")
	assert_ok(engine.start_engine())
	engine.set_throttle(1.0)
	for step in 100:
		engine.tick(1.0)
	assert_true(engine.is_running())


# --- Wrecking --------------------------------------------------------------

func test_a_wrecked_vehicle_stops_and_throws_everybody_out() -> void:
	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	assert_ok(seats.enter(driver, &"seat.driver"))
	vehicle.set_throttle(1.0)
	_drive(2.0)

	var health := VehicleFixtures.find(car, HealthComponent) as HealthComponent
	health.kill()

	assert_true(vehicle.is_wrecked())
	assert_false(vehicle.is_running())
	assert_almost_eq(vehicle.get_speed(), 0.0)
	assert_true(seats.is_empty())


func test_destruction_is_announced() -> void:
	var wrecks: Array = []
	vehicle.destroyed.connect(func() -> void: wrecks.append(1))
	var health := VehicleFixtures.find(car, HealthComponent) as HealthComponent
	health.kill()
	assert_size(wrecks, 1)


func test_a_wrecked_vehicle_refuses_to_start() -> void:
	var health := VehicleFixtures.find(car, HealthComponent) as HealthComponent
	health.kill()
	assert_err(vehicle.start_engine(), &"vehicle.wrecked")


func test_damage_reaches_a_vehicle_through_the_same_pipeline_a_person_uses() -> void:
	var receiver := (
		VehicleFixtures.find(car, DamageReceiverComponent) as DamageReceiverComponent
	)
	var health := VehicleFixtures.find(car, HealthComponent) as HealthComponent
	receiver.receive_amount(100.0, [&"damage.ballistic"])
	assert_almost_eq(health.get_current(), 500.0)


# --- Persistence -----------------------------------------------------------

func test_a_vehicle_survives_a_save() -> void:
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	vehicle.set_steering(0.6)
	_drive(3.0)
	var speed := vehicle.get_speed()
	var heading := adapter.get_heading()
	var saved := vehicle.capture_state()
	var saved_fuel := fuel.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	var restored := VehicleFixtures.vehicle_of(other)
	restored.restore_state(saved)
	VehicleFixtures.fuel_of(other).restore_state(saved_fuel)

	assert_true(vehicle.is_persistent())
	assert_true(restored.is_running())
	assert_almost_eq(restored.get_speed(), speed)
	assert_almost_eq(VehicleFixtures.adapter_of(other).get_heading(), heading)
	assert_almost_eq(VehicleFixtures.fuel_of(other).get_level(), fuel.get_level())


func test_a_restored_vehicle_is_not_holding_the_pedals_it_was() -> void:
	# The save records where it was, not what somebody was pressing. A car
	# loaded mid-corner should not drive itself off.
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	vehicle.set_steering(1.0)
	_drive(2.0)
	var saved := vehicle.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	VehicleFixtures.vehicle_of(other).restore_state(saved)

	assert_almost_eq(VehicleFixtures.adapter_of(other).get_throttle(), 0.0)
	assert_almost_eq(VehicleFixtures.adapter_of(other).get_steering(), 0.0)


func test_a_reloaded_tank_is_not_refilled_by_a_second_initialize() -> void:
	# The free-petrol bug, the same shape as M12's free meal.
	fuel.set_level(7.0)
	var saved := fuel.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	var tank := VehicleFixtures.fuel_of(other)
	tank.restore_state(saved)
	VehicleFixtures.assemble(other, core)

	assert_almost_eq(tank.get_level(), 7.0)
