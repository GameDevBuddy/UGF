extends FrameworkTestCase
## The M13 exit gate: player and AI drive through the same adapter, and getting
## in and out is a handover rather than a change of identity.
##
## What is being asserted is a negative. There is no player path and no AI
## path: [VehicleControllerComponent] and [VehicleAIDriver] call the same four
## methods on the same [VehicleComponent], and neither can tell whether the
## other exists. The same claim [test_ai_controller.gd] makes about walking.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const FakeInputSource := preload("res://tests/support/fake_input_source.gd")

var core: Node = null
var router: InputRouter = null
var source: InputSource = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	source = FakeInputSource.new()
	router = InputRouter.new(source)
	add_test_node(router)
	core.register_service(GameplayNames.SERVICE_INPUT, router)
	router.set_context(InputContexts.on_foot())


func _car(with_ai: bool = false, with_controls: bool = false) -> Node3D:
	var car := VehicleFixtures.vehicle("Sedan", null, with_ai, with_controls)
	add_test_node(car)
	VehicleFixtures.assemble(car, core)
	return car


func _person(with_controller: bool = false, with_ai: bool = false) -> Node3D:
	var person := VehicleFixtures.occupant("Player", with_controller, with_ai)
	add_test_node(person)
	VehicleFixtures.assemble(person, core)
	return person


# --- One adapter, two drivers ---------------------------------------------

func test_a_player_and_an_ai_reach_the_same_adapter() -> void:
	var car := _car(true, true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var adapter := VehicleFixtures.adapter_of(car)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(vehicle.start_engine())

	# The player, through input.
	assert_ok(driver.take_control())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	driver.drive(0.1)
	var player_throttle := adapter.get_throttle()
	assert_true(player_throttle > 0.0)
	assert_ok(driver.release_control())

	# The AI, through its own reasoning. The values differ -- the AI cruises,
	# the player floors it -- and that is the point: what is shared is the
	# adapter, not the policy. Asserting they matched would be asserting the
	# AI has no judgement of its own.
	brain.set_active(true)
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, 200.0)))
	brain.drive(0.1)
	assert_true(adapter.get_throttle() > 0.0)
	assert_ne(adapter.get_throttle(), player_throttle, "different demand...")
	assert_eq(
		VehicleFixtures.adapter_of(car), adapter, "...written to the same adapter"
	)
	assert_eq(driver.vehicle, brain.vehicle, "reached through the same vehicle")


func test_an_ai_drives_a_vehicle_to_a_destination() -> void:
	var car := _car(true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, 100.0)))
	assert_true(vehicle.is_running(), "it starts the engine itself")

	for step in 400:
		brain.drive(0.1)
		vehicle.tick(0.1)
		car.global_position += vehicle.adapter.get_velocity() * 0.1
		if not brain.has_destination():
			break

	assert_false(brain.has_destination(), "it should have arrived")
	assert_true(car.global_position.z > 90.0, "got %f" % car.global_position.z)


func test_an_ai_turns_towards_a_target_beside_it() -> void:
	var car := _car(true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(brain.drive_to(Vector3(100.0, 0.0, 0.0)))

	for step in 200:
		brain.drive(0.1)
		vehicle.tick(0.1)
		car.global_position += vehicle.adapter.get_velocity() * 0.1

	# Facing east, more or less, rather than still pointing north.
	assert_true(
		absf(wrapf(vehicle.adapter.get_heading() - PI / 2.0, -PI, PI)) < 0.6,
		"heading %f" % vehicle.adapter.get_heading()
	)


func test_an_ai_pointed_the_wrong_way_slows_down_before_driving_off() -> void:
	var car := _car(true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, -100.0)))
	brain.drive(0.1)
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0)
	assert_true(vehicle.adapter.get_brake() > 0.0)


func test_an_ai_arriving_is_announced() -> void:
	var car := _car(true)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	var arrivals: Array = []
	brain.arrived.connect(func(where: Vector3) -> void: arrivals.append(where))
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, 1.0)))
	brain.drive(0.1)
	assert_size(arrivals, 1)


func test_an_ai_told_to_stop_stops() -> void:
	var car := _car(true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, 100.0)))
	brain.drive(0.1)
	brain.stop()
	assert_false(brain.has_destination())
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0)
	assert_true(vehicle.adapter.get_brake() > 0.0)


func test_a_deactivated_ai_lets_go() -> void:
	var car := _car(true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	assert_ok(brain.drive_to(Vector3(0.0, 0.0, 100.0)))
	brain.drive(0.1)
	assert_true(vehicle.adapter.get_throttle() > 0.0)

	brain.set_active(false)
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0)
	brain.drive(0.1)
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0, 0.001, "and stays let go")


func test_an_ai_with_no_vehicle_refuses_rather_than_crashing() -> void:
	var brain := VehicleAIDriver.new()
	brain.name = "VehicleAIDriver"
	var bare := Node3D.new()
	bare.name = "Bare"
	bare.add_child(brain)
	add_test_node(bare)
	VehicleFixtures.assemble(bare, core)
	assert_err(brain.drive_to(Vector3.ZERO), &"ai_driver.no_vehicle")


# --- Player controls -------------------------------------------------------

func test_taking_control_pushes_the_driving_context() -> void:
	var car := _car(false, true)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(driver.take_control())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER)
	assert_true(driver.is_controlling())


func test_releasing_control_restores_what_was_beneath() -> void:
	var car := _car(false, true)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(driver.take_control())
	assert_ok(driver.release_control())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_ON_FOOT)


func test_releasing_control_lets_go_of_the_pedals() -> void:
	var car := _car(false, true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(vehicle.start_engine())
	assert_ok(driver.take_control())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	driver.drive(0.1)
	assert_true(vehicle.adapter.get_throttle() > 0.0)

	assert_ok(driver.release_control())
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0)


func test_steering_comes_from_the_same_axes_walking_does() -> void:
	# Forward is forward and left is left whether you are walking or driving.
	var car := _car(false, true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(vehicle.start_engine())
	assert_ok(driver.take_control())
	source.press(GameplayNames.ACTION_MOVE_RIGHT)
	driver.drive(0.1)
	assert_true(vehicle.adapter.get_steering() > 0.0)


func test_the_handbrake_is_on_the_jump_action() -> void:
	var car := _car(false, true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(vehicle.start_engine())
	assert_ok(driver.take_control())
	source.press(GameplayNames.ACTION_JUMP)
	driver.drive(0.1)
	assert_true(vehicle.adapter.is_handbrake_on())


func test_a_suppressed_context_makes_the_car_let_go() -> void:
	# A menu is up. The car should coast, not sit frozen holding the throttle.
	var car := _car(false, true)
	var vehicle := VehicleFixtures.vehicle_of(car)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(vehicle.start_engine())
	assert_ok(driver.take_control())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	driver.drive(0.1)
	assert_true(vehicle.adapter.get_throttle() > 0.0)

	router.push_context(InputContexts.ui())
	driver.drive(0.1)
	assert_almost_eq(vehicle.adapter.get_throttle(), 0.0)


func test_taking_control_twice_is_refused() -> void:
	var car := _car(false, true)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(driver.take_control())
	assert_err(driver.take_control(), &"driver.already_controlling")


func test_two_drivers_remove_their_own_context_and_not_each_others() -> void:
	# By instance, not by id: two players both driving push contexts with the
	# same id, and removing by id would take whichever pushed last.
	var first := _car(false, true)
	var second := VehicleFixtures.vehicle("Second", null, false, true)
	add_test_node(second)
	VehicleFixtures.assemble(second, core)

	var one := VehicleFixtures.find(first, VehicleControllerComponent) as VehicleControllerComponent
	var two := VehicleFixtures.find(second, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(one.take_control())
	assert_ok(two.take_control())
	assert_eq(router.get_depth(), 3)

	assert_ok(one.release_control())
	assert_eq(router.get_depth(), 2)
	assert_true(two.is_controlling())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER)


# --- Possession ------------------------------------------------------------

func test_getting_in_hands_control_from_the_character_to_the_vehicle() -> void:
	var car := _car(false, true)
	var seats := VehicleFixtures.seats_of(car)
	var person := _person(true)
	var walker := VehicleFixtures.find(person, CharacterController) as CharacterController
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(walker.take_control())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_ON_FOOT)

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)

	assert_ok(interactor.begin(VehicleFixtures.find(car, InteractionComponent)))

	assert_true(seats.contains(person))
	assert_false(walker.is_controlling(), "the character let go")
	assert_true(driver.is_controlling(), "and the vehicle took over")
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER)


func test_getting_out_hands_control_back() -> void:
	var car := _car(false, true)
	var seats := VehicleFixtures.seats_of(car)
	var person := _person(true)
	var walker := VehicleFixtures.find(person, CharacterController) as CharacterController
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	assert_ok(walker.take_control())

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)
	var interaction := VehicleFixtures.find(car, InteractionComponent) as InteractionComponent

	assert_ok(interactor.begin(interaction))
	assert_ok(interactor.begin(interaction))

	assert_false(seats.contains(person))
	assert_true(walker.is_controlling(), "the character has its context back")
	assert_false(driver.is_controlling())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_ON_FOOT)


func test_the_context_stack_does_not_grow_across_a_round_trip() -> void:
	# The leak this guards is one context deeper per journey, which after ten
	# car rides is a stack nothing can pop back out of.
	var car := _car(false, true)
	var person := _person(true)
	var walker := VehicleFixtures.find(person, CharacterController) as CharacterController
	assert_ok(walker.take_control())
	var depth := router.get_depth()

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)
	var interaction := VehicleFixtures.find(car, InteractionComponent) as InteractionComponent

	for trip in 5:
		assert_ok(interactor.begin(interaction))
		assert_ok(interactor.begin(interaction))
	assert_eq(router.get_depth(), depth)


func test_an_npc_getting_in_stops_thinking_and_gets_its_mind_back() -> void:
	var car := _car(false, true)
	var person := VehicleFixtures.occupant("Npc", false, true)
	add_test_node(person)
	VehicleFixtures.assemble(person, core)
	var brain := VehicleFixtures.find(person, AIControllerComponent) as AIControllerComponent
	assert_true(brain.is_active())

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)
	var interaction := VehicleFixtures.find(car, InteractionComponent) as InteractionComponent

	assert_ok(interactor.begin(interaction))
	assert_false(brain.is_active(), "an NPC that got in stops walking about")
	assert_ok(interactor.begin(interaction))
	assert_true(brain.is_active(), "and gets its mind back on the way out")


func test_a_player_getting_in_switches_the_traffic_ai_off() -> void:
	var car := _car(true, true)
	var brain := VehicleFixtures.find(car, VehicleAIDriver) as VehicleAIDriver
	var person := _person(true)

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)
	var interaction := VehicleFixtures.find(car, InteractionComponent) as InteractionComponent

	assert_ok(interactor.begin(interaction))
	assert_false(brain.is_active(), "the car stops driving itself")
	assert_ok(interactor.begin(interaction))
	assert_true(brain.is_active(), "and resumes when abandoned")


func test_a_passenger_does_not_take_the_wheel() -> void:
	var car := _car(false, true)
	var driver := VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	var person := _person(true)

	VehicleFixtures.interactable(
		car, [VehicleFixtures.enter_interaction(&"seat.passenger0")]
	)
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)

	assert_ok(interactor.begin(VehicleFixtures.find(car, InteractionComponent)))
	assert_true(VehicleFixtures.seats_of(car).contains(person))
	assert_false(driver.is_controlling(), "riding is not driving")


func test_a_plain_person_with_no_controller_still_gets_in() -> void:
	# Rule 31 again: possession is a series of optional handovers, and an
	# entity missing every one of them boards perfectly well.
	var car := _car()
	var person := _person()

	VehicleFixtures.interactable(car, [VehicleFixtures.enter_interaction()])
	VehicleFixtures.assemble(car, core)
	var interactor := VehicleFixtures.interactor_on(person)
	VehicleFixtures.assemble(person, core)

	assert_ok(interactor.begin(VehicleFixtures.find(car, InteractionComponent)))
	assert_true(VehicleFixtures.seats_of(car).contains(person))


func test_pressing_enter_on_something_that_is_not_a_vehicle_is_refused() -> void:
	var person := _person()
	var context := InteractionContext.create(person, person)
	assert_err(EnterVehicleAction.new().execute(context), &"vehicle.no_seats")


func test_a_full_car_greys_the_prompt_out_rather_than_letting_you_press_it() -> void:
	var car := _car()
	var seats := VehicleFixtures.seats_of(car)
	for index in 2:
		var rider := VehicleFixtures.occupant("Rider%d" % index)
		add_test_node(rider)
		VehicleFixtures.assemble(rider, core)
		assert_ok(seats.enter(rider))

	var latecomer := _person()
	var context := InteractionContext.create(latecomer, car)
	assert_err(EnterVehicleAction.new().can_execute(context), &"seat.full")
