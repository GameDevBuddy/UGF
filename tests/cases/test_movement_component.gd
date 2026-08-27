extends FrameworkTestCase
## Covers MovementComponent: the command API every driver shares, stance
## ownership, jumping across frames, and what movement puts in a save.

var entity: Node = null
var component: MovementComponent = null
var profile: MovementProfile = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	profile = MovementProfile.new()
	profile.walk_speed = 4.0
	profile.sprint_speed = 8.0
	profile.crouch_speed = 2.0
	profile.acceleration = 40.0
	profile.deceleration = 55.0
	profile.jump_velocity = 5.0
	profile.gravity = 18.0
	component = MovementComponent.new()
	component.profile_override = profile
	entity.add_child(component)
	component.initialize(EntityContext.create(entity))


func _walk_forward(seconds: float = 1.0, step: float = 0.05) -> void:
	component.set_move_direction(Vector3.FORWARD)
	var elapsed := 0.0
	while elapsed < seconds:
		component.tick(step)
		elapsed += step


# --- Configuration --------------------------------------------------------

func test_the_override_profile_wins() -> void:
	assert_eq(component.get_profile(), profile)


func test_a_component_with_no_profile_is_inert() -> void:
	# Not an error. A definition with no movement profile is a statue, and a
	# statue should do nothing rather than fail to load (rule 31).
	var inert := MovementComponent.new()
	entity.add_child(inert)
	inert.initialize(EntityContext.create(entity))
	inert.set_move_direction(Vector3.FORWARD)
	inert.tick(1.0)
	assert_eq(inert.get_velocity(), Vector3.ZERO)
	assert_null(inert.get_profile())


func test_the_profile_comes_from_the_definition_when_there_is_no_override() -> void:
	# Read by property name, so Locomotion never imports a character type.
	var definition := CharacterDefinition.new()
	definition.id = &"character.guard"
	definition.movement = profile
	var from_data := MovementComponent.new()
	entity.add_child(from_data)
	from_data.initialize(EntityContext.create(entity, definition))
	assert_eq(from_data.get_profile(), profile)


func test_nothing_ticks_until_something_asks_it_to() -> void:
	# Rule 26. With no body to drive there is nothing to process.
	assert_false(component.is_physics_processing())


# --- Movement -------------------------------------------------------------

func test_walking_reaches_the_walk_speed() -> void:
	_walk_forward()
	assert_almost_eq(component.get_planar_speed(), 4.0, 0.0001)


func test_walking_goes_the_way_it_was_asked_to() -> void:
	_walk_forward()
	assert_true(component.get_velocity().z < 0.0, "forward is -Z")


func test_sprinting_is_faster_than_walking() -> void:
	component.set_sprinting(true)
	_walk_forward()
	assert_almost_eq(component.get_planar_speed(), 8.0, 0.0001)


func test_crouching_is_slower_than_walking() -> void:
	component.set_crouching(true)
	_walk_forward()
	assert_almost_eq(component.get_planar_speed(), 2.0, 0.0001)


func test_stop_clears_intent_without_stopping_dead() -> void:
	_walk_forward()
	component.stop()
	component.tick(0.01)
	var speed := component.get_planar_speed()
	assert_true(speed < 4.0, "it is slowing")
	assert_true(speed > 0.0, "but it did not stop dead")


func test_halt_zeroes_everything() -> void:
	_walk_forward()
	component.halt()
	assert_eq(component.get_velocity(), Vector3.ZERO)
	assert_false(component.is_moving())


func test_move_input_and_a_direction_agree() -> void:
	# The player's path and an AI's path into the same component.
	component.set_move_input(Vector2(0.0, -1.0))
	assert_almost_eq(component.get_intent().get_planar_direction().z, -1.0, 0.0001)


func test_speed_ratio_is_relative_to_the_fastest_stance() -> void:
	_walk_forward()
	assert_almost_eq(component.get_speed_ratio(), 0.5, 0.0001, "4 of a possible 8")


func test_speed_ratio_is_zero_without_a_profile() -> void:
	var inert := MovementComponent.new()
	entity.add_child(inert)
	assert_almost_eq(inert.get_speed_ratio(), 0.0)


# --- Stance ---------------------------------------------------------------

func test_stance_changes_are_announced_once() -> void:
	var seen: Array = []
	component.stance_changed.connect(
		func(s: bool, c: bool) -> void: seen.append([s, c])
	)
	component.set_sprinting(true)
	component.tick(0.05)
	component.tick(0.05)
	assert_size(seen, 1, "the second tick changed nothing")
	assert_eq(seen[0], [true, false])


func test_the_component_refuses_a_stance_its_profile_forbids() -> void:
	profile.can_sprint = false
	component.set_sprinting(true)
	component.tick(0.05)
	assert_false(component.is_sprinting(), "one owner, one answer (rule 4)")


func test_movement_changed_fires_on_the_edges() -> void:
	var seen: Array[bool] = []
	component.movement_changed.connect(func(m: bool) -> void: seen.append(m))
	component.set_move_direction(Vector3.FORWARD)
	component.tick(0.05)
	component.tick(0.05)
	component.stop()
	component.tick(0.05)
	assert_eq(seen, [true, false] as Array[bool])


# --- Semantic state -------------------------------------------------------

func test_stance_is_mirrored_onto_semantic_state() -> void:
	# The tags advertise what this component owns; they are not a second
	# authority on it (rule 4).
	var state := SemanticState.new()
	entity.add_child(state)
	component.semantic_state = state

	component.set_sprinting(true)
	component.tick(0.05)
	assert_true(state.has_state(GameplayNames.STATE_SPRINTING))

	component.set_sprinting(false)
	component.tick(0.05)
	assert_false(state.has_state(GameplayNames.STATE_SPRINTING))


func test_airborne_is_mirrored_onto_semantic_state() -> void:
	var state := SemanticState.new()
	entity.add_child(state)
	component.semantic_state = state

	component.tick(0.05)
	assert_false(state.has_state(GameplayNames.STATE_AIRBORNE))
	component.request_jump()
	component.tick(0.05)
	assert_true(state.has_state(GameplayNames.STATE_AIRBORNE))


func test_movement_works_without_a_semantic_state() -> void:
	_walk_forward()
	assert_almost_eq(component.get_planar_speed(), 4.0, 0.0001)


# --- Jumping --------------------------------------------------------------

func test_a_requested_jump_fires_on_the_next_tick() -> void:
	var fired := [0]
	component.jumped.connect(func() -> void: fired[0] += 1)
	component.request_jump()
	component.tick(0.05)
	assert_eq(fired[0], 1)
	assert_almost_eq(component.get_velocity().y, 5.0, 0.0001)
	assert_true(component.is_airborne())


func test_a_jump_is_not_repeated_on_later_ticks() -> void:
	var fired := [0]
	component.jumped.connect(func() -> void: fired[0] += 1)
	component.request_jump()
	component.tick(0.05)
	component.tick(0.05)
	component.tick(0.05)
	assert_eq(fired[0], 1, "one press, one jump")


func test_a_profile_that_cannot_jump_does_not() -> void:
	profile.can_jump = false
	component.request_jump()
	component.tick(0.05)
	assert_false(component.is_airborne())


func test_what_goes_up_comes_down_and_reports_landing() -> void:
	var landings: Array[float] = []
	component.landed.connect(func(speed: float) -> void: landings.append(speed))
	component.request_jump()
	for _i in range(200):
		component.tick(0.02)
		if not landings.is_empty():
			break
	assert_size(landings, 1, "it landed exactly once")
	assert_true(landings[0] > 0.0, "and it was falling when it did")
	assert_true(component.is_on_floor())


func test_a_stale_jump_request_expires() -> void:
	# Otherwise a press during a fall fires seconds later, on landing.
	profile.jump_buffer = 0.1
	var fired := [0]
	component.jumped.connect(func() -> void: fired[0] += 1)
	profile.can_jump = false
	component.request_jump()
	component.tick(0.2)
	profile.can_jump = true
	component.tick(0.05)
	assert_eq(fired[0], 0)


# --- Persistence ----------------------------------------------------------

func test_movement_is_persistent() -> void:
	assert_true(component.is_persistent())


func test_stance_and_velocity_round_trip() -> void:
	component.set_sprinting(true)
	_walk_forward()
	var captured := component.capture_state()

	var restored := MovementComponent.new()
	restored.profile_override = profile
	entity.add_child(restored)
	restored.initialize(EntityContext.create(entity))
	restored.restore_state(captured)

	assert_true(restored.is_sprinting())
	assert_almost_eq(restored.get_planar_speed(), 8.0, 0.0001, "sprinting, so 8")


func test_restore_tolerates_a_save_written_before_these_fields_existed() -> void:
	component.restore_state({})
	assert_false(component.is_sprinting())
	assert_false(component.is_crouching())


func test_position_is_not_saved_here() -> void:
	# The entity record owns the transform. Two owners for one fact is how a
	# save file ends up disagreeing with itself (rule 4, rule 22).
	var captured := component.capture_state()
	assert_has_not(captured.keys(), "position")
	assert_has_not(captured.keys(), "transform")


# --- Rule 14: every driver is equal --------------------------------------

func test_an_ai_style_intent_produces_the_same_result_as_player_input() -> void:
	# The M2 exit gate, and the promise M7 depends on: an AI brain setting
	# intent wholesale and a controller feeding input vectors reach the same
	# velocity, because there is only one path through this component.
	var ai_entity := add_test_node(Node.new())
	var ai_driven := MovementComponent.new()
	ai_driven.profile_override = profile
	ai_entity.add_child(ai_driven)
	ai_driven.initialize(EntityContext.create(ai_entity))

	component.set_move_input(Vector2(0.0, -1.0))
	ai_driven.set_intent(MovementIntent.create(Vector3.FORWARD))

	for _i in range(20):
		component.tick(0.05)
		ai_driven.tick(0.05)

	assert_eq(ai_driven.get_velocity(), component.get_velocity())


func test_an_ai_can_jump_through_the_same_api() -> void:
	var fired := [0]
	component.jumped.connect(func() -> void: fired[0] += 1)
	component.set_intent(MovementIntent.create(Vector3.ZERO, false, false, true))
	component.tick(0.05)
	assert_eq(fired[0], 1)


func test_setting_a_null_intent_changes_nothing() -> void:
	component.set_move_direction(Vector3.FORWARD)
	component.set_intent(null)
	assert_almost_eq(component.get_intent().get_planar_direction().z, -1.0, 0.0001)
