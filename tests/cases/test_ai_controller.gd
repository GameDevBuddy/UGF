extends FrameworkTestCase
## Covers AIControllerComponent: the commands it issues, the state it holds
## for a shared brain, and the possession handoff.

var provider: FakePerceptionProvider = null
var npc: Node3D = null
var controller: AIControllerComponent = null


func before_each() -> void:
	provider = FakePerceptionProvider.new()
	npc = add_test_node(AIFixtures.npc("Guard", Vector3.ZERO, AIFixtures.guard())) as Node3D
	AIFixtures.assemble(npc)
	controller = AIFixtures.controller_of(npc)
	AIFixtures.perception_of(npc).set_provider(provider)
	controller.set_rng(_rng())


func _rng(seed_value: int = 11) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- What it is -----------------------------------------------------------

func test_the_role_supplies_the_brain_and_the_eyes() -> void:
	var role := controller.get_role()
	assert_not_null(role)
	assert_eq(controller.get_brain(), role.brain)
	assert_eq(AIFixtures.perception_of(npc).get_profile(), role.perception)


func test_changing_the_role_changes_both() -> void:
	# One call, or an NPC ends up with a guard's brain and a civilian's eyes.
	var combatant := AIFixtures.combatant()
	controller.set_role(combatant)
	assert_eq(controller.get_brain(), combatant.brain)
	assert_eq(AIFixtures.perception_of(npc).get_profile(), combatant.perception)


func test_a_brain_can_be_swapped_directly() -> void:
	var announced: Array[AIBrain] = []
	controller.brain_changed.connect(func(b: AIBrain) -> void: announced.append(b))
	var scripted := AIFixtures.brain(RoleBrain.Stance.PASSIVE)
	controller.set_brain(scripted)
	assert_eq(controller.get_brain(), scripted)
	assert_size(announced, 1)


func test_an_npc_with_no_role_has_no_brain_and_does_nothing() -> void:
	var puppet := add_test_node(AIFixtures.npc("Puppet")) as Node3D
	AIFixtures.assemble(puppet)
	var mind := AIFixtures.controller_of(puppet)
	assert_null(mind.get_brain())
	mind.think(0.1)
	assert_eq(mind.get_ai_state(), &"")


# --- Per-NPC state --------------------------------------------------------

func test_the_blackboard_is_per_npc_not_per_brain() -> void:
	# One guard_brain.tres backs forty guards. State on the resource would be
	# state all forty shared.
	var other := add_test_node(AIFixtures.npc("Other", Vector3.ZERO, AIFixtures.guard())) as Node3D
	AIFixtures.assemble(other)
	var second := AIFixtures.controller_of(other)

	controller.blackboard[&"test.value"] = 1
	assert_false(second.blackboard.has(&"test.value"))


func test_swapping_the_brain_clears_the_blackboard() -> void:
	controller.blackboard[&"test.value"] = 1
	controller.set_brain(AIFixtures.brain(RoleBrain.Stance.PASSIVE))
	assert_false(controller.blackboard.has(&"test.value"))


func test_home_defaults_to_where_it_was_assembled() -> void:
	var posted := add_test_node(
		AIFixtures.npc("Sentry", Vector3(3.0, 0.0, 4.0), AIFixtures.guard())
	) as Node3D
	AIFixtures.assemble(posted)
	assert_almost_eq(
		AIFixtures.controller_of(posted).get_home().distance_to(Vector3(3.0, 0.0, 4.0)), 0.0
	)


func test_a_wander_goal_stays_inside_the_role_radius() -> void:
	var home := controller.get_home()
	for attempt in 30:
		assert_true(home.distance_to(controller.pick_wander_goal()) <= 3.0001)


func test_the_same_seed_wanders_the_same_way() -> void:
	controller.set_rng(_rng(7))
	var first := controller.pick_wander_goal()
	controller.set_rng(_rng(7))
	assert_almost_eq(first.distance_to(controller.pick_wander_goal()), 0.0)


# --- Commands -------------------------------------------------------------

func test_moving_to_a_goal_drives_the_mover() -> void:
	controller.move_towards(Vector3.FORWARD * 10.0)
	var movement := AIFixtures.movement_of(npc)
	assert_true(controller.is_moving_to_goal())
	assert_almost_eq(movement.get_intent().direction.distance_to(Vector3.FORWARD), 0.0)


func test_sprinting_is_part_of_the_command() -> void:
	controller.move_towards(Vector3.FORWARD * 10.0, true)
	assert_true(AIFixtures.movement_of(npc).get_intent().wants_sprint)


func test_stopping_clears_the_mover() -> void:
	controller.move_towards(Vector3.FORWARD * 10.0)
	controller.stop_moving()
	assert_false(controller.is_moving_to_goal())
	assert_false(AIFixtures.movement_of(npc).get_intent().is_moving())


func test_a_goal_already_underfoot_issues_no_movement() -> void:
	controller.move_towards(controller.get_position())
	assert_false(AIFixtures.movement_of(npc).get_intent().is_moving())


func test_movement_is_reapplied_every_frame_not_every_thought() -> void:
	# Otherwise an NPC walking to a goal stutters at the think interval.
	controller.think_interval = 1.0
	controller.move_towards(Vector3.FORWARD * 10.0)
	controller.tick(0.05)
	assert_almost_eq(
		AIFixtures.movement_of(npc).get_intent().direction.distance_to(Vector3.FORWARD), 0.0
	)


func test_a_goal_goes_through_the_navigator_when_there_is_one() -> void:
	controller.move_towards(Vector3.FORWARD * 10.0)
	var navigation := AIFixtures.navigation_of(npc)
	assert_true(navigation.has_destination())
	assert_eq(navigation.get_destination(), Vector3.FORWARD * 10.0)


# --- State ----------------------------------------------------------------

func test_the_state_is_announced_when_it_changes() -> void:
	var announced: Array[StringName] = []
	controller.state_changed.connect(func(s: StringName) -> void: announced.append(s))
	controller.set_ai_state(GameplayNames.AI_STATE_ENGAGE)
	controller.set_ai_state(GameplayNames.AI_STATE_ENGAGE)
	controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
	assert_size(announced, 2)


func test_alert_states_are_mirrored_onto_semantic_state() -> void:
	# So a HUD, an animation tree or a sound cue can watch the entity without
	# knowing that AI exists (rule 21).
	var state := AIFixtures.state_of(npc)
	controller.set_ai_state(GameplayNames.AI_STATE_ENGAGE)
	assert_true(state.has_state(GameplayNames.STATE_ALERTED))

	controller.set_ai_state(GameplayNames.AI_STATE_FLEE)
	assert_true(state.has_state(GameplayNames.STATE_FLEEING))

	controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
	assert_false(state.has_state(GameplayNames.STATE_ALERTED))
	assert_false(state.has_state(GameplayNames.STATE_FLEEING))


# --- Being switched off ---------------------------------------------------

func test_an_inactive_controller_stops_thinking_and_moving() -> void:
	controller.move_towards(Vector3.FORWARD * 10.0)
	controller.set_active(false)
	assert_false(controller.is_moving_to_goal())

	var state_before := controller.get_ai_state()
	controller.tick(1.0)
	assert_eq(controller.get_ai_state(), state_before)


func test_reactivating_lets_it_think_again() -> void:
	controller.set_active(false)
	controller.set_active(true)
	controller.tick(0.1)
	assert_ne(controller.get_ai_state(), &"")


# --- The context ----------------------------------------------------------

func test_the_context_carries_what_the_npc_has() -> void:
	var context := controller.build_context(0.1)
	assert_eq(context.actor, npc)
	assert_eq(context.controller, controller)
	assert_eq(context.movement, AIFixtures.movement_of(npc))
	assert_eq(context.combat, AIFixtures.combat_of(npc))
	assert_eq(context.health, AIFixtures.health_of(npc))
	assert_not_null(context.memory)
	assert_almost_eq(context.delta, 0.1)


func test_a_context_without_perception_still_has_a_memory() -> void:
	# So a brain reads an empty memory rather than checking for null on every
	# line it writes.
	controller.perception = null
	var context := controller.build_context(0.1)
	assert_not_null(context.memory)
	assert_true(context.memory.is_empty())


func test_an_unarmed_npc_reports_that_it_cannot_fight() -> void:
	var unarmed := add_test_node(
		AIFixtures.npc("Civilian", Vector3.ZERO, AIFixtures.civilian(), false)
	) as Node3D
	AIFixtures.assemble(unarmed)
	var context := AIFixtures.controller_of(unarmed).build_context(0.1)
	assert_null(context.combat)
	assert_false(context.can_fight())


# --- Persistence ----------------------------------------------------------

func test_the_post_and_the_activity_survive_a_save() -> void:
	controller.set_home(Vector3(5.0, 0.0, -7.0))
	controller.set_ai_state(GameplayNames.AI_STATE_INVESTIGATE)
	var saved := controller.capture_state()

	controller.set_home(Vector3.ZERO)
	controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
	controller.restore_state(saved)

	assert_almost_eq(controller.get_home().distance_to(Vector3(5.0, 0.0, -7.0)), 0.0)
	assert_eq(controller.get_ai_state(), GameplayNames.AI_STATE_INVESTIGATE)


func test_what_it_knew_does_not_survive_a_save() -> void:
	# A guard that reloads into a search for someone who logged out an hour
	# ago is worse than one that starts calm.
	controller.blackboard[&"test.value"] = 1
	controller.restore_state(controller.capture_state())
	assert_false(controller.blackboard.has(&"test.value"))


func test_controllers_are_persistent() -> void:
	assert_true(controller.is_persistent())
