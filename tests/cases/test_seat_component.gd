extends FrameworkTestCase
## Covers SeatDefinition and SeatComponent: who is aboard, who may be, and how
## that survives a save.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var car: Node3D = null
var seats: SeatComponent = null
var driver: Node3D = null
var passenger: Node3D = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	car = VehicleFixtures.vehicle("Sedan")
	add_test_node(car)
	VehicleFixtures.assemble(car, core)
	seats = VehicleFixtures.seats_of(car)

	driver = VehicleFixtures.occupant("Driver")
	passenger = VehicleFixtures.occupant("Passenger")
	add_test_node(driver)
	add_test_node(passenger)
	VehicleFixtures.assemble(driver, core)
	VehicleFixtures.assemble(passenger, core)


# --- Definition ------------------------------------------------------------

func test_a_seat_with_no_id_is_an_error() -> void:
	assert_true(SeatDefinition.new().validate().has_errors())


func test_a_disabled_driver_seat_is_a_warning() -> void:
	var seat := VehicleFixtures.seat(&"seat.driver", SeatDefinition.Role.DRIVER)
	seat.enabled = false
	assert_true(seat.validate().has_warnings())


func test_only_the_driver_seat_controls_the_vehicle() -> void:
	var wheel := VehicleFixtures.seat(&"seat.driver", SeatDefinition.Role.DRIVER)
	var turret := VehicleFixtures.seat(&"seat.turret", SeatDefinition.Role.TURRET)
	assert_true(wheel.controls_vehicle())
	assert_false(turret.controls_vehicle(), "a gunner aims their own thing")


func test_a_seat_names_the_input_context_it_implies() -> void:
	var wheel := VehicleFixtures.seat(&"seat.driver", SeatDefinition.Role.DRIVER)
	var back := VehicleFixtures.seat(&"seat.rear", SeatDefinition.Role.PASSENGER)
	assert_eq(wheel.get_input_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER)
	assert_eq(back.get_input_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_PASSENGER)


func test_a_vehicle_with_two_seats_of_the_same_id_is_an_error() -> void:
	var definition := VehicleFixtures.definition(&"vehicle.broken")
	var duplicated: Array[SeatDefinition] = [
		VehicleFixtures.seat(&"seat.driver", SeatDefinition.Role.DRIVER),
		VehicleFixtures.seat(&"seat.driver", SeatDefinition.Role.PASSENGER),
	]
	definition.seats = duplicated
	assert_true(definition.validate().has_errors())


func test_a_vehicle_with_no_driver_seat_is_a_warning() -> void:
	var definition := VehicleFixtures.definition(&"vehicle.trailer")
	var only_passengers: Array[SeatDefinition] = [
		VehicleFixtures.seat(&"seat.rear", SeatDefinition.Role.PASSENGER)
	]
	definition.seats = only_passengers
	assert_true(definition.validate().has_warnings())


# --- Resolution ------------------------------------------------------------

func test_seats_come_from_the_vehicle_definition() -> void:
	assert_eq(seats.get_seat_count(), 2)
	assert_true(seats.has_seat(&"seat.driver"))


func test_an_override_wins_over_the_definition() -> void:
	var custom := Node3D.new()
	custom.name = "Bus"
	var component := SeatComponent.new()
	component.name = "SeatComponent"
	var only: Array[SeatDefinition] = [
		VehicleFixtures.seat(&"seat.wheel", SeatDefinition.Role.DRIVER)
	]
	component.seats_override = only
	custom.add_child(component)
	add_test_node(custom)
	VehicleFixtures.assemble(custom, core, VehicleFixtures.definition())

	assert_eq(component.get_seat_count(), 1)
	assert_true(component.has_seat(&"seat.wheel"))


# --- Entering --------------------------------------------------------------

func test_somebody_can_get_in() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_eq(seats.get_occupant(&"seat.driver"), driver)
	assert_true(seats.contains(driver))
	assert_eq(seats.get_driver(), driver)


func test_entering_without_naming_a_seat_takes_the_wheel_first() -> void:
	# Pressing E on a car should put you in the driver's seat, not the back.
	assert_ok(seats.enter(driver))
	assert_eq(seats.get_seat_of(driver), &"seat.driver")


func test_the_second_person_in_takes_a_passenger_seat() -> void:
	assert_ok(seats.enter(driver))
	assert_ok(seats.enter(passenger))
	assert_eq(seats.get_seat_of(passenger), &"seat.passenger0")
	assert_eq(seats.get_occupant_count(), 2)


func test_a_taken_seat_is_refused() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_err(seats.enter(passenger, &"seat.driver"), &"seat.occupied")


func test_getting_in_twice_is_refused() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_err(seats.enter(driver, &"seat.passenger0"), &"seat.already_aboard")


func test_a_seat_that_does_not_exist_is_refused() -> void:
	assert_err(seats.enter(driver, &"seat.wing"), &"seat.no_such_seat")


func test_a_disabled_seat_is_refused() -> void:
	seats.get_seat(&"seat.driver").enabled = false
	assert_err(seats.enter(driver, &"seat.driver"), &"seat.disabled")


func test_a_full_vehicle_is_refused() -> void:
	var third := VehicleFixtures.occupant("Third")
	add_test_node(third)
	VehicleFixtures.assemble(third, core)
	assert_ok(seats.enter(driver))
	assert_ok(seats.enter(passenger))
	assert_err(seats.enter(third), &"seat.full")


func test_nobody_is_refused() -> void:
	assert_err(seats.enter(null, &"seat.driver"), &"seat.no_occupant")


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array = []
	seats.entry_refused.connect(
		func(_who: Node, _seat: StringName, reason: StringName) -> void:
			refusals.append(reason)
	)
	assert_err(seats.enter(driver, &"seat.wing"), &"seat.no_such_seat")
	assert_eq(refusals, [&"seat.no_such_seat"])


func test_entering_is_announced_with_the_seat() -> void:
	var seated: Array = []
	seats.occupant_entered.connect(
		func(who: Node, seat: SeatDefinition) -> void:
			seated.append([String(who.name), seat.id])
	)
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_eq(seated, [["Driver", &"seat.driver"]])


func test_can_enter_answers_without_seating_anybody() -> void:
	assert_ok(seats.can_enter(driver, &"seat.driver"))
	assert_ok(seats.can_enter(driver, &"seat.driver"))
	assert_false(seats.contains(driver))


# --- Requirements ----------------------------------------------------------

func test_a_seat_can_require_an_item() -> void:
	# Reuses M5's requirements rather than inventing a second vocabulary: a
	# seat that needs a key is the same resource a locked door uses.
	var key := ItemFixtures.unique(&"item.car_key")
	core.get_definition_registry().register(key)
	var requirement := InteractionFixtures.needs_item(&"item.car_key", 1, false)
	var required: Array[InteractionRequirement] = [requirement]
	seats.get_seat(&"seat.driver").requirements = required

	assert_true(seats.enter(driver, &"seat.driver").is_err())

	var keyed := VehicleFixtures.occupant("Keyed")
	var bag := InventoryComponent.new()
	bag.name = "InventoryComponent"
	bag.profile_override = ItemFixtures.container(5)
	keyed.add_child(bag)
	add_test_node(keyed)
	VehicleFixtures.assemble(keyed, core)
	assert_ok(bag.add(ItemInstance.create(key, 1)))

	assert_ok(seats.enter(keyed, &"seat.driver"))


# --- Reach -----------------------------------------------------------------

func test_entry_range_keeps_distant_people_out() -> void:
	seats.entry_range = 3.0
	driver.global_position = Vector3(50.0, 0.0, 0.0)
	assert_err(seats.enter(driver, &"seat.driver"), &"seat.out_of_reach")
	driver.global_position = Vector3(1.0, 0.0, 0.0)
	assert_ok(seats.enter(driver, &"seat.driver"))


func test_no_entry_range_means_anybody_anywhere() -> void:
	driver.global_position = Vector3(500.0, 0.0, 0.0)
	assert_ok(seats.enter(driver, &"seat.driver"))


# --- Leaving ---------------------------------------------------------------

func test_somebody_can_get_out() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_ok(seats.exit(driver))
	assert_false(seats.contains(driver))
	assert_true(seats.is_empty())
	assert_null(seats.get_driver())


func test_getting_out_when_you_were_never_in_is_refused() -> void:
	assert_err(seats.exit(driver), &"seat.not_aboard")


func test_leaving_is_announced_with_the_seat_left() -> void:
	var left: Array = []
	seats.occupant_exited.connect(
		func(who: Node, seat: SeatDefinition) -> void:
			left.append([String(who.name), seat.id])
	)
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_ok(seats.exit(driver))
	assert_eq(left, [["Driver", &"seat.driver"]])


func test_a_freed_seat_can_be_taken_again() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_ok(seats.exit(driver))
	assert_ok(seats.enter(passenger, &"seat.driver"))


func test_everybody_can_be_ejected_at_once() -> void:
	assert_ok(seats.enter(driver))
	assert_ok(seats.enter(passenger))
	var thrown := seats.eject_all()
	assert_size(thrown, 2)
	assert_true(seats.is_empty())
	assert_eq(seats.get_occupant_count(), 0)


func test_an_occupant_freed_out_from_under_the_vehicle_reads_as_empty() -> void:
	# Reading a freed instance out of a Dictionary into a typed local throws
	# before is_instance_valid() can be reached, so this crashed rather than
	# answering null. A destroyed passenger must not take the car with it.
	assert_ok(seats.enter(driver, &"seat.driver"))
	driver.get_parent().remove_child(driver)
	driver.free()

	assert_null(seats.get_occupant(&"seat.driver"))
	assert_null(seats.get_driver())
	assert_empty(seats.get_occupants())
	assert_eq(seats.get_occupant_count(), 0)


# --- Semantic state --------------------------------------------------------

func test_occupancy_is_mirrored_onto_semantic_state() -> void:
	var state := VehicleFixtures.find(car, SemanticState) as SemanticState
	assert_false(state.has_state(GameplayNames.STATE_OCCUPIED))
	assert_ok(seats.enter(driver))
	assert_true(state.has_state(GameplayNames.STATE_OCCUPIED))
	assert_ok(seats.exit(driver))
	assert_false(state.has_state(GameplayNames.STATE_OCCUPIED))


func test_one_person_leaving_a_full_car_leaves_it_occupied() -> void:
	var state := VehicleFixtures.find(car, SemanticState) as SemanticState
	assert_ok(seats.enter(driver))
	assert_ok(seats.enter(passenger))
	assert_ok(seats.exit(driver))
	assert_true(state.has_state(GameplayNames.STATE_OCCUPIED), "the passenger is still in")


# --- Persistence -----------------------------------------------------------

func test_occupancy_is_saved_by_persistent_id() -> void:
	# By id, never by node path: a save reloaded into a rebuilt scene has
	# different nodes, and that is the whole point of rule 32.
	assert_ok(seats.enter(driver, &"seat.driver"))
	var saved := seats.capture_state()
	assert_true(seats.is_persistent())
	assert_eq(saved["occupants"]["seat.driver"], "driver.instance")


func test_a_restored_vehicle_knows_who_was_aboard_before_they_exist() -> void:
	# Two steps and it cannot be one: the entities a save names may not have
	# been spawned yet when the vehicle is restored.
	assert_ok(seats.enter(driver, &"seat.driver"))
	var saved := seats.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	var restored := VehicleFixtures.seats_of(other)
	restored.restore_state(saved)

	assert_true(restored.is_empty(), "nobody is seated yet")
	assert_eq(restored.get_pending_occupants()[&"seat.driver"], &"driver.instance")


func test_a_restored_occupant_is_put_back_in_their_own_seat() -> void:
	assert_ok(seats.enter(passenger, &"seat.passenger0"))
	var saved := seats.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	var restored := VehicleFixtures.seats_of(other)
	restored.restore_state(saved)

	assert_ok(restored.resolve_pending(passenger))
	assert_eq(restored.get_seat_of(passenger), &"seat.passenger0")
	assert_empty(restored.get_pending_occupants())


func test_an_unexpected_entity_is_not_seated_by_a_restore() -> void:
	assert_ok(seats.enter(driver, &"seat.driver"))
	var saved := seats.capture_state()

	var other := VehicleFixtures.vehicle("Restored")
	add_test_node(other)
	VehicleFixtures.assemble(other, core)
	var restored := VehicleFixtures.seats_of(other)
	restored.restore_state(saved)

	assert_err(restored.resolve_pending(passenger), &"seat.not_expected")
	assert_true(restored.is_empty())


func test_an_entity_with_no_identity_cannot_be_restored() -> void:
	var anonymous := Node3D.new()
	anonymous.name = "Anonymous"
	add_test_node(anonymous)
	seats.restore_state({"occupants": {"seat.driver": "somebody"}})
	assert_err(seats.resolve_pending(anonymous), &"seat.no_identity")
