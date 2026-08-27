extends FrameworkTestCase
## Covers AnimationAdapter: what it writes, when it fires a one-shot, and the
## fact that it never writes back.

var entity: Node = null
var movement: MovementComponent = null
var adapter: AnimationAdapter = null
var profile: AnimationProfile = null
var movement_profile: MovementProfile = null


func before_each() -> void:
	entity = add_test_node(Node.new())

	movement_profile = MovementProfile.new()
	movement_profile.walk_speed = 4.0
	movement_profile.sprint_speed = 8.0
	movement_profile.acceleration = 40.0
	movement_profile.jump_velocity = 5.0
	movement = MovementComponent.new()
	movement.profile_override = movement_profile
	entity.add_child(movement)
	movement.initialize(EntityContext.create(entity))

	profile = AnimationProfile.new()
	profile.speed_parameter = "parameters/locomotion/blend_position"
	profile.airborne_parameter = "parameters/airborne/active"
	profile.crouch_parameter = "parameters/crouch/active"
	profile.sprint_parameter = "parameters/sprint/active"
	profile.moving_parameter = "parameters/moving/active"
	profile.jump_request_parameter = "parameters/jump/request"
	profile.land_request_parameter = "parameters/land/request"
	profile.land_request_min_speed = 4.0

	adapter = AnimationAdapter.new()
	adapter.profile_override = profile
	adapter.movement = movement
	adapter.auto_tick = false
	entity.add_child(adapter)
	adapter.initialize(EntityContext.create(entity))


func _walk(seconds: float = 1.0) -> void:
	movement.set_move_direction(Vector3.FORWARD)
	var elapsed := 0.0
	while elapsed < seconds:
		movement.tick(0.05)
		elapsed += 0.05


# --- Writing --------------------------------------------------------------

func test_it_writes_the_speed_ratio() -> void:
	_walk()
	adapter.apply()
	assert_almost_eq(
		adapter.get_applied_value(profile.speed_parameter), 0.5, 0.0001, "4 of 8"
	)


func test_it_writes_the_stance_flags() -> void:
	movement.set_crouching(true)
	movement.tick(0.05)
	adapter.apply()
	assert_true(adapter.get_applied_value(profile.crouch_parameter))
	assert_false(adapter.get_applied_value(profile.sprint_parameter))


func test_it_writes_whether_the_entity_is_moving() -> void:
	adapter.apply()
	assert_false(adapter.get_applied_value(profile.moving_parameter))
	_walk(0.1)
	adapter.apply()
	assert_true(adapter.get_applied_value(profile.moving_parameter))


func test_it_writes_airborne_state() -> void:
	movement.request_jump()
	movement.tick(0.05)
	adapter.apply()
	assert_true(adapter.get_applied_value(profile.airborne_parameter))


func test_an_unset_parameter_is_never_written() -> void:
	# A character with a two-state tree and one with a full blend space share
	# this adapter; the difference is which paths the profile fills in.
	adapter.apply()
	assert_has_not(adapter.get_applied().keys(), "")
	assert_has_not(adapter.get_applied().keys(), profile.speed_metres_parameter)
	assert_size(adapter.get_applied(), 5, "the five paths this profile sets")


func test_it_writes_speed_in_metres_when_asked_to() -> void:
	profile.speed_metres_parameter = "parameters/speed_mps"
	_walk()
	adapter.apply()
	assert_almost_eq(
		adapter.get_applied_value("parameters/speed_mps"), 4.0, 0.0001
	)


func test_the_speed_parameter_can_be_blended_rather_than_snapped() -> void:
	profile.speed_blend_rate = 1.0
	_walk()
	adapter.apply(0.1)
	assert_almost_eq(
		adapter.get_applied_value(profile.speed_parameter), 0.1, 0.0001, "part way"
	)


func test_applied_parameters_are_announced() -> void:
	var seen: Array = []
	adapter.parameters_applied.connect(
		func(parameters: Dictionary) -> void: seen.append(parameters)
	)
	adapter.apply()
	assert_size(seen, 1)
	assert_true(seen[0].has(profile.speed_parameter))


func test_get_applied_hands_back_a_copy() -> void:
	adapter.apply()
	var snapshot := adapter.get_applied()
	snapshot.clear()
	assert_false(adapter.get_applied().is_empty(), "the adapter kept its own")


# --- One-shots ------------------------------------------------------------

func test_jumping_fires_the_jump_one_shot() -> void:
	movement.request_jump()
	movement.tick(0.05)
	assert_eq(
		adapter.get_applied_value(profile.jump_request_parameter),
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func test_a_hard_landing_fires_the_landing_one_shot() -> void:
	movement.request_jump()
	for _i in range(200):
		movement.tick(0.02)
		if adapter.get_applied_value(profile.land_request_parameter) != null:
			break
	assert_true(movement.is_on_floor(), "it came back down")
	assert_eq(
		adapter.get_applied_value(profile.land_request_parameter),
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func test_a_gentle_landing_does_not() -> void:
	# Stepping off a kerb should not play a heavy landing.
	profile.land_request_min_speed = 1000.0
	movement.request_jump()
	for _i in range(200):
		movement.tick(0.02)
		if movement.is_on_floor():
			break
	assert_null(adapter.get_applied_value(profile.land_request_parameter))


func test_an_unmapped_one_shot_is_simply_not_fired() -> void:
	var unmapped := "parameters/jump/request"
	profile.jump_request_parameter = ""
	movement.request_jump()
	movement.tick(0.05)
	assert_true(movement.is_airborne(), "it jumped")
	assert_has_not(adapter.get_applied().keys(), unmapped)
	assert_has_not(adapter.get_applied().keys(), "")


# --- Rule 21: presentation observes, it never owns -----------------------

func test_the_adapter_never_writes_back_to_movement() -> void:
	# The whole safety argument for this component: the worst bug it can cause
	# is a wrong-looking animation, never a wrong gameplay state.
	_walk()
	var velocity_before := movement.get_velocity()
	var sprinting_before := movement.is_sprinting()

	adapter.apply(0.1)
	adapter.apply(0.1)

	assert_eq(movement.get_velocity(), velocity_before)
	assert_eq(movement.is_sprinting(), sprinting_before)
	assert_true(movement.is_moving(), "and it is still the mover's own answer")


func test_the_adapter_holds_no_state_a_save_would_want() -> void:
	assert_false(adapter.is_persistent())
	assert_empty(adapter.capture_state())


# --- Degradation ----------------------------------------------------------

func test_it_works_with_no_animation_tree() -> void:
	# Everything above ran without one. Stated explicitly because it is the
	# reason this suite can exist at all.
	assert_false(adapter.has_animation_tree())
	adapter.apply()
	assert_false(adapter.get_applied().is_empty())


func test_it_is_inert_with_no_profile() -> void:
	var bare := AnimationAdapter.new()
	bare.movement = movement
	entity.add_child(bare)
	bare.initialize(EntityContext.create(entity))
	bare.apply()
	assert_empty(bare.get_applied())
	assert_null(bare.get_profile())


func test_it_is_inert_with_nothing_to_observe() -> void:
	var bare := AnimationAdapter.new()
	bare.profile_override = profile
	entity.add_child(bare)
	bare.initialize(EntityContext.create(entity))
	bare.apply()
	assert_empty(bare.get_applied())
	assert_false(bare.is_processing(), "and it costs nothing to have (rule 26)")


func test_the_profile_comes_from_the_definition() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.guard"
	definition.animation = profile
	var from_data := AnimationAdapter.new()
	from_data.movement = movement
	entity.add_child(from_data)
	from_data.initialize(EntityContext.create(entity, definition))
	assert_eq(from_data.get_profile(), profile)


# --- Profile validation ---------------------------------------------------

func test_a_profile_that_maps_nothing_is_a_warning() -> void:
	var empty := AnimationProfile.new()
	assert_true(empty.validate().has_warnings())


func test_a_configured_profile_validates_clean() -> void:
	assert_false(profile.validate().has_errors())
	assert_false(profile.validate().has_warnings())


func test_a_negative_blend_rate_is_an_error() -> void:
	profile.speed_blend_rate = -1.0
	assert_true(profile.validate().has_errors())


func test_configured_parameters_lists_only_what_is_set() -> void:
	assert_size(profile.get_configured_parameters(), 7)
	profile.speed_metres_parameter = "parameters/speed_mps"
	assert_size(profile.get_configured_parameters(), 8)
