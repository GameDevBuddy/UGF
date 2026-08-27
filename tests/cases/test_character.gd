extends FrameworkTestCase
## Covers CharacterDefinition and CharacterController, and holds the M2 exit
## gate: walk, sprint, crouch and jump from input; a clean input-context
## switch; and an AI driving the same character through the same commands.

const FakeInputSource := preload("res://tests/support/fake_input_source.gd")

var entity: Node3D = null
var movement: MovementComponent = null
var controller: CharacterController = null
var router: InputRouter = null
var source: RefCounted = null
var definition: CharacterDefinition = null


func before_each() -> void:
	entity = add_test_node(Node3D.new()) as Node3D

	var movement_profile := MovementProfile.new()
	movement_profile.walk_speed = 4.0
	movement_profile.sprint_speed = 8.0
	movement_profile.crouch_speed = 2.0
	movement_profile.acceleration = 40.0
	movement_profile.deceleration = 55.0
	movement_profile.jump_velocity = 5.0
	movement_profile.gravity = 18.0

	definition = CharacterDefinition.new()
	definition.id = &"character.test"
	definition.display_name = "Test Character"
	definition.movement = movement_profile
	# EntityDefinition requires a scene to be spawnable; validation only checks
	# that one is present, so an empty PackedScene is enough to isolate the
	# character-specific checks below from that inherited error.
	definition.scene = PackedScene.new()

	source = FakeInputSource.new()
	router = InputRouter.new(source)
	add_test_node(router)

	movement = MovementComponent.new()
	entity.add_child(movement)

	controller = CharacterController.new()
	controller.movement = movement
	entity.add_child(controller)

	movement.initialize(EntityContext.create(entity, definition))
	controller.set_router(router)
	controller.initialize(EntityContext.create(entity, definition))


func _drive(seconds: float = 1.0) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		controller.drive(0.05)
		movement.tick(0.05)
		elapsed += 0.05


# --- Definition -----------------------------------------------------------

func test_a_character_is_an_entity_definition() -> void:
	assert_true(definition is EntityDefinition)
	assert_true(definition is FrameworkDefinition)


func test_a_character_with_no_movement_profile_is_flagged() -> void:
	var statue := CharacterDefinition.new()
	statue.id = &"character.statue"
	statue.display_name = "Statue"
	statue.scene = PackedScene.new()
	var result := statue.validate()
	assert_true(result.has_warnings())
	assert_false(result.has_errors(), "a statue is expressible, just unusual")


func test_definition_validation_reaches_into_its_profiles() -> void:
	# A character whose movement profile is broken is a broken character, and
	# the report should say so without the author opening the sub-resource.
	definition.movement.acceleration = 0.0
	var result := definition.validate()
	assert_true(result.has_errors())
	assert_true(result.format_report().contains("acceleration"))


func test_a_scene_is_still_required() -> void:
	# Inherited from EntityDefinition: a character that cannot be spawned is
	# an error, not a warning.
	assert_false(definition.validate().has_errors(), "the fixture is sound")
	definition.scene = null
	var result := definition.validate()
	assert_true(result.has_errors())
	assert_true(result.format_report().contains("cannot be spawned"))


func test_role_is_a_tag_not_a_class() -> void:
	# Guard, vendor and civilian are the same type with different data
	# (rule 5, rule 13).
	var guard := CharacterDefinition.new()
	guard.id = &"character.guard"
	guard.tags = [&"role.guard", &"character.human"]
	var vendor := CharacterDefinition.new()
	vendor.id = &"character.vendor"
	vendor.tags = [&"role.vendor", &"character.human"]

	assert_eq(guard.get_script(), vendor.get_script(), "one class")
	assert_true(guard.has_tag(&"role.guard"))
	assert_false(vendor.has_tag(&"role.guard"))
	assert_true(vendor.has_all_tags([&"role.vendor", &"character.human"]))


# --- Possession -----------------------------------------------------------

func test_taking_control_pushes_the_character_context() -> void:
	assert_ok(controller.take_control())
	assert_true(controller.is_controlling())
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_ON_FOOT)


func test_releasing_control_removes_that_context_again() -> void:
	controller.take_control()
	assert_ok(controller.release_control())
	assert_false(controller.is_controlling())
	assert_eq(router.get_depth(), 0)


func test_control_changes_are_announced() -> void:
	var seen: Array[bool] = []
	controller.control_changed.connect(func(c: bool) -> void: seen.append(c))
	controller.take_control()
	controller.release_control()
	assert_eq(seen, [true, false] as Array[bool])


func test_taking_control_twice_fails() -> void:
	controller.take_control()
	assert_err(controller.take_control(), &"controller.already_controlling")
	assert_eq(router.get_depth(), 1, "and did not push a second context")


func test_releasing_without_control_fails() -> void:
	assert_err(controller.release_control(), &"controller.not_controlling")


func test_a_controller_with_no_mover_refuses_control() -> void:
	var orphan := CharacterController.new()
	entity.add_child(orphan)
	orphan.set_router(router)
	orphan.initialize(EntityContext.create(entity, definition))
	assert_err(orphan.take_control(), &"controller.no_movement")


func test_a_definition_can_name_its_own_input_context() -> void:
	var driving := InputContexts.vehicle_driver()
	definition.input_context = driving
	var custom := CharacterController.new()
	custom.movement = movement
	entity.add_child(custom)
	custom.set_router(router)
	custom.initialize(EntityContext.create(entity, definition))

	custom.take_control()
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER)


func test_handing_control_between_two_characters_leaves_one_driver() -> void:
	# The M2 exit gate for input contexts, and the shape possession takes in
	# M13 when the second driver is a vehicle rather than a character.
	var second_entity := add_test_node(Node3D.new()) as Node3D
	var second_movement := MovementComponent.new()
	second_entity.add_child(second_movement)
	second_movement.initialize(EntityContext.create(second_entity, definition))
	var second := CharacterController.new()
	second.movement = second_movement
	second_entity.add_child(second)
	second.set_router(router)
	second.initialize(EntityContext.create(second_entity, definition))

	controller.take_control()
	controller.release_control()
	second.take_control()

	assert_false(controller.is_controlling())
	assert_true(second.is_controlling())
	assert_eq(router.get_depth(), 1, "exactly one context, not two stacked")

	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	controller.drive(0.05)
	second.drive(0.05)
	movement.tick(0.05)
	second_movement.tick(0.05)

	assert_eq(movement.get_velocity(), Vector3.ZERO, "the released one stayed put")
	assert_true(second_movement.get_planar_speed() > 0.0, "the new one moved")


func test_releasing_control_stops_a_character_mid_stride() -> void:
	# Without this a character handed over mid-walk keeps walking, because the
	# last intent it was given is still set.
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())

	controller.release_control()
	movement.tick(0.05)
	assert_false(movement.is_moving())


# --- Driving --------------------------------------------------------------

func test_walking_from_input() -> void:
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_almost_eq(movement.get_planar_speed(), 4.0, 0.0001)
	assert_true(movement.get_velocity().z < 0.0, "forward")


func test_sprinting_from_input() -> void:
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	source.hold(GameplayNames.ACTION_SPRINT)
	_drive()
	assert_true(movement.is_sprinting())
	assert_almost_eq(movement.get_planar_speed(), 8.0, 0.0001)


func test_crouching_from_input() -> void:
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	source.hold(GameplayNames.ACTION_CROUCH)
	_drive()
	assert_true(movement.is_crouching())
	assert_almost_eq(movement.get_planar_speed(), 2.0, 0.0001)


func test_jumping_from_input() -> void:
	controller.take_control()
	source.press(GameplayNames.ACTION_JUMP)
	controller.drive(0.05)
	movement.tick(0.05)
	assert_true(movement.is_airborne())
	assert_almost_eq(movement.get_velocity().y, 5.0, 0.0001)


func test_strafing_from_input() -> void:
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_RIGHT)
	_drive()
	assert_true(movement.get_velocity().x > 0.0)


func test_a_modal_context_stops_the_character_without_it_knowing_why() -> void:
	# The controller contains no knowledge of menus. A context push is the
	# whole mechanism.
	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())

	router.push_context(InputContexts.ui())
	controller.drive(0.05)
	movement.tick(0.05)
	assert_false(movement.is_moving())


func test_closing_the_menu_gives_control_back() -> void:
	controller.take_control()
	router.push_context(InputContexts.ui())
	controller.drive(0.05)
	movement.tick(0.05)

	router.pop_context()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())


func test_an_uncontrolled_controller_issues_nothing() -> void:
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_eq(movement.get_velocity(), Vector3.ZERO)


func test_movement_follows_the_camera_when_there_is_one() -> void:
	var camera_profile := CameraProfile.new()
	camera_profile.sensitivity = 0.01
	var camera := CameraAdapter.new()
	camera.profile_override = camera_profile
	entity.add_child(camera)
	camera.initialize(EntityContext.create(entity, definition))
	camera.set_look(PI * 0.5, 0.0)
	controller.camera = camera

	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()

	# Facing +90 degrees about Y, forward is -X.
	assert_true(movement.get_velocity().x < 0.0)
	assert_almost_eq(movement.get_velocity().z, 0.0, 0.001)


# --- Degradation ----------------------------------------------------------

func test_a_controller_with_no_input_service_refuses_control_cleanly() -> void:
	# A build without the Input module. The character is not broken by it,
	# it simply has no player (rule 31).
	var npc := CharacterController.new()
	npc.movement = movement
	entity.add_child(npc)
	npc.initialize(EntityContext.create(entity, definition))
	assert_err(npc.take_control(), &"controller.no_input_router")
	assert_false(npc.is_controlling())


func test_a_character_still_moves_with_no_controller_at_all() -> void:
	# The M2 exit gate for AI: the same public commands, no controller, no
	# input service, no camera. This is the API M7 will drive.
	movement.set_move_direction(Vector3.FORWARD)
	movement.set_sprinting(true)
	for _i in range(20):
		movement.tick(0.05)
	assert_almost_eq(movement.get_planar_speed(), 8.0, 0.0001)
	assert_false(controller.is_controlling(), "nobody was driving it")


func test_an_ai_and_a_player_reach_the_same_velocity() -> void:
	var ai_entity := add_test_node(Node3D.new()) as Node3D
	var ai_movement := MovementComponent.new()
	ai_entity.add_child(ai_movement)
	ai_movement.initialize(EntityContext.create(ai_entity, definition))

	controller.take_control()
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	ai_movement.set_intent(MovementIntent.create(Vector3.FORWARD))

	for _i in range(20):
		controller.drive(0.05)
		movement.tick(0.05)
		ai_movement.tick(0.05)

	assert_eq(ai_movement.get_velocity(), movement.get_velocity())


# --- Wiring ---------------------------------------------------------------

func test_the_router_can_be_found_through_the_core_service_registry() -> void:
	# The path a real game takes: the Input module registers the router, and
	# the controller resolves it from the core it was handed.
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	var entity_module: FrameworkModule = load(
		"res://addons/universal_gameplay/entity/entity_module.gd"
	).new()
	var input_module: FrameworkModule = load(
		"res://addons/universal_gameplay/input/input_module.gd"
	).new()
	assert_ok(core.register_module(entity_module))
	assert_ok(core.register_module(input_module))

	var resolved := CharacterController.new()
	resolved.movement = movement
	entity.add_child(resolved)
	resolved.initialize(EntityContext.create(entity, definition, core))

	assert_not_null(resolved.get_router())
	assert_eq(resolved.get_router(), core.get_service(GameplayNames.SERVICE_INPUT))
	assert_ok(resolved.take_control())


func test_an_injected_router_survives_initialisation() -> void:
	# Split-screen hands each controller its own router; resolving over the
	# top of one would quietly put both players back on the same router.
	var injected := InputRouter.new(FakeInputSource.new())
	add_test_node(injected)
	var split := CharacterController.new()
	split.movement = movement
	entity.add_child(split)
	split.set_router(injected)
	split.initialize(EntityContext.create(entity, definition))
	assert_eq(split.get_router(), injected)


# --- Interaction ----------------------------------------------------------
#
# The controller's job here is only to turn a button into a call. That the
# interaction itself works is test_interactor_component.gd's business; what
# these prove is that the wire exists, because a disconnected interact button
# fails silently and everything else about the character still works.

func _wire_interactor() -> InteractorComponent:
	var profile := InteractorProfile.new()
	profile.auto_focus = false

	var interactor := InteractorComponent.new()
	interactor.auto_tick = false
	interactor.profile_override = profile
	entity.add_child(interactor)
	interactor.initialize(EntityContext.create(entity, definition))
	controller.interactor = interactor
	return interactor


func _door(interaction: InteractionDefinition) -> InteractionComponent:
	var door := add_test_node(InteractionFixtures.target([interaction]))
	InteractionFixtures.assemble(door)
	return InteractionFixtures.interaction_of(door)


func _is_open(interaction: InteractionComponent) -> bool:
	var state := InteractionFixtures.state_of(interaction.get_entity_root())
	return state.has_state(GameplayNames.STATE_OPEN)


func test_the_interact_button_runs_the_focused_interaction() -> void:
	var interactor := _wire_interactor()
	var door := _door(InteractionFixtures.door())
	interactor.set_focus(door)
	controller.take_control()

	source.press(GameplayNames.ACTION_INTERACT)
	controller.drive(0.05)
	assert_true(_is_open(door))


func test_the_interact_button_does_nothing_with_nothing_in_reach() -> void:
	_wire_interactor()
	controller.take_control()
	source.press(GameplayNames.ACTION_INTERACT)
	controller.drive(0.05)
	assert_false(controller.interactor.is_busy())


func test_releasing_gives_up_a_timed_interaction() -> void:
	var timed := InteractionFixtures.timed(1.0)
	var action := ToggleStateAction.new()
	action.state = GameplayNames.STATE_OPEN
	timed.action = action

	var interactor := _wire_interactor()
	var door := _door(timed)
	interactor.set_focus(door)
	controller.take_control()

	source.press(GameplayNames.ACTION_INTERACT)
	controller.drive(0.05)
	assert_true(interactor.is_busy())

	source.advance_frame()
	interactor.tick(0.5)
	source.release(GameplayNames.ACTION_INTERACT)
	controller.drive(0.05)

	assert_false(interactor.is_busy())
	assert_false(_is_open(door))


func test_a_menu_gives_up_a_timed_interaction() -> void:
	var timed := InteractionFixtures.timed(1.0)
	var interactor := _wire_interactor()
	var door := _door(timed)
	interactor.set_focus(door)
	controller.take_control()

	source.press(GameplayNames.ACTION_INTERACT)
	controller.drive(0.05)
	assert_true(interactor.is_busy())

	router.push_context(InputContexts.ui())
	controller.drive(0.05)
	assert_false(interactor.is_busy())


func test_a_character_with_no_interactor_still_drives() -> void:
	# The Interaction module is optional; the interact button pressed on a
	# character that has none must not be an error (rule 31).
	controller.take_control()
	source.press(GameplayNames.ACTION_INTERACT)
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())


# --- Combat ---------------------------------------------------------------
#
# As with interaction, what these prove is that the wire exists. The attack
# pipeline itself is test_combat_component.gd's business; a disconnected
# attack button fails silently and everything else about the character works.

func _wire_combat() -> CombatComponent:
	var weapon := WeaponComponent.new()
	weapon.auto_tick = false
	weapon.profile_override = CombatFixtures.rifle(20.0, 5)
	entity.add_child(weapon)

	var combat := CombatComponent.new()
	combat.auto_tick = false
	combat.profile_override = CombatFixtures.combat_profile()
	combat.weapon = weapon
	entity.add_child(combat)

	var context := EntityContext.create(entity, definition)
	weapon.initialize(context)
	combat.initialize(context)
	combat.set_hit_provider(FakeHitProvider.new())
	controller.combat = combat
	return combat


func test_the_attack_button_fires() -> void:
	var combat := _wire_combat()
	controller.take_control()

	source.press(GameplayNames.ACTION_ATTACK)
	controller.drive(0.05)
	assert_eq(combat.weapon.get_magazine(), 4)


func test_releasing_stops_holding_the_trigger() -> void:
	var combat := _wire_combat()
	controller.take_control()

	source.press(GameplayNames.ACTION_ATTACK)
	controller.drive(0.05)
	assert_true(combat.is_holding())

	source.advance_frame()
	source.release(GameplayNames.ACTION_ATTACK)
	controller.drive(0.05)
	assert_false(combat.is_holding())


func test_the_reload_button_reloads() -> void:
	var combat := _wire_combat()
	controller.take_control()

	source.press(GameplayNames.ACTION_ATTACK)
	controller.drive(0.05)
	combat.weapon.tick(1.0)

	source.advance_frame()
	source.release(GameplayNames.ACTION_ATTACK)
	source.press(GameplayNames.ACTION_RELOAD)
	controller.drive(0.05)
	assert_true(combat.weapon.is_reloading())


func test_a_menu_releases_the_trigger() -> void:
	var combat := _wire_combat()
	controller.take_control()
	source.press(GameplayNames.ACTION_ATTACK)
	controller.drive(0.05)
	assert_true(combat.is_holding())

	router.push_context(InputContexts.ui())
	controller.drive(0.05)
	assert_false(combat.is_holding())


func test_a_character_with_no_combat_still_drives() -> void:
	# The Combat module is optional; the attack button pressed on a character
	# that has none must not be an error (rule 31).
	controller.take_control()
	source.press(GameplayNames.ACTION_ATTACK)
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())


# --- Possession -----------------------------------------------------------
#
# The handoff the M2 exit gate promised and M7 spends: an NPC a player takes
# over stops thinking, and gets its own mind back when they leave.

func _wire_ai() -> AIControllerComponent:
	var ai := AIControllerComponent.new()
	ai.auto_tick = false
	ai.role_override = AIFixtures.guard()
	entity.add_child(ai)
	ai.initialize(EntityContext.create(entity, definition))
	controller.ai = ai
	return ai


func test_taking_control_switches_the_ai_off() -> void:
	var ai := _wire_ai()
	assert_true(ai.is_active())
	controller.take_control()
	assert_false(ai.is_active())


func test_releasing_control_gives_the_npc_its_mind_back() -> void:
	var ai := _wire_ai()
	controller.take_control()
	controller.release_control()
	assert_true(ai.is_active())


func test_a_character_with_no_ai_is_controlled_normally() -> void:
	# The AI module is optional; possessing a character that has none must not
	# be an error (rule 31).
	assert_ok(controller.take_control())
	source.hold(GameplayNames.ACTION_MOVE_FORWARD)
	_drive()
	assert_true(movement.is_moving())
