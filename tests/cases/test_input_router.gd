extends FrameworkTestCase
## Covers InputRouter: the context stack, what each context lets through, and
## the difference between "not pressed" and "not listening".

const FakeInputSource := preload("res://tests/support/fake_input_source.gd")

var source: RefCounted = null
var router: InputRouter = null


func before_each() -> void:
	source = FakeInputSource.new()
	router = InputRouter.new(source)
	# The router is a Node. Parent it so the harness frees it with the test
	# rather than leaving it for the exit-time leak check to find.
	add_test_node(router)


func test_service_id() -> void:
	assert_eq(router.get_service_id(), GameplayNames.SERVICE_INPUT)


func test_empty_stack_hears_nothing() -> void:
	# Input is opt-in. A project that has not said who should be listening is
	# not served by the router guessing "everyone".
	source.press(GameplayNames.ACTION_JUMP)
	assert_eq(router.get_depth(), 0)
	assert_false(router.is_action_allowed(GameplayNames.ACTION_JUMP))
	assert_false(router.is_pressed(GameplayNames.ACTION_JUMP))


func test_pushed_context_makes_its_actions_audible() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_JUMP)
	assert_true(router.is_action_allowed(GameplayNames.ACTION_JUMP))
	assert_true(router.is_pressed(GameplayNames.ACTION_JUMP))


func test_action_outside_the_context_is_not_heard() -> void:
	router.push_context(InputContexts.vehicle_passenger())
	source.press(GameplayNames.ACTION_JUMP)
	assert_false(router.is_pressed(GameplayNames.ACTION_JUMP), "not in this context")
	source.press(GameplayNames.ACTION_INTERACT)
	assert_true(router.is_pressed(GameplayNames.ACTION_INTERACT), "but interact is")


func test_a_modal_context_hides_the_one_beneath_it() -> void:
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.ui())
	source.press(GameplayNames.ACTION_JUMP)
	assert_false(router.is_pressed(GameplayNames.ACTION_JUMP))
	assert_eq(router.get_depth(), 2, "the on-foot context is still there")


func test_popping_restores_the_context_beneath() -> void:
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.ui())
	source.press(GameplayNames.ACTION_JUMP)
	assert_false(router.is_pressed(GameplayNames.ACTION_JUMP))

	router.pop_context()
	assert_true(router.is_pressed(GameplayNames.ACTION_JUMP), "walking again")
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_ON_FOOT)


func test_a_non_blocking_context_falls_through() -> void:
	# The additive case: a context that claims one action and lets everything
	# else reach the context below.
	router.push_context(InputContexts.on_foot())
	router.push_context(
		InputContext.create(&"input.overlay", [&"overlay_action"], false)
	)
	source.press(GameplayNames.ACTION_JUMP)
	source.press(&"overlay_action")
	assert_true(router.is_pressed(&"overlay_action"), "the overlay's own action")
	assert_true(router.is_pressed(GameplayNames.ACTION_JUMP), "and jump falls through")


func test_pop_on_an_empty_stack_fails() -> void:
	assert_err(router.pop_context(), &"input.empty_stack")


func test_pushing_null_fails() -> void:
	assert_err(router.push_context(null), &"input.null_context")
	assert_eq(router.get_depth(), 0)


func test_remove_context_takes_one_from_the_middle() -> void:
	# Contexts do not always unwind in order: a menu opened during a
	# conversation can be closed on its own.
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.dialogue())
	router.push_context(InputContexts.ui())

	assert_ok(router.remove_context(GameplayNames.INPUT_CONTEXT_DIALOGUE))
	assert_eq(
		router.get_context_ids(),
		[GameplayNames.INPUT_CONTEXT_ON_FOOT, GameplayNames.INPUT_CONTEXT_UI] as Array[StringName]
	)


func test_removing_a_context_that_is_not_active_fails() -> void:
	router.push_context(InputContexts.on_foot())
	assert_err(router.remove_context(&"input.nonexistent"), &"input.context_not_active")


func test_remove_by_instance_takes_the_right_one_of_two_alike() -> void:
	# Two characters both on foot push contexts with the same id. Removing by
	# id would take whichever pushed last; this is why the controller removes
	# by instance.
	var first := InputContexts.on_foot()
	var second := InputContexts.on_foot()
	router.push_context(first)
	router.push_context(second)

	assert_ok(router.remove_context_instance(first))
	assert_eq(router.get_depth(), 1)
	assert_eq(router.get_active_context(), second, "the other one survived")


func test_remove_by_instance_rejects_null() -> void:
	assert_err(router.remove_context_instance(null), &"input.null_context")


func test_set_context_replaces_the_whole_stack() -> void:
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.dialogue())
	router.set_context(InputContexts.disabled())
	assert_eq(router.get_depth(), 1)
	assert_eq(router.get_active_context_id(), GameplayNames.INPUT_CONTEXT_DISABLED)


func test_clear_leaves_nothing_listening() -> void:
	router.push_context(InputContexts.on_foot())
	router.clear_contexts()
	assert_eq(router.get_depth(), 0)
	assert_eq(router.get_active_context_id(), &"")
	assert_null(router.get_active_context())


func test_has_context_finds_one_below_the_top() -> void:
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.ui())
	assert_true(router.has_context(GameplayNames.INPUT_CONTEXT_ON_FOOT))
	assert_false(router.has_context(GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER))


func test_context_changed_fires_on_every_stack_change() -> void:
	var seen: Array[StringName] = []
	router.context_changed.connect(func(id: StringName) -> void: seen.append(id))
	router.push_context(InputContexts.on_foot())
	router.push_context(InputContexts.ui())
	router.pop_context()
	assert_eq(
		seen,
		[
			GameplayNames.INPUT_CONTEXT_ON_FOOT,
			GameplayNames.INPUT_CONTEXT_UI,
			GameplayNames.INPUT_CONTEXT_ON_FOOT,
		] as Array[StringName]
	)


func test_control_suppression_reports_and_signals_once() -> void:
	var seen: Array[bool] = []
	router.control_suppressed.connect(func(s: bool) -> void: seen.append(s))

	router.push_context(InputContexts.on_foot())
	assert_false(router.is_control_suppressed())
	router.push_context(InputContexts.ui())
	assert_true(router.is_control_suppressed())
	router.pop_context()
	assert_false(router.is_control_suppressed())

	assert_eq(seen, [true, false] as Array[bool], "edges only, not every push")


func test_move_vector_is_clamped_to_unit_length() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	source.press(GameplayNames.ACTION_MOVE_RIGHT)
	var vector := router.get_move_vector()
	assert_almost_eq(vector.length(), 1.0, 0.0001, "a diagonal is not faster")


func test_move_vector_is_zero_when_movement_is_blocked() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	router.push_context(InputContexts.dialogue())
	assert_eq(router.get_move_vector(), Vector2.ZERO)


func test_forward_is_negative_y() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	assert_almost_eq(router.get_move_vector().y, -1.0)


func test_analogue_strength_survives_routing() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_MOVE_RIGHT, 0.4)
	assert_almost_eq(router.get_strength(GameplayNames.ACTION_MOVE_RIGHT), 0.4)
	assert_almost_eq(router.get_move_vector().x, 0.4, 0.0001)


func test_blocked_strength_is_zero_not_the_raw_value() -> void:
	source.press(GameplayNames.ACTION_SPRINT, 1.0)
	assert_almost_eq(router.get_strength(GameplayNames.ACTION_SPRINT), 0.0)


func test_just_pressed_and_just_released_are_routed_too() -> void:
	router.push_context(InputContexts.on_foot())
	source.press(GameplayNames.ACTION_JUMP)
	assert_true(router.was_just_pressed(GameplayNames.ACTION_JUMP))
	source.advance_frame()
	assert_false(router.was_just_pressed(GameplayNames.ACTION_JUMP), "one frame only")
	assert_true(router.is_pressed(GameplayNames.ACTION_JUMP), "still held")
	source.release(GameplayNames.ACTION_JUMP)
	assert_true(router.was_just_released(GameplayNames.ACTION_JUMP))


func test_source_can_be_swapped() -> void:
	# The seam a replay or a network client's intent stream plugs in at.
	router.push_context(InputContexts.on_foot())
	var replacement: RefCounted = FakeInputSource.new()
	replacement.press(GameplayNames.ACTION_SPRINT)
	router.set_source(replacement)
	assert_true(router.is_pressed(GameplayNames.ACTION_SPRINT))
	assert_eq(router.get_source(), replacement)


func test_a_null_source_falls_back_to_the_engine() -> void:
	router.set_source(null)
	assert_true(router.get_source() is EngineInputSource)


func test_validate_bindings_reports_an_unbound_action() -> void:
	var unbound: Array[StringName] = [GameplayNames.ACTION_SPRINT]
	source.unbound = unbound
	router.push_context(InputContexts.on_foot())
	var result := router.validate_bindings()
	assert_true(result.has_warnings(), "an unbound action is invisible at runtime")
	assert_true(result.format_report().contains("sprint"))


func test_validate_bindings_is_clean_when_everything_is_bound() -> void:
	router.push_context(InputContexts.on_foot())
	var result := router.validate_bindings()
	assert_false(result.has_errors())
	assert_false(result.has_warnings())
