extends FrameworkTestCase
## Covers DialogueRuntime: walking a conversation, branching, and the
## condition/action split.

var narrative: NarrativeStateService = null
var runtime: DialogueRuntime = null
var speaker: Node = null
var listener: Node = null


func before_each() -> void:
	narrative = NarrativeStateService.new()
	add_test_node(narrative)
	speaker = add_test_node(Node3D.new())
	speaker.name = "Foreman"
	listener = add_test_node(Node3D.new())
	listener.name = "Player"
	runtime = DialogueRuntime.new()


func _context() -> DialogueContext:
	return DialogueContext.create(speaker, listener, null, narrative)


func _start(definition: DialogueDefinition) -> FrameworkResult:
	return runtime.start(definition, _context())


func _text() -> String:
	var current := runtime.get_current_line()
	return current.text if current != null else ""


# --- Starting -------------------------------------------------------------

func test_a_conversation_starts_on_its_start_node() -> void:
	assert_ok(_start(DialogueFixtures.linear()))
	assert_true(runtime.is_running())
	assert_eq(_text(), "Hello.")


func test_a_conversation_with_no_start_node_named_uses_the_first() -> void:
	var dialogue := DialogueFixtures.linear()
	dialogue.start_node = &""
	assert_ok(_start(dialogue))
	assert_eq(_text(), "Hello.")


func test_starting_twice_is_refused() -> void:
	_start(DialogueFixtures.linear())
	assert_err(_start(DialogueFixtures.linear()), &"dialogue.already_running")


func test_starting_nothing_is_refused_rather_than_crashing() -> void:
	assert_err(runtime.start(null, _context()), &"dialogue.no_definition")
	assert_err(runtime.start(DialogueFixtures.linear(), null), &"dialogue.no_context")


func test_a_conversation_with_no_nodes_cannot_start() -> void:
	assert_err(
		_start(DialogueFixtures.definition(&"dialogue.empty", [])),
		&"dialogue.no_start_node"
	)


func test_starting_is_announced() -> void:
	var started: Array[DialogueContext] = []
	runtime.started.connect(func(c: DialogueContext) -> void: started.append(c))
	_start(DialogueFixtures.linear())
	assert_size(started, 1)


# --- Advancing ------------------------------------------------------------

func test_advancing_walks_the_lines() -> void:
	_start(DialogueFixtures.linear())
	assert_eq(_text(), "Hello.")
	runtime.advance()
	assert_eq(_text(), "Nice weather.")
	runtime.advance()
	assert_eq(_text(), "Goodbye.")


func test_reaching_an_end_node_finishes_with_its_outcome() -> void:
	var outcomes: Array[StringName] = []
	runtime.finished.connect(
		func(outcome: StringName, _c: DialogueContext) -> void: outcomes.append(outcome)
	)
	_start(DialogueFixtures.linear())
	for step in 3:
		runtime.advance()

	assert_false(runtime.is_running())
	assert_size(outcomes, 1)
	assert_eq(outcomes[0], &"outcome.ended")
	assert_eq(runtime.get_outcome(), &"outcome.ended")


func test_a_blank_successor_also_ends_it() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.short", [DialogueFixtures.line(&"only", "That's all.")], &"only"
	)
	_start(dialogue)
	runtime.advance()
	assert_false(runtime.is_running())
	assert_eq(runtime.get_outcome(), &"")


func test_advancing_when_nothing_is_running_is_refused() -> void:
	assert_err(runtime.advance(), &"dialogue.not_running")


func test_each_line_is_announced() -> void:
	var lines: Array[String] = []
	runtime.line_shown.connect(
		func(node: LineNode, _c: DialogueContext) -> void: lines.append(node.text)
	)
	_start(DialogueFixtures.linear())
	runtime.advance()
	runtime.advance()
	assert_size(lines, 3)


func test_the_speaker_falls_back_to_the_conversations_default() -> void:
	_start(DialogueFixtures.linear())
	assert_eq(runtime.get_current_speaker(), &"speaker.npc")


func test_a_line_can_name_its_own_speaker() -> void:
	var node := DialogueFixtures.line(&"only", "Over here.")
	node.speaker = &"speaker.other"
	_start(DialogueFixtures.definition(&"dialogue.one", [node], &"only"))
	assert_eq(runtime.get_current_speaker(), &"speaker.other")


# --- Choices --------------------------------------------------------------

func test_a_choice_node_stops_and_offers_options() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_true(runtime.is_awaiting_choice())
	assert_null(runtime.get_current_line())


func test_advancing_past_an_open_choice_is_refused() -> void:
	# Otherwise a "continue" press silently skips the branch the player was
	# about to take.
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_err(runtime.advance(), &"dialogue.awaiting_choice")


func test_only_available_options_are_offered() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	# accept, refuse and the shown-but-locked boast. The bribe needs gold.
	assert_size(runtime.get_choices(), 3)


func test_meeting_a_condition_opens_an_option() -> void:
	narrative.set_relationship(&"faction.town", &"player", 50.0)
	_start(DialogueFixtures.branching())
	runtime.advance()

	var node := runtime.get_current_node() as ChoiceNode
	var boast := node.find_choice(&"choice.boast")
	assert_true(boast.is_available(runtime.get_context()))


func test_an_option_shown_but_unavailable_says_why_and_cannot_be_taken() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	var node := runtime.get_current_node() as ChoiceNode
	var boast := node.find_choice(&"choice.boast")

	assert_eq(
		boast.get_display_text(runtime.get_context()),
		"[Reputation] They don't know you well enough."
	)
	assert_err(runtime.choose_option(boast), &"dialogue.choice_unavailable")
	assert_true(runtime.is_running())


func test_choosing_by_index_follows_the_option() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_ok(runtime.choose(0))
	assert_eq(_text(), "Good. See the foreman.")


func test_choosing_by_id_follows_the_option() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_ok(runtime.choose_id(&"choice.refuse"))
	assert_eq(_text(), "Suit yourself.")


func test_choosing_something_that_is_not_offered_is_refused() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_err(runtime.choose(99), &"dialogue.no_such_choice")
	assert_err(runtime.choose_id(&"choice.nonexistent"), &"dialogue.no_such_choice")


func test_choosing_when_no_choice_is_open_is_refused() -> void:
	_start(DialogueFixtures.branching())
	assert_err(runtime.choose_id(&"choice.accept"), &"dialogue.not_awaiting_choice")


func test_a_choice_is_announced() -> void:
	var taken: Array[DialogueChoice] = []
	runtime.choice_made.connect(
		func(choice: DialogueChoice, _c: DialogueContext) -> void: taken.append(choice)
	)
	_start(DialogueFixtures.branching())
	runtime.advance()
	runtime.choose_id(&"choice.accept")
	assert_size(taken, 1)
	assert_eq(taken[0].id, &"choice.accept")


func test_options_are_announced_when_they_open() -> void:
	var offered: Array[ChoiceNode] = []
	runtime.choices_offered.connect(
		func(node: ChoiceNode, _c: Array[DialogueChoice]) -> void: offered.append(node)
	)
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_size(offered, 1)


# --- Conditions query, actions mutate -------------------------------------

func test_a_choices_actions_run_only_when_it_is_taken() -> void:
	# The whole reason conditions must be side-effect free: a condition on an
	# option nobody chose still ran.
	_start(DialogueFixtures.branching())
	runtime.advance()
	assert_false(narrative.get_flag(&"flag.job_accepted"))

	runtime.choose_id(&"choice.accept")
	assert_true(narrative.get_flag(&"flag.job_accepted"))
	assert_eq(narrative.get_counter(&"counter.jobs"), 1)


func test_the_option_not_taken_changes_nothing() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	runtime.choose_id(&"choice.accept")
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), 0.0)


func test_refusing_costs_standing() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	runtime.choose_id(&"choice.refuse")
	assert_almost_eq(narrative.get_relationship(&"faction.town", &"player"), -10.0)


func test_evaluating_a_condition_never_changes_anything() -> void:
	_start(DialogueFixtures.branching())
	runtime.advance()
	for repeat in 5:
		runtime.get_choices()
	assert_true(narrative.is_empty())


func test_start_and_end_actions_run_once_each() -> void:
	var dialogue := DialogueFixtures.linear()
	dialogue.start_actions = _actions([DialogueFixtures.bump(&"counter.started")])
	dialogue.end_actions = _actions([DialogueFixtures.bump(&"counter.ended")])

	_start(dialogue)
	assert_eq(narrative.get_counter(&"counter.started"), 1)
	assert_eq(narrative.get_counter(&"counter.ended"), 0)

	for step in 3:
		runtime.advance()
	assert_eq(narrative.get_counter(&"counter.ended"), 1)


func test_a_node_with_only_actions_is_stepped_straight_through() -> void:
	# What Implementation Plan 18 calls an Action node: no text, so the runtime
	# never sits on it with nothing to show.
	_start(DialogueFixtures.remembering())
	assert_eq(_text(), "Do I know you?")
	runtime.advance()
	assert_false(runtime.is_running())
	assert_true(narrative.get_flag(&"flag.met_before"))


# --- Branching ------------------------------------------------------------

func test_a_branch_takes_the_first_condition_that_holds() -> void:
	narrative.set_flag(&"flag.met_before")
	_start(DialogueFixtures.remembering())
	assert_eq(_text(), "You again.")


func test_a_branch_falls_back_when_nothing_holds() -> void:
	_start(DialogueFixtures.remembering())
	assert_eq(_text(), "Do I know you?")


func test_a_node_whose_conditions_fail_is_skipped() -> void:
	var gated := DialogueFixtures.line(&"gated", "Secret.", &"plain")
	gated.conditions = _conditions([DialogueFixtures.flag_is(&"flag.never")])
	var dialogue := DialogueFixtures.definition(
		&"dialogue.gated",
		[gated, DialogueFixtures.line(&"plain", "Ordinary.")],
		&"gated"
	)
	_start(dialogue)
	assert_eq(_text(), "Ordinary.")


# --- Conversation-scoped values -------------------------------------------

func test_locals_are_readable_as_variables_and_shadow_the_store() -> void:
	narrative.set_variable(&"var.tone", "formal")
	_start(DialogueFixtures.linear())
	runtime.get_context().locals[&"var.tone"] = "rude"
	assert_eq(runtime.get_context().get_variable(&"var.tone"), "rude")


func test_locals_do_not_outlive_the_conversation() -> void:
	_start(DialogueFixtures.linear())
	var context := runtime.get_context()
	context.locals[&"var.answer"] = 1
	for step in 3:
		runtime.advance()
	assert_true(context.locals.is_empty())


# --- Stopping and safety --------------------------------------------------

func test_stopping_early_runs_the_end_actions() -> void:
	# Leaving a conversation half-applied is worse than finishing it.
	var dialogue := DialogueFixtures.linear()
	dialogue.end_actions = _actions([DialogueFixtures.raise_flag(&"flag.talked")])
	_start(dialogue)
	assert_ok(runtime.stop(&"walked_away"))

	assert_false(runtime.is_running())
	assert_eq(runtime.get_outcome(), &"walked_away")
	assert_true(narrative.get_flag(&"flag.talked"))


func test_stopping_when_nothing_is_running_is_refused() -> void:
	assert_err(runtime.stop(), &"dialogue.not_running")


func test_a_conversation_that_loops_without_a_line_ends_rather_than_hanging() -> void:
	# Content that is wrong should cost a conversation, not the game.
	var dialogue := DialogueFixtures.definition(
		&"dialogue.loop",
		[
			DialogueFixtures.action_node(&"a", [], &"b"),
			DialogueFixtures.action_node(&"b", [], &"a"),
		],
		&"a"
	)
	_start(dialogue)
	assert_false(runtime.is_running())
	assert_eq(runtime.get_outcome(), &"looped")


func test_a_dangling_jump_ends_the_conversation_rather_than_crashing() -> void:
	var dialogue := DialogueFixtures.definition(
		&"dialogue.broken",
		[DialogueFixtures.line(&"only", "Hello.", &"nowhere")],
		&"only"
	)
	_start(dialogue)
	runtime.advance()
	assert_false(runtime.is_running())
	assert_eq(runtime.get_outcome(), &"broken")


func test_visits_are_counted() -> void:
	# What a "you have asked me that already" line branches on.
	_start(DialogueFixtures.linear())
	assert_eq(runtime.times_visited(&"one"), 1)
	assert_eq(runtime.times_visited(&"two"), 0)


# --- Internals ------------------------------------------------------------

func _conditions(entries: Array) -> Array[DialogueCondition]:
	var typed: Array[DialogueCondition] = []
	typed.assign(entries)
	return typed


func _actions(entries: Array) -> Array[DialogueAction]:
	var typed: Array[DialogueAction] = []
	typed.assign(entries)
	return typed
