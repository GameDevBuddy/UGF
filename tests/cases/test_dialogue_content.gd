extends FrameworkTestCase
## Covers dialogue content: conditions, actions, and the validation that
## catches a conversation nobody could have.

var narrative: NarrativeStateService = null
var speaker: Node = null
var listener: Node = null


func before_each() -> void:
	narrative = NarrativeStateService.new()
	add_test_node(narrative)
	speaker = add_test_node(Node3D.new())
	listener = add_test_node(Node3D.new())


func _context() -> DialogueContext:
	return DialogueContext.create(speaker, listener, null, narrative)


# --- NarrativeCondition ---------------------------------------------------

func test_a_flag_condition_reads_the_store() -> void:
	var condition := DialogueFixtures.flag_is(&"flag.gate_open")
	assert_false(condition.evaluate(_context()))
	narrative.set_flag(&"flag.gate_open")
	assert_true(condition.evaluate(_context()))


func test_a_flag_condition_can_ask_for_false() -> void:
	var condition := DialogueFixtures.flag_is(&"flag.gate_open", false)
	assert_true(condition.evaluate(_context()))
	narrative.set_flag(&"flag.gate_open")
	assert_false(condition.evaluate(_context()))


func test_a_counter_condition_compares() -> void:
	var condition := DialogueFixtures.counter_at_least(&"counter.bandits", 5)
	narrative.increment(&"counter.bandits", 4)
	assert_false(condition.evaluate(_context()))
	narrative.increment(&"counter.bandits")
	assert_true(condition.evaluate(_context()))


func test_a_relationship_condition_compares() -> void:
	var condition := DialogueFixtures.standing_at_least(&"faction.town", &"player", 20.0)
	assert_false(condition.evaluate(_context()))
	narrative.set_relationship(&"faction.town", &"player", 25.0)
	assert_true(condition.evaluate(_context()))


func test_a_variable_condition_compares_across_number_types() -> void:
	# A counter of 3 and an authored 3.0 are the same answer, and refusing
	# that is a trap nobody enjoys finding in a shipped conversation.
	var condition := NarrativeCondition.new()
	condition.subject = NarrativeCondition.Subject.VARIABLE
	condition.key = &"var.count"
	condition.value = 3.0
	narrative.set_variable(&"var.count", 3)
	assert_true(condition.evaluate(_context()))


func test_every_comparison_operator_works() -> void:
	narrative.increment(&"counter.n", 5)
	var cases := {
		NarrativeCondition.Comparison.EQUAL: [5, true],
		NarrativeCondition.Comparison.NOT_EQUAL: [4, true],
		NarrativeCondition.Comparison.GREATER: [4, true],
		NarrativeCondition.Comparison.GREATER_OR_EQUAL: [5, true],
		NarrativeCondition.Comparison.LESS: [5, false],
		NarrativeCondition.Comparison.LESS_OR_EQUAL: [5, true],
	}
	for comparison in cases:
		var condition := NarrativeCondition.new()
		condition.subject = NarrativeCondition.Subject.COUNTER
		condition.key = &"counter.n"
		condition.comparison = comparison
		condition.value = cases[comparison][0]
		assert_eq(
			condition.evaluate(_context()), cases[comparison][1], condition.describe()
		)


func test_a_condition_with_no_narrative_store_answers_no_rather_than_crashing() -> void:
	var context := DialogueContext.create(speaker, listener, null, null)
	assert_false(DialogueFixtures.flag_is(&"flag.anything").evaluate(context))
	assert_false(
		DialogueFixtures.counter_at_least(&"counter.anything", 1).evaluate(context)
	)


func test_a_condition_that_names_nothing_is_a_content_error() -> void:
	assert_false(NarrativeCondition.new().validate().is_valid())


func test_a_relationship_condition_needs_both_parties() -> void:
	var condition := DialogueFixtures.standing_at_least(&"faction.town", &"", 1.0)
	assert_false(condition.validate().is_valid())


func test_comparing_a_flag_to_a_number_is_flagged() -> void:
	var condition := DialogueFixtures.flag_is(&"flag.a")
	condition.value = 3
	assert_true(condition.validate().has_warnings())


func test_ordering_a_flag_is_flagged() -> void:
	var condition := DialogueFixtures.flag_is(&"flag.a")
	condition.comparison = NarrativeCondition.Comparison.GREATER
	assert_true(condition.validate().has_warnings())


# --- ItemCondition --------------------------------------------------------

func _with_inventory(node: Node, item_id: StringName, quantity: int) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container()
	node.add_child(inventory)
	inventory.initialize(EntityContext.create(node))
	if quantity > 0:
		inventory.add(ItemInstance.create(ItemFixtures.stackable(item_id, 99), quantity))
	return inventory


func test_an_item_condition_reads_the_listeners_bag() -> void:
	var condition := DialogueFixtures.carries(&"item.gold", 50)
	assert_false(condition.evaluate(_context()))
	_with_inventory(listener, &"item.gold", 50)
	assert_true(condition.evaluate(_context()))


func test_an_item_condition_can_read_the_speakers_bag() -> void:
	var condition := DialogueFixtures.carries(&"item.gold", 10)
	condition.party = ItemCondition.Party.SPEAKER
	_with_inventory(speaker, &"item.gold", 10)
	assert_true(condition.evaluate(_context()))


func test_an_item_condition_can_be_negated() -> void:
	var condition := DialogueFixtures.carries(&"item.gold", 1)
	condition.negate = true
	assert_true(condition.evaluate(_context()), "nothing carried, so 'lacks' holds")
	_with_inventory(listener, &"item.gold", 1)
	assert_false(condition.evaluate(_context()))


func test_no_inventory_at_all_reads_as_not_carrying() -> void:
	assert_false(DialogueFixtures.carries(&"item.gold").evaluate(_context()))


func test_an_item_condition_with_no_id_is_a_content_error() -> void:
	assert_false(ItemCondition.new().validate().is_valid())


func test_conditions_describe_themselves() -> void:
	assert_has(DialogueFixtures.flag_is(&"flag.a").describe(), "flag.a")
	assert_has(DialogueFixtures.carries(&"item.gold", 2).describe(), "item.gold")
	assert_has(
		DialogueFixtures.standing_at_least(&"faction.town", &"player", 1.0).describe(),
		"faction.town"
	)


# --- The condition base ---------------------------------------------------

func test_the_base_condition_always_holds() -> void:
	assert_true(DialogueCondition.new().evaluate(_context()))


func test_all_hold_skips_empty_slots() -> void:
	# An empty slot in an authored array must not silently hide a line.
	var conditions: Array[DialogueCondition] = [null, DialogueFixtures.flag_is(&"flag.a")]
	assert_false(DialogueCondition.all_hold(conditions, _context()))
	narrative.set_flag(&"flag.a")
	assert_true(DialogueCondition.all_hold(conditions, _context()))


# --- NarrativeAction ------------------------------------------------------

func test_every_narrative_operation_writes() -> void:
	var context := _context()
	DialogueFixtures.raise_flag(&"flag.a").execute(context)
	DialogueFixtures.bump(&"counter.n", 3).execute(context)
	DialogueFixtures.shift_standing(&"faction.town", &"player", 5.0).execute(context)

	var set_variable := NarrativeAction.new()
	set_variable.operation = NarrativeAction.Operation.SET_VARIABLE
	set_variable.key = &"var.name"
	set_variable.value = "Ada"
	set_variable.execute(context)

	assert_true(narrative.get_flag(&"flag.a"))
	assert_eq(narrative.get_counter(&"counter.n"), 3)
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), 5.0)
	assert_eq(narrative.get_variable(&"var.name"), "Ada")


func test_a_local_is_written_to_the_conversation_not_the_store() -> void:
	var action := NarrativeAction.new()
	action.operation = NarrativeAction.Operation.SET_LOCAL
	action.key = &"var.answer"
	action.value = "yes"

	var context := _context()
	assert_ok(action.execute(context))
	assert_eq(context.locals[&"var.answer"], "yes")
	assert_false(narrative.has_variable(&"var.answer"))


func test_a_local_works_with_no_narrative_store_at_all() -> void:
	var action := NarrativeAction.new()
	action.operation = NarrativeAction.Operation.SET_LOCAL
	action.key = &"var.answer"
	action.value = 1
	assert_ok(action.execute(DialogueContext.create(speaker, listener, null, null)))


func test_writing_with_no_store_reports_rather_than_pretending() -> void:
	var context := DialogueContext.create(speaker, listener, null, null)
	assert_err(
		DialogueFixtures.raise_flag(&"flag.a").execute(context),
		&"narrative_action.no_service"
	)


func test_an_action_that_names_nothing_is_refused_and_flagged() -> void:
	assert_err(NarrativeAction.new().execute(_context()), &"narrative_action.no_key")
	assert_false(NarrativeAction.new().validate().is_valid())


func test_a_zero_increment_is_flagged() -> void:
	assert_true(DialogueFixtures.bump(&"counter.n", 0).validate().has_warnings())


func test_actions_describe_themselves() -> void:
	assert_has(DialogueFixtures.bump(&"counter.n", 2).describe(), "counter.n")
	assert_has(
		DialogueFixtures.shift_standing(&"a", &"b", -3.0).describe(), "b"
	)


func test_run_all_skips_empty_slots_and_keeps_going() -> void:
	var actions: Array[DialogueAction] = [
		null, DialogueFixtures.raise_flag(&"flag.a"), DialogueFixtures.bump(&"counter.n")
	]
	DialogueAction.run_all(actions, _context())
	assert_true(narrative.get_flag(&"flag.a"))
	assert_eq(narrative.get_counter(&"counter.n"), 1)


# --- Definition validation ------------------------------------------------

func test_a_complete_conversation_validates_clean() -> void:
	var result := DialogueFixtures.branching().validate()
	assert_true(result.is_valid(), result.format_report())
	assert_false(result.has_warnings(), result.format_report())


func test_a_conversation_with_no_nodes_is_an_error() -> void:
	assert_false(DialogueFixtures.definition(&"dialogue.empty", []).validate().is_valid())


func test_a_dangling_jump_is_an_error() -> void:
	# The commonest thing to get wrong by hand and the hardest to notice: it
	# looks exactly like a conversation meant to end there.
	var dialogue := DialogueFixtures.definition(
		&"dialogue.broken", [DialogueFixtures.line(&"one", "Hi.", &"nowhere")], &"one"
	)
	assert_false(dialogue.validate().is_valid())


func test_a_missing_start_node_is_an_error() -> void:
	var dialogue := DialogueFixtures.linear()
	dialogue.start_node = &"nonexistent"
	assert_false(dialogue.validate().is_valid())


func test_duplicate_node_ids_are_an_error() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.twins",
		[DialogueFixtures.line(&"same", "A."), DialogueFixtures.line(&"same", "B.")],
		&"same"
	)
	assert_false(dialogue.validate().is_valid())


func test_a_node_with_no_id_is_an_error() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.nameless", [DialogueFixtures.line(&"", "Who am I?")]
	)
	assert_false(dialogue.validate().is_valid())


func test_an_unreachable_node_is_a_warning_not_an_error() -> void:
	# A conversation under construction has orphans; failing the build over one
	# would make the validator something people turn off.
	var dialogue := DialogueFixtures.definition(
		&"dialogue.orphan",
		[
			DialogueFixtures.line(&"one", "Hi."),
			DialogueFixtures.line(&"orphan", "Nobody can hear me."),
		],
		&"one"
	)
	var result := dialogue.validate()
	assert_true(result.is_valid())
	assert_true(result.has_warnings())


func test_a_choice_node_with_no_options_is_an_error() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.stall", [DialogueFixtures.choice_node(&"ask", "Well?", [])], &"ask"
	)
	assert_false(dialogue.validate().is_valid())


func test_duplicate_choice_ids_are_an_error() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.ambiguous",
		[
			DialogueFixtures.choice_node(
				&"ask",
				"Well?",
				[
					DialogueFixtures.choice(&"same", "A.", &"ask"),
					DialogueFixtures.choice(&"same", "B.", &"ask"),
				]
			)
		],
		&"ask"
	)
	assert_false(dialogue.validate().is_valid())


func test_a_choice_with_no_text_is_an_error() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.blank",
		[DialogueFixtures.choice_node(&"ask", "Well?", [DialogueFixtures.choice(&"a", "")])],
		&"ask"
	)
	assert_false(dialogue.validate().is_valid())


func test_mismatched_branch_arrays_are_an_error() -> void:
	var node := DialogueFixtures.branch(
		&"start", [DialogueFixtures.flag_is(&"flag.a")], [], &"one"
	)
	var dialogue := DialogueFixtures.definition(
		&"dialogue.mismatch", [node, DialogueFixtures.line(&"one", "Hi.")], &"start"
	)
	assert_false(dialogue.validate().is_valid())


func test_an_end_node_with_a_successor_is_flagged() -> void:
	var ending := DialogueFixtures.ending(&"done")
	ending.next = &"one"
	var dialogue := DialogueFixtures.definition(
		&"dialogue.after_the_end",
		[DialogueFixtures.line(&"one", "Hi.", &"done"), ending],
		&"one"
	)
	assert_true(dialogue.validate().has_warnings())


func test_a_line_with_no_text_is_flagged() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.silent", [DialogueFixtures.line(&"one", "")], &"one"
	)
	assert_true(dialogue.validate().has_warnings())


func test_nodes_are_found_by_id() -> void:
	var dialogue := DialogueFixtures.linear()
	assert_not_null(dialogue.find_node(&"two"))
	assert_null(dialogue.find_node(&"nonexistent"))
	assert_true(dialogue.has_node(&"one"))
	assert_eq(dialogue.get_node_count(), 4)
