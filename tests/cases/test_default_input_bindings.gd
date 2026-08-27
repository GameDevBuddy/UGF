extends FrameworkTestCase
## Covers DefaultInputBindings: that the framework's vocabulary is actually
## bindable out of the box, and that installing never trades a project's own
## bindings for the framework's.

## The project's own bindings for the framework actions, recorded so each test
## can start from an empty InputMap and hand the real one back afterwards.
var _saved_events: Dictionary[StringName, Array] = {}
var _saved_deadzones: Dictionary[StringName, float] = {}


## Clears the framework's actions out of the global InputMap for the duration
## of one test.
##
## InputMap is engine-global and this project legitimately defines these
## actions -- the addon's own plugin writes them. Without a snapshot, the first
## test to install would leave the map altered for every test after it, and the
## suite would pass or fail depending on the order it happened to run in. That
## is exactly the leakage the harness gives every test a fresh instance to
## prevent, and a global the harness cannot reach has to be handled here.
func before_each() -> void:
	for action in DefaultInputBindings.get_bindings():
		if not InputMap.has_action(action):
			continue
		_saved_events[action] = InputMap.action_get_events(action)
		_saved_deadzones[action] = InputMap.action_get_deadzone(action)
		InputMap.erase_action(action)


func after_each() -> void:
	for action in DefaultInputBindings.get_bindings():
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	for action in _saved_events:
		InputMap.add_action(action, _saved_deadzones[action])
		for event in _saved_events[action]:
			InputMap.action_add_event(action, event)
	_saved_events.clear()
	_saved_deadzones.clear()


func _install() -> ValidationResult:
	return DefaultInputBindings.install()


# --- The bindings themselves ----------------------------------------------

func test_every_action_the_framework_names_has_a_default() -> void:
	# The gap this class exists to close: a project that installs the addon
	# and gets a character which spawns, validates and cannot move.
	var bindings := DefaultInputBindings.get_bindings()
	for action in [
		GameplayNames.ACTION_MOVE_FORWARD,
		GameplayNames.ACTION_MOVE_BACK,
		GameplayNames.ACTION_MOVE_LEFT,
		GameplayNames.ACTION_MOVE_RIGHT,
		GameplayNames.ACTION_JUMP,
		GameplayNames.ACTION_SPRINT,
		GameplayNames.ACTION_CROUCH,
		GameplayNames.ACTION_INTERACT,
	]:
		assert_has(bindings, action)


func test_every_standard_context_is_fully_bindable() -> void:
	# Stated against the contexts rather than a hand-written list, so adding an
	# action to a context without a default binding fails here rather than in
	# someone's playtest.
	var bindings := DefaultInputBindings.get_bindings()
	for context in InputContexts.all():
		for action in context.actions:
			assert_has(bindings, action, "%s uses '%s'" % [context.id, action])


func test_no_action_is_left_without_events() -> void:
	var bindings := DefaultInputBindings.get_bindings()
	for action in bindings:
		assert_false(
			(bindings[action] as Array).is_empty(), "'%s' has no events" % action
		)


func test_movement_is_bound_on_keyboard_and_gamepad_both() -> void:
	var forward: Array = DefaultInputBindings.get_bindings()[
		GameplayNames.ACTION_MOVE_FORWARD
	]
	var has_key := false
	var has_pad := false
	for event in forward:
		has_key = has_key or event is InputEventKey
		has_pad = has_pad or event is InputEventJoypadMotion
	assert_true(has_key)
	assert_true(has_pad)


func test_movement_keys_use_physical_keycodes() -> void:
	# WASD on a keyboard that is not QWERTY should still be the same four keys
	# under the fingers, which is what physical_keycode means.
	var forward: Array = DefaultInputBindings.get_bindings()[
		GameplayNames.ACTION_MOVE_FORWARD
	]
	var keys := 0
	for event in forward:
		if event is InputEventKey:
			keys += 1
			assert_ne((event as InputEventKey).physical_keycode, KEY_NONE)
	assert_true(keys > 0)


func test_opposing_axes_read_opposite_ends_of_the_stick() -> void:
	var left := _axis_value(GameplayNames.ACTION_MOVE_LEFT)
	var right := _axis_value(GameplayNames.ACTION_MOVE_RIGHT)
	assert_almost_eq(left, -1.0)
	assert_almost_eq(right, 1.0)


func test_get_bindings_is_pure() -> void:
	# It builds events and returns them; it does not touch InputMap. That is
	# what lets every assertion above run without mutating editor state.
	var before := InputMap.has_action(GameplayNames.ACTION_JUMP)
	DefaultInputBindings.get_bindings()
	assert_eq(InputMap.has_action(GameplayNames.ACTION_JUMP), before)


func test_each_call_builds_fresh_events() -> void:
	# Shared InputEvent instances would let one project's rebind reach another
	# action, since Godot stores the object rather than a copy.
	var first: Array = DefaultInputBindings.get_bindings()[GameplayNames.ACTION_JUMP]
	var second: Array = DefaultInputBindings.get_bindings()[GameplayNames.ACTION_JUMP]
	assert_ne(first[0], second[0])


# --- Installing -----------------------------------------------------------

func test_install_binds_the_actions() -> void:
	_install()
	assert_true(InputMap.has_action(GameplayNames.ACTION_JUMP))
	assert_false(InputMap.action_get_events(GameplayNames.ACTION_JUMP).is_empty())


func test_installing_makes_the_engine_source_report_the_action_as_bound() -> void:
	# The end-to-end point of the exercise: EngineInputSource reports an
	# unbound action as unpressed forever, so "bound" has to become true.
	var source := EngineInputSource.new()
	assert_false(source.has_action(GameplayNames.ACTION_SPRINT))
	_install()
	assert_true(source.has_action(GameplayNames.ACTION_SPRINT))


func test_installing_clears_what_the_router_would_have_warned_about() -> void:
	var router := InputRouter.new()
	add_test_node(router)
	router.push_context(InputContexts.on_foot())
	assert_true(router.validate_bindings().has_warnings(), "unbound to begin with")

	_install()
	assert_false(router.validate_bindings().has_warnings(), "and bound after")


func test_install_is_idempotent() -> void:
	_install()
	var before := InputMap.action_get_events(GameplayNames.ACTION_JUMP).size()
	DefaultInputBindings.install()
	assert_eq(InputMap.action_get_events(GameplayNames.ACTION_JUMP).size(), before)


func test_install_never_overwrites_a_projects_own_binding() -> void:
	# A project that rebinds jump keeps its binding through every future
	# version of the addon.
	var custom := InputEventKey.new()
	custom.physical_keycode = KEY_ENTER
	InputMap.add_action(GameplayNames.ACTION_JUMP)
	InputMap.action_add_event(GameplayNames.ACTION_JUMP, custom)
	_install()

	var events := InputMap.action_get_events(GameplayNames.ACTION_JUMP)
	assert_size(events, 1, "the project's single binding, untouched")
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_ENTER)


func test_install_reports_what_it_left_alone() -> void:
	InputMap.add_action(GameplayNames.ACTION_JUMP)
	var result := _install()
	assert_true(result.format_report().contains("already bound"))
	assert_false(result.has_errors(), "leaving a binding alone is not a failure")


func test_overwriting_is_possible_but_has_to_be_asked_for() -> void:
	var custom := InputEventKey.new()
	custom.physical_keycode = KEY_ENTER
	InputMap.add_action(GameplayNames.ACTION_JUMP)
	InputMap.action_add_event(GameplayNames.ACTION_JUMP, custom)

	DefaultInputBindings.install(true)

	var events := InputMap.action_get_events(GameplayNames.ACTION_JUMP)
	assert_true(events.size() > 1, "replaced with the framework's defaults")
	for event in events:
		if event is InputEventKey:
			assert_ne((event as InputEventKey).physical_keycode, KEY_ENTER)


func test_unbound_actions_are_reportable_before_any_context_exists() -> void:
	# A setup check has to work before a context has been pushed, which is
	# earlier than InputRouter.validate_bindings() can help.
	assert_size(
		DefaultInputBindings.get_unbound_actions(),
		DefaultInputBindings.get_bindings().size()
	)
	_install()
	assert_empty(DefaultInputBindings.get_unbound_actions())


func test_uninstall_removes_only_the_framework_actions() -> void:
	InputMap.add_action(&"project.own_action")
	_install()
	DefaultInputBindings.uninstall()

	assert_false(InputMap.has_action(GameplayNames.ACTION_JUMP))
	assert_true(InputMap.has_action(&"project.own_action"))
	InputMap.erase_action(&"project.own_action")


# --- Helpers --------------------------------------------------------------

func _axis_value(action: StringName) -> float:
	for event in DefaultInputBindings.get_bindings()[action] as Array:
		if event is InputEventJoypadMotion:
			return (event as InputEventJoypadMotion).axis_value
	return 0.0
