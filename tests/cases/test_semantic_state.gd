extends FrameworkTestCase
## Covers SemanticState.

var entity: Node = null
var state: SemanticState = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	state = SemanticState.new()
	entity.add_child(state)


func test_starts_empty() -> void:
	assert_empty(state.get_states())
	assert_false(state.has_state(GameplayNames.STATE_DEAD))


func test_add_state() -> void:
	assert_true(state.add_state(GameplayNames.STATE_DEAD))
	assert_true(state.has_state(GameplayNames.STATE_DEAD))
	assert_size(state.get_states(), 1)


func test_adding_twice_changes_nothing() -> void:
	state.add_state(GameplayNames.STATE_DEAD)
	assert_false(state.add_state(GameplayNames.STATE_DEAD))
	assert_size(state.get_states(), 1)


func test_empty_state_is_rejected() -> void:
	assert_false(state.add_state(&""))
	assert_empty(state.get_states())


func test_remove_state() -> void:
	state.add_state(GameplayNames.STATE_DEAD)
	assert_true(state.remove_state(GameplayNames.STATE_DEAD))
	assert_false(state.has_state(GameplayNames.STATE_DEAD))
	assert_false(state.remove_state(GameplayNames.STATE_DEAD), "Removing twice reports false")


func test_set_state_toggles() -> void:
	assert_true(state.set_state(GameplayNames.STATE_SPRINTING, true))
	assert_true(state.has_state(GameplayNames.STATE_SPRINTING))
	assert_true(state.set_state(GameplayNames.STATE_SPRINTING, false))
	assert_false(state.has_state(GameplayNames.STATE_SPRINTING))


func test_signals_fire_on_change_only() -> void:
	var added: Array[StringName] = []
	var removed: Array[StringName] = []
	state.state_added.connect(func(s: StringName) -> void: added.append(s))
	state.state_removed.connect(func(s: StringName) -> void: removed.append(s))

	state.add_state(GameplayNames.STATE_DEAD)
	state.add_state(GameplayNames.STATE_DEAD)
	state.remove_state(GameplayNames.STATE_DEAD)
	state.remove_state(GameplayNames.STATE_DEAD)

	assert_size(added, 1)
	assert_size(removed, 1)


func test_has_all_states() -> void:
	state.add_state(GameplayNames.STATE_SPRINTING)
	state.add_state(GameplayNames.STATE_AIRBORNE)
	assert_true(
		state.has_all_states([GameplayNames.STATE_SPRINTING, GameplayNames.STATE_AIRBORNE])
	)
	assert_false(
		state.has_all_states([GameplayNames.STATE_SPRINTING, GameplayNames.STATE_DEAD])
	)


func test_has_any_state() -> void:
	state.add_state(GameplayNames.STATE_CROUCHING)
	assert_true(state.has_any_state([GameplayNames.STATE_DEAD, GameplayNames.STATE_CROUCHING]))
	assert_false(state.has_any_state([GameplayNames.STATE_DEAD]))


func test_clear_emits_for_each_state() -> void:
	state.add_state(GameplayNames.STATE_DEAD)
	state.add_state(GameplayNames.STATE_CROUCHING)
	var removed: Array[StringName] = []
	state.state_removed.connect(func(s: StringName) -> void: removed.append(s))
	state.clear_states()
	assert_empty(state.get_states())
	assert_size(removed, 2)


func test_round_trips_through_capture_and_restore() -> void:
	state.add_state(GameplayNames.STATE_DEAD)
	state.add_state(GameplayNames.STATE_CROUCHING)
	var captured := state.capture_state()

	var restored := SemanticState.new()
	entity.add_child(restored)
	restored.restore_state(captured)

	assert_true(restored.has_state(GameplayNames.STATE_DEAD))
	assert_true(restored.has_state(GameplayNames.STATE_CROUCHING))
	assert_size(restored.get_states(), 2)


func test_restore_replaces_rather_than_merges() -> void:
	state.add_state(GameplayNames.STATE_SPRINTING)
	state.restore_state({"states": [GameplayNames.STATE_DEAD]})
	assert_false(state.has_state(GameplayNames.STATE_SPRINTING), "Prior state was cleared")
	assert_true(state.has_state(GameplayNames.STATE_DEAD))


func test_restore_tolerates_empty_data() -> void:
	state.add_state(GameplayNames.STATE_DEAD)
	state.restore_state({})
	assert_empty(state.get_states())


func test_is_persistent() -> void:
	assert_true(state.is_persistent())
