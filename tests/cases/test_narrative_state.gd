extends FrameworkTestCase
## Covers NarrativeStateService: the four kinds of thing a story remembers.

var narrative: NarrativeStateService = null


func before_each() -> void:
	narrative = NarrativeStateService.new()
	add_test_node(narrative)


func test_it_registers_under_the_narrative_service_id() -> void:
	assert_eq(narrative.get_service_id(), GameplayNames.SERVICE_NARRATIVE)


func test_a_fresh_store_is_empty() -> void:
	assert_true(narrative.is_empty())


# --- Flags ----------------------------------------------------------------

func test_an_unknown_flag_is_false() -> void:
	# What makes a save written before a flag existed load cleanly.
	assert_false(narrative.get_flag(&"flag.never_set"))


func test_raising_and_clearing_a_flag() -> void:
	assert_true(narrative.set_flag(&"flag.gate_open"))
	assert_true(narrative.get_flag(&"flag.gate_open"))
	assert_true(narrative.clear_flag(&"flag.gate_open"))
	assert_false(narrative.get_flag(&"flag.gate_open"))


func test_setting_a_flag_to_what_it_already_is_changes_nothing() -> void:
	narrative.set_flag(&"flag.gate_open")
	assert_false(narrative.set_flag(&"flag.gate_open"))


func test_flag_changes_are_announced() -> void:
	var changes: Array[StringName] = []
	narrative.flag_changed.connect(
		func(flag: StringName, _v: bool) -> void: changes.append(flag)
	)
	narrative.set_flag(&"flag.a")
	narrative.set_flag(&"flag.a")
	narrative.clear_flag(&"flag.a")
	assert_size(changes, 2)


func test_all_and_any_flags() -> void:
	narrative.set_flag(&"flag.a")
	var both: Array[StringName] = [&"flag.a", &"flag.b"]
	assert_false(narrative.has_all_flags(both))
	assert_true(narrative.has_any_flag(both))
	narrative.set_flag(&"flag.b")
	assert_true(narrative.has_all_flags(both))


func test_raised_flags_are_listed() -> void:
	narrative.set_flag(&"flag.a")
	narrative.set_flag(&"flag.b")
	narrative.clear_flag(&"flag.a")
	assert_size(narrative.get_raised_flags(), 1)


func test_an_empty_flag_name_is_refused() -> void:
	assert_false(narrative.set_flag(&""))
	assert_true(narrative.is_empty())


# --- Variables ------------------------------------------------------------

func test_a_variable_round_trips() -> void:
	narrative.set_variable(&"var.name", "Ada")
	assert_eq(narrative.get_variable(&"var.name"), "Ada")
	assert_true(narrative.has_variable(&"var.name"))


func test_an_unset_variable_returns_its_fallback() -> void:
	assert_eq(narrative.get_variable(&"var.missing", "default"), "default")
	assert_null(narrative.get_variable(&"var.missing"))


func test_variable_changes_carry_the_previous_value() -> void:
	var previous: Array = []
	narrative.variable_changed.connect(
		func(_k: StringName, _v: Variant, p: Variant) -> void: previous.append(p)
	)
	narrative.set_variable(&"var.n", 1)
	narrative.set_variable(&"var.n", 2)
	assert_size(previous, 2)
	assert_eq(previous[1], 1)


func test_variables_hold_any_type() -> void:
	narrative.set_variable(&"var.number", 42)
	narrative.set_variable(&"var.point", Vector3.UP)
	narrative.set_variable(&"var.list", [1, 2, 3])
	assert_eq(narrative.get_variable(&"var.number"), 42)
	assert_eq(narrative.get_variable(&"var.point"), Vector3.UP)
	assert_size(narrative.get_variable(&"var.list"), 3)


func test_clearing_a_variable() -> void:
	narrative.set_variable(&"var.n", 1)
	assert_true(narrative.clear_variable(&"var.n"))
	assert_false(narrative.has_variable(&"var.n"))
	assert_false(narrative.clear_variable(&"var.n"))


# --- Counters -------------------------------------------------------------

func test_an_unknown_counter_is_zero() -> void:
	assert_eq(narrative.get_counter(&"counter.never"), 0)


func test_incrementing_accumulates() -> void:
	assert_eq(narrative.increment(&"counter.bandits"), 1)
	assert_eq(narrative.increment(&"counter.bandits", 4), 5)


func test_a_counter_can_go_negative() -> void:
	# A tally, not a resource. Clamping at zero would make "net favours owed"
	# unrepresentable.
	assert_eq(narrative.increment(&"counter.debt", -3), -3)


func test_counter_changes_are_announced() -> void:
	var values: Array[int] = []
	narrative.counter_changed.connect(
		func(_c: StringName, value: int, _p: int) -> void: values.append(value)
	)
	narrative.increment(&"counter.n")
	narrative.increment(&"counter.n", 0)
	narrative.set_counter(&"counter.n", 10)
	assert_size(values, 2)
	assert_eq(values[1], 10)


# --- Relationships --------------------------------------------------------

func test_an_unknown_relationship_is_neutral() -> void:
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), 0.0)


func test_standing_shifts_and_is_reported() -> void:
	assert_almost_eq(narrative.modify_relationship(&"faction.town", &"player", 15.0), 15.0)
	assert_almost_eq(narrative.modify_relationship(&"faction.town", &"player", -5.0), 10.0)


func test_standing_is_clamped() -> void:
	narrative.modify_relationship(&"faction.town", &"player", 1000.0)
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), 100.0)
	narrative.modify_relationship(&"faction.town", &"player", -5000.0)
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), -100.0)


func test_standing_is_directional() -> void:
	# A player may be loved by one faction and hunted by another for the same
	# act, and a symmetric store cannot say that.
	narrative.set_relationship(&"faction.town", &"player", 50.0)
	assert_almost_eq(narrative.get_relationship(&"player", &"faction.town"), 0.0)


func test_relationship_changes_are_announced() -> void:
	var changes: Array[float] = []
	narrative.relationship_changed.connect(
		func(_s: StringName, _o: StringName, v: float) -> void: changes.append(v)
	)
	narrative.set_relationship(&"a", &"b", 5.0)
	narrative.set_relationship(&"a", &"b", 5.0)
	assert_size(changes, 1)


# --- Bulk and persistence -------------------------------------------------

func _populate() -> void:
	narrative.set_flag(&"flag.gate_open")
	narrative.set_variable(&"var.name", "Ada")
	narrative.increment(&"counter.bandits", 7)
	narrative.set_relationship(&"faction.town", &"player", 25.0)


func test_reset_empties_everything_and_announces() -> void:
	var resets: Array[int] = []
	narrative.narrative_reset.connect(func() -> void: resets.append(1))
	_populate()
	narrative.reset()
	assert_true(narrative.is_empty())
	assert_size(resets, 1)


func test_all_four_kinds_survive_a_save() -> void:
	_populate()
	var saved := narrative.capture_state()
	narrative.reset()
	narrative.restore_state(saved)

	assert_true(narrative.get_flag(&"flag.gate_open"))
	assert_eq(narrative.get_variable(&"var.name"), "Ada")
	assert_eq(narrative.get_counter(&"counter.bandits"), 7)
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), 25.0)


func test_restoring_replaces_rather_than_merges() -> void:
	# A load is a load. Leaving the previous run's flags raised is how a save
	# comes back subtly wrong.
	narrative.set_flag(&"flag.from_previous_run")
	narrative.restore_state({"flags": ["flag.gate_open"]})
	assert_false(narrative.get_flag(&"flag.from_previous_run"))
	assert_true(narrative.get_flag(&"flag.gate_open"))


func test_a_save_from_an_older_schema_loads() -> void:
	narrative.restore_state({"flags": ["flag.only_thing_that_existed"]})
	assert_true(narrative.get_flag(&"flag.only_thing_that_existed"))
	assert_eq(narrative.get_counter(&"counter.anything"), 0)
