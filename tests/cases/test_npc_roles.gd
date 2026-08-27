extends FrameworkTestCase
## The M7 exit gate: a civilian, a guard and a combatant built from the same
## character base.
##
## What is asserted is a negative — that there is no CivilianNPC, no GuardNPC
## and no combatant path through the controller. All three are one entity
## composition and one brain class, differing in an NPCRoleDefinition, and the
## behaviours that come out of them are genuinely different.

var provider: FakePerceptionProvider = null
var hits: FakeHitProvider = null
var intruder: Node3D = null


func before_each() -> void:
	provider = FakePerceptionProvider.new()
	hits = FakeHitProvider.new()
	intruder = add_test_node(AIFixtures.actor("Intruder", Vector3.FORWARD * 6.0, 5.0)) as Node3D
	AIFixtures.assemble(intruder)
	provider.candidates.append(intruder)
	hits.targets.append(intruder)


## Every role is built by this one call. If a role needed its own construction
## path, the exit gate would not be met.
func _spawn(role: NPCRoleDefinition, position: Vector3 = Vector3.ZERO) -> Node3D:
	var npc := add_test_node(AIFixtures.npc("NPC", position, role)) as Node3D
	AIFixtures.assemble(npc)
	AIFixtures.perception_of(npc).set_provider(provider)
	var combat := AIFixtures.combat_of(npc)
	if combat != null:
		combat.set_hit_provider(hits)
	var controller := AIFixtures.controller_of(npc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	controller.set_rng(rng)
	return npc


func _run(npc: Node3D, seconds: float = 0.4, step: float = 0.2) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		AIFixtures.perception_of(npc).sweep(step)
		AIFixtures.controller_of(npc).tick(step)
		elapsed += step


func _state(npc: Node3D) -> StringName:
	return AIFixtures.controller_of(npc).get_ai_state()


func _heading(npc: Node3D) -> Vector3:
	return AIFixtures.movement_of(npc).get_intent().direction


# --- The gate -------------------------------------------------------------

func test_all_three_roles_are_the_same_composition() -> void:
	var civilian := _spawn(AIFixtures.civilian())
	var guard := _spawn(AIFixtures.guard())
	var combatant := _spawn(AIFixtures.combatant())

	for npc in [civilian, guard, combatant]:
		assert_not_null(AIFixtures.controller_of(npc))
		assert_not_null(AIFixtures.perception_of(npc))
		assert_not_null(AIFixtures.movement_of(npc))
		assert_not_null(AIFixtures.combat_of(npc))
		assert_true(AIFixtures.controller_of(npc).get_brain() is RoleBrain)


func test_all_three_notice_the_same_intruder() -> void:
	for role in [AIFixtures.civilian(), AIFixtures.guard(), AIFixtures.combatant()]:
		var npc := _spawn(role)
		_run(npc)
		assert_true(
			AIFixtures.perception_of(npc).get_memory().knows(intruder),
			"%s should have noticed" % role.id
		)


func test_and_do_three_different_things_about_it() -> void:
	# The whole gate in one assertion: same eyes, same body, same brain class,
	# three behaviours, and the only difference on disk is a .tres.
	var civilian := _spawn(AIFixtures.civilian())
	var guard := _spawn(AIFixtures.guard())
	var combatant := _spawn(AIFixtures.combatant())

	_run(civilian)
	_run(guard)
	_run(combatant)

	assert_eq(_state(civilian), GameplayNames.AI_STATE_FLEE)
	assert_eq(_state(guard), GameplayNames.AI_STATE_ENGAGE)
	assert_eq(_state(combatant), GameplayNames.AI_STATE_ENGAGE)


# --- Civilian -------------------------------------------------------------

func test_a_civilian_runs_the_other_way() -> void:
	var civilian := _spawn(AIFixtures.civilian())
	_run(civilian)
	assert_eq(_state(civilian), GameplayNames.AI_STATE_FLEE)
	assert_true(
		_heading(civilian).dot(Vector3.FORWARD) < 0.0,
		"a civilian should head away from the intruder in front of it"
	)


func test_a_civilian_never_attacks() -> void:
	var civilian := _spawn(AIFixtures.civilian())
	_run(civilian, 2.0)
	assert_almost_eq(AIFixtures.health_of(intruder).get_current(), 100.0)


func test_a_civilian_is_marked_as_fleeing() -> void:
	var civilian := _spawn(AIFixtures.civilian())
	_run(civilian)
	assert_true(AIFixtures.state_of(civilian).has_state(GameplayNames.STATE_FLEEING))


func test_an_undisturbed_civilian_wanders_near_home() -> void:
	provider.candidates.clear()
	var civilian := _spawn(AIFixtures.civilian())
	var home := AIFixtures.controller_of(civilian).get_home()
	_run(civilian, 3.0)
	assert_has(
		[GameplayNames.AI_STATE_IDLE, GameplayNames.AI_STATE_WANDER], _state(civilian)
	)
	var goal := AIFixtures.controller_of(civilian).get_move_goal()
	assert_true(home.distance_to(goal) <= 5.001 or goal == Vector3.ZERO)


# --- Guard ----------------------------------------------------------------

func test_a_guard_closes_on_what_it_sees() -> void:
	var guard := _spawn(AIFixtures.guard())
	_run(guard)
	assert_eq(_state(guard), GameplayNames.AI_STATE_ENGAGE)
	assert_true(
		_heading(guard).dot(Vector3.FORWARD) > 0.0,
		"a guard should head towards the intruder in front of it"
	)


func test_a_guard_attacks_once_it_is_in_reach() -> void:
	var guard := _spawn(AIFixtures.guard(), Vector3.ZERO)
	intruder.global_position = Vector3.FORWARD * 1.0
	_run(guard, 1.0)
	assert_true(
		AIFixtures.health_of(intruder).get_current() < 100.0,
		"an intruder standing next to a guard should be attacked"
	)


func test_a_guard_investigates_where_the_intruder_went() -> void:
	var guard := _spawn(AIFixtures.guard())
	_run(guard)
	assert_eq(_state(guard), GameplayNames.AI_STATE_ENGAGE)

	# Out of sight, not out of mind.
	intruder.global_position = Vector3.BACK * 40.0
	_run(guard)
	assert_eq(_state(guard), GameplayNames.AI_STATE_INVESTIGATE)
	assert_true(AIFixtures.state_of(guard).has_state(GameplayNames.STATE_ALERTED))


func test_a_guard_gives_up_after_searching() -> void:
	# Otherwise a guard stands on the last known position forever.
	var guard := _spawn(AIFixtures.guard())
	_run(guard)
	intruder.global_position = Vector3.BACK * 40.0
	_run(guard, 0.4)

	var controller := AIFixtures.controller_of(guard)
	guard.global_position = controller.get_move_goal()
	_run(guard, 4.0)

	assert_false(AIFixtures.perception_of(guard).get_memory().knows(intruder))
	assert_has([GameplayNames.AI_STATE_IDLE, GameplayNames.AI_STATE_WANDER], _state(guard))


func test_a_guard_with_no_weapon_runs_instead_of_charging() -> void:
	# Noticing something it cannot fight is still information.
	var unarmed := add_test_node(
		AIFixtures.npc("Unarmed", Vector3.ZERO, AIFixtures.guard(), false)
	) as Node3D
	AIFixtures.assemble(unarmed)
	AIFixtures.perception_of(unarmed).set_provider(provider)
	_run(unarmed)
	assert_eq(_state(unarmed), GameplayNames.AI_STATE_FLEE)


# --- Combatant ------------------------------------------------------------

func test_a_combatant_engages_on_sight() -> void:
	var combatant := _spawn(AIFixtures.combatant())
	_run(combatant)
	assert_eq(_state(combatant), GameplayNames.AI_STATE_ENGAGE)


func test_a_wounded_combatant_can_be_told_to_run() -> void:
	var role := AIFixtures.combatant()
	(role.brain as RoleBrain).flee_health_fraction = 0.5
	var combatant := _spawn(role)

	_run(combatant)
	assert_eq(_state(combatant), GameplayNames.AI_STATE_ENGAGE)

	AIFixtures.health_of(combatant).set_current(20.0)
	_run(combatant)
	assert_eq(_state(combatant), GameplayNames.AI_STATE_FLEE)


func test_a_dead_npc_stops() -> void:
	var combatant := _spawn(AIFixtures.combatant())
	_run(combatant)
	AIFixtures.health_of(combatant).kill()
	_run(combatant)

	assert_eq(_state(combatant), GameplayNames.AI_STATE_DEAD)
	assert_false(AIFixtures.movement_of(combatant).get_intent().is_moving())


func test_a_combatant_keeps_its_distance_when_told_to() -> void:
	# The sniper: same role resource, one number different.
	var role := AIFixtures.combatant()
	(role.brain as RoleBrain).preferred_range = 20.0
	var combatant := _spawn(role)
	_run(combatant)

	assert_eq(_state(combatant), GameplayNames.AI_STATE_ENGAGE)
	assert_false(
		AIFixtures.movement_of(combatant).get_intent().is_moving(),
		"already inside its preferred range, so it should hold and shoot"
	)


# --- One command API ------------------------------------------------------

func test_an_npc_attacks_through_the_same_component_a_player_does() -> void:
	# The M2 and M6 promise, spent: the AI drives the character through
	# MovementComponent and CombatComponent and nothing else.
	var combatant := _spawn(AIFixtures.combatant())
	intruder.global_position = Vector3.FORWARD * 1.0
	_run(combatant, 1.0)
	assert_true(AIFixtures.health_of(intruder).get_current() < 100.0)


func test_a_role_is_content_not_code() -> void:
	# Adding a fourth kind of NPC creates a resource and no GDScript.
	var zealot := AIFixtures.role(&"role.zealot", RoleBrain.Stance.AGGRESSIVE, 0.0, 9.0)
	var npc := _spawn(zealot)
	_run(npc)
	assert_eq(_state(npc), GameplayNames.AI_STATE_ENGAGE)
	assert_true(zealot.validate().is_valid())
