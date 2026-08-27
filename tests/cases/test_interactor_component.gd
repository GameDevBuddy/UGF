extends FrameworkTestCase
## Covers InteractorComponent: focus, reach, and the timing that is the whole
## of a "timed interaction".

var actor: Node = null
var interactor: InteractorComponent = null
var door: Node = null
var interaction: InteractionComponent = null
var open: InteractionDefinition = null


func before_each() -> void:
	actor = add_test_node(InteractionFixtures.actor("Player", null, 1, true))
	InteractionFixtures.assemble(actor)
	interactor = InteractionFixtures.interactor_of(actor)
	interactor.profile_override = _profile()
	InteractionFixtures.assemble(actor)

	open = InteractionFixtures.door()
	door = add_test_node(InteractionFixtures.target([open], "Door", true))
	InteractionFixtures.assemble(door)
	interaction = InteractionFixtures.interaction_of(door)


func _profile(
	reach: float = 2.5, auto_focus: bool = false, cancel_out_of_reach: bool = true
) -> InteractorProfile:
	var profile := InteractorProfile.new()
	profile.reach = reach
	profile.auto_focus = auto_focus
	profile.focus_interval = 0.1
	profile.cancel_when_out_of_reach = cancel_out_of_reach
	return profile


func _place(entity: Node, distance: float) -> void:
	(entity as Node3D).global_position = Vector3(distance, 0.0, 0.0)


# --- Focus ----------------------------------------------------------------

func test_focus_starts_empty() -> void:
	assert_null(interactor.get_focus())
	assert_eq(interactor.get_prompt(), "")


func test_setting_focus_announces_it_and_the_prompt() -> void:
	var focused: Array[InteractionComponent] = []
	var prompts: Array[String] = []
	interactor.focus_changed.connect(
		func(c: InteractionComponent) -> void: focused.append(c)
	)
	interactor.prompt_changed.connect(func(p: String) -> void: prompts.append(p))

	interactor.set_focus(interaction)
	assert_eq(interactor.get_focus(), interaction)
	assert_size(focused, 1)
	assert_size(prompts, 1)
	assert_eq(prompts[0], "Open")


func test_setting_the_same_focus_twice_announces_once() -> void:
	var focused: Array[InteractionComponent] = []
	interactor.focus_changed.connect(
		func(c: InteractionComponent) -> void: focused.append(c)
	)
	interactor.set_focus(interaction)
	interactor.set_focus(interaction)
	assert_size(focused, 1)


func test_scanning_finds_an_interactable_in_reach() -> void:
	_place(actor, 0.0)
	_place(door, 1.0)
	interactor.refresh_focus()
	assert_eq(interactor.get_focus(), interaction)


func test_scanning_ignores_what_is_out_of_reach() -> void:
	_place(actor, 0.0)
	_place(door, 10.0)
	interactor.refresh_focus()
	assert_null(interactor.get_focus())


func test_scanning_prefers_the_nearer_of_two() -> void:
	var far_door := add_test_node(
		InteractionFixtures.target([InteractionFixtures.door(&"interaction.far")], "FarDoor", true)
	)
	InteractionFixtures.assemble(far_door)
	_place(actor, 0.0)
	_place(door, 0.5)
	_place(far_door, 2.0)

	interactor.refresh_focus()
	assert_eq(interactor.get_focus(), interaction)


func test_scanning_ignores_an_entity_with_nothing_available() -> void:
	interaction.enabled = false
	_place(actor, 0.0)
	_place(door, 1.0)
	interactor.refresh_focus()
	assert_null(interactor.get_focus())


func test_scanning_runs_on_an_interval_not_every_frame() -> void:
	interactor.profile_override = _profile(2.5, true)
	InteractionFixtures.assemble(actor)
	_place(actor, 0.0)
	_place(door, 1.0)

	interactor.tick(0.05)
	assert_null(interactor.get_focus())
	interactor.tick(0.06)
	assert_eq(interactor.get_focus(), interaction)


# --- Instant interactions -------------------------------------------------

func test_interacting_with_nothing_in_reach_is_refused() -> void:
	assert_err(interactor.interact(), &"interactor.no_focus")


func test_the_focused_interaction_runs() -> void:
	interactor.set_focus(interaction)
	assert_ok(interactor.interact())
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_a_specific_target_can_be_used_without_focus() -> void:
	assert_ok(interactor.begin(door))
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_something_that_cannot_be_interacted_with_is_refused() -> void:
	var rock := add_test_node(Node.new())
	assert_err(interactor.begin(rock), &"interactor.no_target")


func test_a_target_out_of_reach_is_refused() -> void:
	_place(actor, 0.0)
	_place(door, 10.0)
	assert_err(interactor.begin(door), &"interactor.out_of_reach")


func test_completion_is_announced_with_the_context() -> void:
	var completed: Array[InteractionContext] = []
	interactor.interaction_completed.connect(
		func(c: InteractionContext, _r: FrameworkResult) -> void: completed.append(c)
	)
	interactor.begin(door)
	assert_size(completed, 1)
	assert_eq(completed[0].interactor, actor)
	assert_eq(completed[0].target, door)
	assert_eq(completed[0].interactor_component, interactor)


func test_a_refusal_is_announced_as_a_failure() -> void:
	var failures: Array[FrameworkResult] = []
	interactor.interaction_failed.connect(
		func(_c: InteractionContext, r: FrameworkResult) -> void: failures.append(r)
	)
	interaction.enabled = false
	assert_err(interactor.begin(door), &"interaction.disabled")
	assert_size(failures, 1)


# --- Timed interactions ---------------------------------------------------

func _timed_door(duration: float = 1.0, interruptible: bool = true) -> InteractionDefinition:
	var hack := InteractionFixtures.timed(duration)
	hack.interruptible = interruptible
	var action := ToggleStateAction.new()
	action.state = GameplayNames.STATE_OPEN
	hack.action = action
	var offered: Array[InteractionDefinition] = [hack]
	interaction.interactions_override = offered
	InteractionFixtures.assemble(door)
	return hack


func test_a_timed_interaction_does_not_complete_immediately() -> void:
	_timed_door(1.0)
	assert_ok(interactor.begin(door))
	assert_true(interactor.is_busy())
	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_progress_climbs_and_completes() -> void:
	_timed_door(1.0)
	interactor.begin(door)

	interactor.tick(0.25)
	assert_almost_eq(interactor.get_progress(), 0.25)
	interactor.tick(0.25)
	assert_almost_eq(interactor.get_progress(), 0.5)
	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))

	interactor.tick(0.5)
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))
	assert_false(interactor.is_busy())
	assert_almost_eq(interactor.get_progress(), 0.0)


func test_progress_is_announced_while_it_runs() -> void:
	_timed_door(1.0)
	var reported: Array[float] = []
	interactor.interaction_progressed.connect(
		func(_c: InteractionContext, p: float) -> void: reported.append(p)
	)
	interactor.begin(door)
	interactor.tick(0.5)
	interactor.tick(0.5)
	assert_size(reported, 2)
	assert_almost_eq(reported[0], 0.5)
	assert_almost_eq(reported[1], 1.0)


func test_cancelling_applies_nothing() -> void:
	_timed_door(1.0)
	var cancels: Array[StringName] = []
	interactor.interaction_cancelled.connect(
		func(_c: InteractionContext, reason: StringName) -> void: cancels.append(reason)
	)
	interactor.begin(door)
	interactor.tick(0.9)
	interactor.cancel(&"released")

	assert_false(interactor.is_busy())
	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))
	assert_size(cancels, 1)
	assert_eq(cancels[0], &"released")


func test_cancelling_when_idle_does_nothing() -> void:
	var cancels: Array[StringName] = []
	interactor.interaction_cancelled.connect(
		func(_c: InteractionContext, reason: StringName) -> void: cancels.append(reason)
	)
	interactor.cancel()
	assert_empty(cancels)


func test_an_uninterruptible_interaction_ignores_a_cancel() -> void:
	_timed_door(1.0, false)
	interactor.begin(door)
	interactor.tick(0.5)
	interactor.cancel(&"released")
	assert_true(interactor.is_busy())

	interactor.tick(0.5)
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_an_uninterruptible_interaction_can_still_be_forced() -> void:
	_timed_door(1.0, false)
	interactor.begin(door)
	interactor.cancel(&"despawned", true)
	assert_false(interactor.is_busy())


func test_walking_away_cancels_an_interruptible_hold() -> void:
	_timed_door(1.0)
	_place(actor, 0.0)
	_place(door, 1.0)
	interactor.begin(door)
	interactor.tick(0.5)

	_place(actor, 10.0)
	interactor.tick(0.1)
	assert_false(interactor.is_busy())
	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_walking_away_does_not_cancel_when_the_profile_says_not_to() -> void:
	interactor.profile_override = _profile(2.5, false, false)
	InteractionFixtures.assemble(actor)
	_timed_door(1.0)
	_place(actor, 0.0)
	_place(door, 1.0)
	interactor.begin(door)

	_place(actor, 10.0)
	interactor.tick(1.0)
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


func test_only_one_interaction_at_a_time() -> void:
	_timed_door(1.0)
	interactor.begin(door)
	assert_err(interactor.begin(door), &"interactor.busy")


func test_interacting_marks_the_semantic_state() -> void:
	_timed_door(1.0)
	var state := InteractionFixtures.state_of(actor)
	interactor.begin(door)
	assert_true(state.has_state(GameplayNames.STATE_INTERACTING))
	interactor.tick(1.0)
	assert_false(state.has_state(GameplayNames.STATE_INTERACTING))


func test_an_instant_interaction_never_marks_the_state() -> void:
	var state := InteractionFixtures.state_of(actor)
	interactor.begin(door)
	assert_false(state.has_state(GameplayNames.STATE_INTERACTING))


func test_a_requirement_is_rechecked_at_the_moment_of_completion() -> void:
	var hack := _timed_door(1.0)
	var locked := InteractionFixtures.needs_state([], [GameplayNames.STATE_LOCKED])
	var requirements: Array[InteractionRequirement] = [locked]
	hack.requirements = requirements

	interactor.begin(door)
	InteractionFixtures.state_of(door).add_state(GameplayNames.STATE_LOCKED)
	interactor.tick(1.0)

	assert_false(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))
	assert_false(interactor.is_busy())


# --- Shared with AI -------------------------------------------------------

func test_an_npc_uses_the_same_call_a_player_does() -> void:
	var npc := add_test_node(InteractionFixtures.actor("Guard", null, 1, true))
	InteractionFixtures.assemble(npc)
	var brain := InteractionFixtures.interactor_of(npc)
	brain.profile_override = _profile()
	InteractionFixtures.assemble(npc)

	assert_ok(brain.begin(door))
	assert_true(InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN))


# --- Discovery and defaults -----------------------------------------------

func test_find_on_locates_the_component() -> void:
	assert_eq(InteractorComponent.find_on(actor), interactor)
	assert_eq(InteractorComponent.find_on(interactor), interactor)
	assert_null(InteractorComponent.find_on(null))


func test_an_interactor_with_no_authored_profile_still_reaches() -> void:
	var plain := add_test_node(InteractionFixtures.actor("Plain"))
	InteractionFixtures.assemble(plain)
	assert_not_null(InteractionFixtures.interactor_of(plain).get_profile())
	assert_true(InteractionFixtures.interactor_of(plain).get_reach() > 0.0)


func test_a_non_spatial_entity_is_always_in_reach() -> void:
	var abstract_actor := add_test_node(InteractionFixtures.actor("Ghost"))
	InteractionFixtures.assemble(abstract_actor)
	var ghost := InteractionFixtures.interactor_of(abstract_actor)
	assert_true(ghost.is_in_reach(door))


func test_focus_and_a_half_finished_hold_are_not_persisted() -> void:
	assert_false(interactor.is_persistent())
	assert_empty(interactor.capture_state())
