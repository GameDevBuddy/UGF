extends FrameworkTestCase
## Covers InputContext as a definition, and the six standard contexts.


func test_context_is_a_definition() -> void:
	# It is authored content with a stable id, which is what makes a project's
	# own contexts first-class rather than second-class.
	var context := InputContexts.on_foot()
	assert_true(context is FrameworkDefinition)
	assert_eq(context.id, GameplayNames.INPUT_CONTEXT_ON_FOOT)


func test_allows_reports_membership() -> void:
	var context := InputContext.create(&"input.test", [GameplayNames.ACTION_JUMP])
	assert_true(context.allows(GameplayNames.ACTION_JUMP))
	assert_false(context.allows(GameplayNames.ACTION_SPRINT))


func test_create_copies_the_action_array() -> void:
	# Sharing the caller's array would let one context's edit reach another.
	var actions: Array[StringName] = [GameplayNames.ACTION_JUMP]
	var context := InputContext.create(&"input.test", actions)
	actions.append(GameplayNames.ACTION_SPRINT)
	assert_size(context.actions, 1)


func test_blocks_lower_defaults_to_modal() -> void:
	var context := InputContext.create(&"input.test", [GameplayNames.ACTION_JUMP])
	assert_true(context.blocks_lower)
	assert_false(context.suppresses_control)


func test_validation_flags_an_empty_action_entry() -> void:
	var context := InputContext.create(&"input.test", [GameplayNames.ACTION_JUMP, &""])
	var result := context.validate()
	assert_true(result.has_warnings())


func test_validation_flags_a_context_that_does_nothing() -> void:
	var context := InputContext.create(&"input.test", [])
	var result := context.validate()
	assert_true(result.has_warnings())
	assert_true(result.format_report().contains("does nothing"))


func test_a_suppressing_context_may_list_no_actions() -> void:
	# Disabled is empty on purpose: its whole job is to be empty.
	var result := InputContexts.disabled().validate()
	assert_false(result.has_errors())
	assert_false(result.has_warnings())


func test_validation_still_requires_an_id() -> void:
	var context := InputContext.new()
	context.actions = [GameplayNames.ACTION_JUMP]
	assert_true(context.validate().has_errors())


func test_on_foot_carries_the_full_movement_set() -> void:
	var context := InputContexts.on_foot()
	assert_true(context.allows(GameplayNames.ACTION_MOVE_FORWARD))
	assert_true(context.allows(GameplayNames.ACTION_MOVE_BACK))
	assert_true(context.allows(GameplayNames.ACTION_MOVE_LEFT))
	assert_true(context.allows(GameplayNames.ACTION_MOVE_RIGHT))
	assert_true(context.allows(GameplayNames.ACTION_JUMP))
	assert_true(context.allows(GameplayNames.ACTION_SPRINT))
	assert_true(context.allows(GameplayNames.ACTION_CROUCH))


func test_driving_reuses_the_movement_action_names() -> void:
	# Possession swaps the listener, not the vocabulary: a vehicle reads
	# throttle and steering off the same semantic axes.
	var context := InputContexts.vehicle_driver()
	assert_true(context.allows(GameplayNames.ACTION_MOVE_FORWARD))
	assert_true(context.allows(GameplayNames.ACTION_MOVE_LEFT))
	assert_false(context.allows(GameplayNames.ACTION_SPRINT), "no sprinting a car")


func test_a_passenger_can_only_get_out() -> void:
	var context := InputContexts.vehicle_passenger()
	assert_size(context.actions, 1)
	assert_true(context.allows(GameplayNames.ACTION_INTERACT))


func test_modal_contexts_suppress_control() -> void:
	assert_true(InputContexts.ui().suppresses_control)
	assert_true(InputContexts.dialogue().suppresses_control)
	assert_true(InputContexts.disabled().suppresses_control)


func test_gameplay_contexts_do_not_suppress_control() -> void:
	assert_false(InputContexts.on_foot().suppresses_control)
	assert_false(InputContexts.vehicle_driver().suppresses_control)


func test_dialogue_still_lets_you_advance_it() -> void:
	assert_true(InputContexts.dialogue().allows(GameplayNames.ACTION_INTERACT))
	assert_false(InputContexts.disabled().allows(GameplayNames.ACTION_INTERACT))


func test_all_returns_every_standard_context_with_distinct_ids() -> void:
	var contexts := InputContexts.all()
	assert_size(contexts, 6)
	var ids: Array[StringName] = []
	for context in contexts:
		assert_has_not(ids, context.id)
		ids.append(context.id)


func test_every_standard_context_validates_clean() -> void:
	# Content validation is a feature (rule 27), and the framework's own
	# content should be the first thing it passes on.
	for context in InputContexts.all():
		var result := context.validate()
		assert_false(
			result.has_errors(), "%s: %s" % [context.id, result.format_report()]
		)
