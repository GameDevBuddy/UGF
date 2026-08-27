extends FrameworkTestCase
## Covers DialogueComponent and the event adapter, and holds the M8 exit gate:
## a branching conversation, persistent flags, and events emitted for choices.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var bus: Node = null
var narrative: NarrativeStateService = null
var npc: Node3D = null
var dialogue: DialogueComponent = null
var adapter: DialogueEventAdapter = null
var player: Node3D = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	narrative = NarrativeStateService.new()
	add_test_node(narrative)

	npc = add_test_node(Node3D.new()) as Node3D
	npc.name = "Foreman"

	dialogue = DialogueComponent.new()
	dialogue.name = "DialogueComponent"
	dialogue.narrative = narrative
	dialogue.dialogue_override = DialogueFixtures.branching()
	dialogue.suppresses_control = false
	npc.add_child(dialogue)

	adapter = DialogueEventAdapter.new()
	adapter.name = "DialogueEventAdapter"
	adapter.dialogue = dialogue
	adapter.event_bus = bus
	npc.add_child(adapter)

	player = add_test_node(Node3D.new()) as Node3D
	player.name = "Player"

	var context := EntityContext.create(npc)
	for component in DefinitionBinder.collect_components(npc):
		component.initialize(context)


func _runtime() -> DialogueRuntime:
	return dialogue.get_runtime()


# --- Talking --------------------------------------------------------------

func test_an_npc_with_dialogue_can_be_talked_to() -> void:
	assert_true(dialogue.can_talk(player))
	assert_ok(dialogue.talk(player))
	assert_true(dialogue.is_talking())


func test_an_npc_with_nothing_to_say_cannot_be_talked_to() -> void:
	dialogue.set_dialogue(null)
	assert_false(dialogue.can_talk(player))
	assert_err(dialogue.talk(player), &"dialogue.nothing_to_say")


func test_talking_twice_at_once_is_refused() -> void:
	dialogue.talk(player)
	assert_err(dialogue.talk(player), &"dialogue.already_talking")


func test_the_context_carries_both_parties() -> void:
	dialogue.talk(player)
	var context := _runtime().get_context()
	assert_eq(context.speaker, npc)
	assert_eq(context.listener, player)
	assert_eq(context.narrative, narrative)


func test_starting_and_finishing_are_announced() -> void:
	var started: Array[DialogueRuntime] = []
	var finished: Array[StringName] = []
	dialogue.conversation_started.connect(
		func(r: DialogueRuntime) -> void: started.append(r)
	)
	dialogue.conversation_finished.connect(
		func(outcome: StringName, _r: DialogueRuntime) -> void: finished.append(outcome)
	)

	dialogue.talk(player)
	assert_size(started, 1)
	_runtime().advance()
	_runtime().choose_id(&"choice.refuse")
	_runtime().advance()

	assert_size(finished, 1)
	assert_eq(finished[0], &"outcome.refused")
	assert_false(dialogue.is_talking())


func test_walking_away_ends_the_conversation() -> void:
	dialogue.talk(player)
	assert_ok(dialogue.stop(&"walked_away"))
	assert_false(dialogue.is_talking())


func test_stopping_when_nobody_is_talking_is_refused() -> void:
	assert_err(dialogue.stop(), &"dialogue.not_talking")


func test_a_conversation_can_be_swapped_for_another() -> void:
	# What a quest stage does when the same NPC should start saying something
	# else.
	dialogue.set_dialogue(DialogueFixtures.linear())
	dialogue.talk(player)
	assert_eq(_runtime().get_current_line().text, "Hello.")


func test_availability_conditions_gate_the_whole_conversation() -> void:
	var gated := DialogueFixtures.branching()
	var conditions: Array[DialogueCondition] = [DialogueFixtures.flag_is(&"flag.hired")]
	gated.conditions = conditions
	dialogue.set_dialogue(gated)

	assert_false(dialogue.can_talk(player))
	assert_err(dialogue.talk(player), &"dialogue.unavailable")

	narrative.set_flag(&"flag.hired")
	assert_ok(dialogue.talk(player))


# --- One-shots ------------------------------------------------------------

func test_a_one_shot_conversation_is_had_once() -> void:
	var once := DialogueFixtures.linear()
	once.repeatable = false
	dialogue.set_dialogue(once)

	dialogue.talk(player)
	for step in 3:
		_runtime().advance()

	assert_true(dialogue.has_completed(once.id))
	assert_false(dialogue.can_talk(player))
	assert_err(dialogue.talk(player), &"dialogue.already_had")


func test_a_repeatable_conversation_can_be_had_again() -> void:
	dialogue.set_dialogue(DialogueFixtures.linear())
	dialogue.talk(player)
	for step in 3:
		_runtime().advance()
	assert_ok(dialogue.talk(player))


func test_which_one_shots_were_had_survives_a_save() -> void:
	var once := DialogueFixtures.linear()
	once.repeatable = false
	dialogue.set_dialogue(once)
	dialogue.talk(player)
	for step in 3:
		_runtime().advance()

	var saved := dialogue.capture_state()
	dialogue.restore_state({})
	assert_false(dialogue.has_completed(once.id))
	dialogue.restore_state(saved)
	assert_true(dialogue.has_completed(once.id))


func test_a_conversation_in_progress_does_not_survive_a_save() -> void:
	# Reloading into the middle of a sentence with a listener who may no longer
	# exist is worse than starting it again.
	dialogue.talk(player)
	assert_empty(dialogue.capture_state().get("completed", []))
	assert_true(dialogue.is_persistent())


# --- Input ----------------------------------------------------------------

func test_a_conversation_suppresses_control_while_it_runs() -> void:
	var source := preload("res://tests/support/fake_input_source.gd").new()
	var router := InputRouter.new(source)
	add_test_node(router)
	router.push_context(InputContexts.on_foot())

	dialogue.suppresses_control = true
	dialogue.set_router(router)
	dialogue.talk(player)
	assert_true(router.is_control_suppressed())

	dialogue.stop()
	assert_false(router.is_control_suppressed())


func test_control_suppression_can_be_turned_off() -> void:
	# A radio call plays over the top of live gameplay.
	var source := preload("res://tests/support/fake_input_source.gd").new()
	var router := InputRouter.new(source)
	add_test_node(router)
	router.push_context(InputContexts.on_foot())

	dialogue.suppresses_control = false
	dialogue.set_router(router)
	dialogue.talk(player)
	assert_false(router.is_control_suppressed())


# --- Events ---------------------------------------------------------------

func _subscribe(event_name: StringName) -> Array[FrameworkEvent]:
	var received: Array[FrameworkEvent] = []
	bus.subscribe(event_name, func(event: FrameworkEvent) -> void: received.append(event))
	return received


func test_a_choice_is_published_as_a_cross_feature_event() -> void:
	# The half of the exit gate that says "events emitted for choices". A
	# mission subscribes to this and never reads a DialogueDefinition.
	var received := _subscribe(GameplayNames.EVENT_DIALOGUE_CHOICE)

	dialogue.talk(player)
	_runtime().advance()
	_runtime().choose_id(&"choice.accept")

	assert_size(received, 1)
	assert_eq(received[0].dialogue_id, &"dialogue.job")
	assert_eq(received[0].choice_id, &"choice.accept")
	assert_eq(received[0].node_id, &"ask")
	assert_eq(received[0].source, npc)
	assert_eq(received[0].listener, player)


func test_a_choices_tags_travel_with_the_event() -> void:
	# So a mission can match on "any helpful answer" without knowing which
	# conversations exist.
	var received := _subscribe(GameplayNames.EVENT_DIALOGUE_CHOICE)
	dialogue.talk(player)
	_runtime().advance()
	_runtime().choose_id(&"choice.accept")
	assert_true(received[0].has_tag(&"choice.helpful"))


func test_completion_is_published_with_its_outcome() -> void:
	var received := _subscribe(GameplayNames.EVENT_DIALOGUE_COMPLETED)

	dialogue.talk(player)
	_runtime().advance()
	_runtime().choose_id(&"choice.refuse")
	_runtime().advance()

	assert_size(received, 1)
	assert_eq(received[0].outcome, &"outcome.refused")
	assert_eq(received[0].dialogue_id, &"dialogue.job")


func test_publication_can_be_turned_off_per_entity() -> void:
	# Ambient crowd barking one-liners should not flood the bus.
	adapter.publish_choices = false
	adapter.publish_completion = false
	var choices := _subscribe(GameplayNames.EVENT_DIALOGUE_CHOICE)
	var completions := _subscribe(GameplayNames.EVENT_DIALOGUE_COMPLETED)

	dialogue.talk(player)
	_runtime().advance()
	_runtime().choose_id(&"choice.accept")
	_runtime().advance()

	assert_empty(choices)
	assert_empty(completions)


func test_the_adapter_can_be_deleted_and_conversations_still_work() -> void:
	# Rule 10: the bus is an optional dependency, and losing it costs telling
	# other systems, not talking.
	adapter.free()
	dialogue.talk(player)
	_runtime().advance()
	assert_ok(_runtime().choose_id(&"choice.accept"))
	assert_true(narrative.get_flag(&"flag.job_accepted"))


# --- The exit gate --------------------------------------------------------

func test_a_branching_conversation_with_persistent_flags_and_events() -> void:
	# All three halves of the M8 exit gate in one conversation.
	var choices := _subscribe(GameplayNames.EVENT_DIALOGUE_CHOICE)
	var completions := _subscribe(GameplayNames.EVENT_DIALOGUE_COMPLETED)

	# It branches: the same node offers different options depending on state.
	dialogue.talk(player)
	_runtime().advance()
	assert_size(_runtime().get_choices(), 3)

	# The choice taken writes to state that outlives the conversation.
	_runtime().choose_id(&"choice.accept")
	_runtime().advance()

	assert_true(narrative.get_flag(&"flag.job_accepted"))
	assert_eq(narrative.get_counter(&"counter.jobs"), 1)
	assert_size(choices, 1)
	assert_size(completions, 1)
	assert_eq(completions[0].outcome, &"outcome.accepted")

	# The flags survive a save, which is what "persistent" means.
	var saved := narrative.capture_state()
	narrative.reset()
	assert_false(narrative.get_flag(&"flag.job_accepted"))
	narrative.restore_state(saved)
	assert_true(narrative.get_flag(&"flag.job_accepted"))

	# And the conversation reads its own consequences the second time.
	var second := DialogueFixtures.branching()
	var conditions: Array[DialogueCondition] = [
		DialogueFixtures.flag_is(&"flag.job_accepted", false)
	]
	second.conditions = conditions
	dialogue.set_dialogue(second)
	assert_false(dialogue.can_talk(player), "the job is taken; there is nothing to offer")


# --- Talking through the interaction pipeline -----------------------------

func test_an_npc_is_talked_to_through_the_same_interaction_a_door_uses() -> void:
	# M5's pipeline, spent again rather than a second path being grown.
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var talk := InteractionFixtures.definition(
		&"interaction.talk", GameplayNames.VERB_TALK, "Talk"
	)
	talk.action = TalkAction.new()
	var offered: Array[InteractionDefinition] = [talk]
	interaction.interactions_override = offered
	interaction.auto_tick = false
	npc.add_child(interaction)
	interaction.initialize(EntityContext.create(npc))

	assert_ok(interaction.interact_by(player))
	assert_true(dialogue.is_talking())
	assert_eq(_runtime().get_context().listener, player)


func test_the_talk_prompt_disappears_when_there_is_nothing_to_say() -> void:
	dialogue.set_dialogue(null)
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var talk := InteractionFixtures.definition(
		&"interaction.talk", GameplayNames.VERB_TALK, "Talk"
	)
	talk.action = TalkAction.new()
	var offered: Array[InteractionDefinition] = [talk]
	interaction.interactions_override = offered
	interaction.auto_tick = false
	npc.add_child(interaction)
	interaction.initialize(EntityContext.create(npc))

	assert_eq(interaction.get_prompt(player), "")
	assert_err(interaction.interact_by(player), &"talk.nothing_to_say")


func test_talking_to_something_that_cannot_talk_is_refused() -> void:
	var crate := add_test_node(Node3D.new())
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var talk := InteractionFixtures.definition(
		&"interaction.talk", GameplayNames.VERB_TALK, "Talk"
	)
	talk.action = TalkAction.new()
	var offered: Array[InteractionDefinition] = [talk]
	interaction.interactions_override = offered
	interaction.auto_tick = false
	crate.add_child(interaction)
	interaction.initialize(EntityContext.create(crate))

	assert_err(interaction.interact_by(player), &"talk.no_dialogue")
