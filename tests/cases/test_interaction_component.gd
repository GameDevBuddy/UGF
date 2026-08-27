extends FrameworkTestCase
## Covers InteractionComponent: what it offers, what it refuses, and the
## guarantee that a refused interaction leaves nothing behind.

var actor: Node = null
var door: Node = null
var interaction: InteractionComponent = null
var open: InteractionDefinition = null


func before_each() -> void:
	# Carries a bag but nothing in it, so an unmet item requirement fails for
	# the reason the test is about rather than for having no inventory.
	actor = add_test_node(
		InteractionFixtures.actor("Player", ItemFixtures.unique(&"item.keycard"))
	)
	InteractionFixtures.assemble(actor)

	open = InteractionFixtures.door()
	door = add_test_node(InteractionFixtures.target([open]))
	InteractionFixtures.assemble(door)
	interaction = InteractionFixtures.interaction_of(door)


func _context(definition: InteractionDefinition = null) -> InteractionContext:
	return interaction.make_context(actor, definition)


# --- Offering -------------------------------------------------------------

func test_the_target_joins_the_interactable_group() -> void:
	assert_true(door.is_in_group(GameplayNames.GROUP_INTERACTABLE))


func test_what_is_offered_is_what_was_authored() -> void:
	assert_size(interaction.get_interactions(), 1)
	assert_eq(interaction.find_interaction(&"interaction.door"), open)
	assert_null(interaction.find_interaction(&"interaction.nothing"))


func test_an_entity_with_no_interactions_is_not_interactable() -> void:
	var rock := add_test_node(InteractionFixtures.target([], "Rock"))
	InteractionFixtures.assemble(rock)
	assert_false(InteractionFixtures.interaction_of(rock).is_interactable())


func test_disabling_makes_it_inert_without_forgetting_what_it_offers() -> void:
	interaction.enabled = false
	assert_false(interaction.is_interactable())
	assert_empty(interaction.get_available(actor))
	assert_err(interaction.interact(_context(open)), &"interaction.disabled")
	assert_size(interaction.get_interactions(), 1)


func test_the_highest_priority_interaction_is_offered_first() -> void:
	var talk := InteractionFixtures.definition(&"interaction.talk", &"verb.talk", "Talk")
	talk.priority = 10
	var offered: Array[InteractionDefinition] = [open, talk]
	interaction.interactions_override = offered
	InteractionFixtures.assemble(door)

	assert_eq(interaction.get_available(actor)[0], talk)
	assert_eq(interaction.get_primary(actor), talk)


func test_the_prompt_is_the_prompt_of_the_first_available() -> void:
	assert_eq(interaction.get_prompt(actor), "Open")


func test_nothing_available_means_no_prompt() -> void:
	interaction.enabled = false
	assert_eq(interaction.get_prompt(actor), "")


func test_an_unavailable_interaction_is_hidden_by_default() -> void:
	open.requirements = _requirements([InteractionFixtures.needs_item()])
	assert_empty(interaction.get_available(actor))
	assert_eq(interaction.get_prompt(actor), "")


func test_show_when_unavailable_prompts_with_the_reason() -> void:
	open.requirements = _requirements([InteractionFixtures.needs_item()])
	open.show_when_unavailable = true
	assert_size(interaction.get_available(actor), 1)
	assert_eq(interaction.get_prompt(actor), "Requires a keycard")
	assert_err(interaction.can_interact(_context(open)), &"requirement.missing_item")


# --- Running --------------------------------------------------------------

func test_an_interaction_runs_its_action() -> void:
	assert_ok(interaction.interact_by(actor))
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_the_same_interaction_toggles_back() -> void:
	interaction.interact_by(actor)
	interaction.interact_by(actor)
	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_started_and_completed_are_both_announced() -> void:
	var started: Array[InteractionContext] = []
	var completed: Array[InteractionContext] = []
	interaction.interaction_started.connect(func(c: InteractionContext) -> void: started.append(c))
	interaction.interaction_completed.connect(
		func(c: InteractionContext, _r: FrameworkResult) -> void: completed.append(c)
	)
	interaction.interact_by(actor)
	assert_size(started, 1)
	assert_size(completed, 1)
	assert_eq(started[0], completed[0])


func test_a_refused_interaction_announces_failure_and_not_completion() -> void:
	open.requirements = _requirements([InteractionFixtures.needs_item()])
	var failures: Array[FrameworkResult] = []
	var completions: Array[FrameworkResult] = []
	interaction.interaction_failed.connect(
		func(_c: InteractionContext, r: FrameworkResult) -> void: failures.append(r)
	)
	interaction.interaction_completed.connect(
		func(_c: InteractionContext, r: FrameworkResult) -> void: completions.append(r)
	)
	assert_err(interaction.interact_by(actor), &"requirement.missing_item")
	assert_size(failures, 1)
	assert_empty(completions)


func test_an_interaction_this_entity_does_not_offer_is_refused() -> void:
	var stranger := InteractionFixtures.definition(&"interaction.elsewhere")
	assert_err(interaction.interact_by(actor, stranger), &"interaction.not_offered")


func test_an_empty_context_is_refused_rather_than_crashing() -> void:
	assert_err(interaction.can_interact(null), &"interaction.null_context")


func test_an_entity_with_nothing_available_says_so() -> void:
	var rock := add_test_node(InteractionFixtures.target([], "Rock"))
	InteractionFixtures.assemble(rock)
	assert_err(
		InteractionFixtures.interaction_of(rock).interact_by(actor),
		&"interaction.none_available"
	)


# --- Atomicity ------------------------------------------------------------

func test_an_action_that_refuses_late_consumes_nothing() -> void:
	var keycard := ItemFixtures.unique(&"item.keycard")
	var carrier := add_test_node(InteractionFixtures.actor("Player", keycard))
	InteractionFixtures.assemble(carrier)
	InteractionFixtures.inventory_of(carrier).add(ItemInstance.create(keycard, 1))

	var action := RecordingAction.new()
	action.refuse_execute = true
	open.action = action
	open.requirements = _requirements([InteractionFixtures.needs_item(&"item.keycard", 1, true)])
	open.repeatable = false

	assert_err(interaction.interact_by(carrier), &"test.refused")
	assert_eq(InteractionFixtures.inventory_of(carrier).count(&"item.keycard"), 1)
	assert_false(interaction.is_spent(open))


func test_a_successful_interaction_consumes_its_requirement() -> void:
	var keycard := ItemFixtures.unique(&"item.keycard")
	var carrier := add_test_node(InteractionFixtures.actor("Player", keycard))
	InteractionFixtures.assemble(carrier)
	InteractionFixtures.inventory_of(carrier).add(ItemInstance.create(keycard, 1))
	open.requirements = _requirements([InteractionFixtures.needs_item(&"item.keycard", 1, true)])

	assert_ok(interaction.interact_by(carrier))
	assert_eq(InteractionFixtures.inventory_of(carrier).count(&"item.keycard"), 0)


func test_an_action_refused_up_front_never_runs() -> void:
	var action := RecordingAction.new()
	action.refuse_check = true
	open.action = action
	assert_err(interaction.interact_by(actor), &"test.unavailable")
	assert_eq(action.executed, 0)


# --- One-shots and cooldowns ----------------------------------------------

func test_a_one_shot_runs_once() -> void:
	open.repeatable = false
	assert_ok(interaction.interact_by(actor))
	assert_true(interaction.is_spent(open))
	assert_err(interaction.interact_by(actor), &"interaction.spent")
	assert_empty(interaction.get_available(actor))


func test_a_cooldown_blocks_and_then_expires() -> void:
	open.cooldown = 2.0
	assert_ok(interaction.interact_by(actor))
	assert_almost_eq(interaction.get_cooldown_remaining(open), 2.0)
	assert_err(interaction.interact_by(actor), &"interaction.cooling_down")

	interaction.tick(1.0)
	assert_almost_eq(interaction.get_cooldown_remaining(open), 1.0)
	assert_err(interaction.interact_by(actor), &"interaction.cooling_down")

	interaction.tick(1.5)
	assert_almost_eq(interaction.get_cooldown_remaining(open), 0.0)
	assert_ok(interaction.interact_by(actor))


func test_resetting_makes_a_one_shot_usable_again() -> void:
	open.repeatable = false
	interaction.interact_by(actor)
	interaction.reset()
	assert_false(interaction.is_spent(open))
	assert_ok(interaction.interact_by(actor))


func test_availability_changes_are_announced() -> void:
	var changes: Array[int] = []
	interaction.availability_changed.connect(func() -> void: changes.append(1))
	interaction.interact_by(actor)
	assert_size(changes, 1)


# --- Persistence ----------------------------------------------------------

func test_a_spent_one_shot_survives_a_save() -> void:
	open.repeatable = false
	interaction.interact_by(actor)
	var saved := interaction.capture_state()

	interaction.reset()
	assert_false(interaction.is_spent(open))
	interaction.restore_state(saved)
	assert_true(interaction.is_spent(open))


func test_a_cooldown_survives_a_save() -> void:
	open.cooldown = 5.0
	interaction.interact_by(actor)
	var saved := interaction.capture_state()
	interaction.reset()
	interaction.restore_state(saved)
	assert_almost_eq(interaction.get_cooldown_remaining(open), 5.0)


func test_being_disabled_survives_a_save() -> void:
	interaction.enabled = false
	var saved := interaction.capture_state()
	interaction.enabled = true
	interaction.restore_state(saved)
	assert_false(interaction.enabled)


func test_interactions_are_persistent() -> void:
	assert_true(interaction.is_persistent())


# --- Discovery ------------------------------------------------------------

func test_find_on_locates_the_component_on_an_entity() -> void:
	assert_eq(InteractionComponent.find_on(door), interaction)
	assert_eq(InteractionComponent.find_on(interaction), interaction)
	assert_null(InteractionComponent.find_on(null))


func test_find_on_returns_null_for_ordinary_scenery() -> void:
	var scenery := add_test_node(Node.new())
	assert_null(InteractionComponent.find_on(scenery))


# --- Internals ------------------------------------------------------------

func _requirements(entries: Array) -> Array[InteractionRequirement]:
	var typed: Array[InteractionRequirement] = []
	typed.assign(entries)
	return typed
