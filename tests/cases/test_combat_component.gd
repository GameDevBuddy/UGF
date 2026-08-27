extends FrameworkTestCase
## Covers CombatComponent, and holds the M6 exit gate: ranged and melee
## producing the same DamageContext, and an AI attacking through the same
## command API a player uses.

var provider: FakeHitProvider = null
var attacker: Node3D = null
var combat: CombatComponent = null
var weapon: WeaponComponent = null
var dummy: Node3D = null


func before_each() -> void:
	provider = FakeHitProvider.new()
	provider.wall = add_test_node(Node.new())

	attacker = add_test_node(CombatFixtures.fighter("Player")) as Node3D
	CombatFixtures.assemble(attacker)
	combat = CombatFixtures.combat_of(attacker)
	weapon = CombatFixtures.weapon_of(attacker)
	combat.set_hit_provider(provider)
	combat.set_rng(_rng())

	dummy = add_test_node(CombatFixtures.dummy("Dummy", Vector3.FORWARD * 1.0)) as Node3D
	CombatFixtures.assemble(dummy)
	provider.targets.append(dummy)


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _health() -> float:
	return CombatFixtures.health_of(dummy).get_current()


func _arm(profile: WeaponProfile) -> void:
	weapon.set_profile(profile, &"item.test_weapon")


# --- Unarmed --------------------------------------------------------------

func test_an_unarmed_entity_punches() -> void:
	assert_ok(combat.attack())
	assert_almost_eq(_health(), 95.0)


func test_an_entity_with_no_profile_and_no_weapon_cannot_attack() -> void:
	combat.profile_override = null
	CombatFixtures.assemble(attacker)
	assert_err(combat.attack(), &"combat.no_attack")


func test_an_unarmed_entity_has_no_secondary_attack() -> void:
	assert_err(combat.attack(true), &"combat.no_attack")


# --- Melee and ranged, one pipeline ---------------------------------------

func test_a_sword_swing_lands() -> void:
	_arm(CombatFixtures.sword(30.0))
	assert_ok(combat.attack())
	assert_almost_eq(_health(), 70.0)


func test_a_rifle_shot_lands() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0))
	assert_ok(combat.attack())
	assert_almost_eq(_health(), 80.0)


func test_both_produce_the_same_damage_context() -> void:
	# The exit gate. A sword and a rifle differ in their delivery resource and
	# in nothing else that reaches Health.
	var contexts: Array[DamageContext] = []
	combat.attack_landed.connect(
		func(_hit: CombatHit, damage: DamageContext) -> void: contexts.append(damage)
	)

	_arm(CombatFixtures.sword(30.0))
	combat.attack()

	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0))
	combat.attack()

	assert_size(contexts, 2)
	for damage in contexts:
		assert_eq(damage.instigator, attacker)
		assert_eq(damage.weapon_id, &"item.test_weapon")
		assert_has(damage.tags, GameplayNames.DAMAGE_PHYSICAL)
		assert_true(damage.final_amount > 0.0)
		assert_ne(damage.hit_position, Vector3.ZERO)


func test_a_shot_that_hits_scenery_deals_no_damage_but_is_still_reported() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	provider.wall_distance = 5.0
	_arm(CombatFixtures.rifle(20.0))

	var landed: Array[CombatHit] = []
	combat.attack_landed.connect(
		func(hit: CombatHit, _d: DamageContext) -> void: landed.append(hit)
	)
	combat.attack()
	assert_size(landed, 1)
	assert_almost_eq(_health(), 100.0)


func test_range_falloff_reaches_health() -> void:
	dummy.global_position = Vector3.FORWARD * 45.0
	var profile := CombatFixtures.rifle(20.0)
	var delivery := profile.primary.delivery as HitscanDelivery
	delivery.falloff_start = 30.0
	delivery.falloff_end = 60.0
	delivery.minimum_multiplier = 0.5
	_arm(profile)

	combat.attack()
	assert_almost_eq(_health(), 85.0)


func test_a_swing_sweeps_several_targets() -> void:
	var second := add_test_node(
		CombatFixtures.dummy("Second", Vector3.FORWARD * 1.5)
	) as Node3D
	CombatFixtures.assemble(second)
	provider.targets.append(second)

	_arm(CombatFixtures.sword(30.0))
	combat.attack()
	assert_almost_eq(_health(), 70.0)
	assert_almost_eq(CombatFixtures.health_of(second).get_current(), 70.0)


# --- The state machine ----------------------------------------------------

func test_an_instant_attack_is_over_before_it_returns() -> void:
	_arm(CombatFixtures.sword())
	combat.attack()
	assert_false(combat.is_attacking())
	assert_eq(combat.get_phase(), CombatSolver.Phase.IDLE)


func test_a_timed_attack_waits_for_its_window() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.2, 0.1, 0.2)
	_arm(profile)

	assert_ok(combat.attack())
	assert_true(combat.is_attacking())
	assert_eq(combat.get_phase(), CombatSolver.Phase.STARTUP)
	assert_almost_eq(_health(), 100.0)

	combat.tick(0.25)
	assert_eq(combat.get_phase(), CombatSolver.Phase.ACTIVE)
	assert_almost_eq(_health(), 75.0)

	combat.tick(0.3)
	assert_false(combat.is_attacking())


func test_a_wide_window_still_resolves_once() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.0, 1.0, 0.0)
	_arm(profile)

	combat.attack()
	for step in 5:
		combat.tick(0.1)
	assert_almost_eq(_health(), 75.0)


func test_a_frame_longer_than_the_window_does_not_skip_it() -> void:
	# A short damage window and a bad frame: the attack must still land, or
	# combat silently stops working the moment the game stutters.
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.05, 0.05, 0.05)
	_arm(profile)

	combat.attack()
	combat.tick(1.0)
	assert_almost_eq(_health(), 75.0)
	assert_false(combat.is_attacking())


func test_the_phases_are_announced_in_order() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.2, 0.1, 0.2)
	_arm(profile)

	var events: Array[String] = []
	combat.attack_started.connect(func(_c: AttackContext) -> void: events.append("started"))
	combat.attack_window_opened.connect(func(_c: AttackContext) -> void: events.append("window"))
	combat.attack_finished.connect(func(_c: AttackContext) -> void: events.append("finished"))

	combat.attack()
	combat.tick(0.25)
	combat.tick(0.3)
	assert_eq(events.size(), 3)
	assert_eq(events[0], "started")
	assert_eq(events[1], "window")
	assert_eq(events[2], "finished")


func test_a_second_attack_is_refused_while_one_is_running() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack()
	_arm(profile)
	combat.attack()
	assert_err(combat.attack(), &"combat.busy")


func test_attacking_marks_the_semantic_state() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack()
	_arm(profile)
	var state := CombatFixtures.state_of(attacker)

	combat.attack()
	assert_true(state.has_state(GameplayNames.STATE_ATTACKING))
	combat.tick(1.0)
	assert_false(state.has_state(GameplayNames.STATE_ATTACKING))


func test_progress_climbs_through_an_attack() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.25, 0.25, 0.5)
	_arm(profile)
	combat.attack()
	combat.tick(0.5)
	assert_almost_eq(combat.get_progress(), 0.5)


# --- Interruption ---------------------------------------------------------

func test_cancelling_before_the_window_lands_nothing() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.3, 0.1, 0.1)
	_arm(profile)

	var reasons: Array[StringName] = []
	combat.attack_interrupted.connect(
		func(_c: AttackContext, reason: StringName) -> void: reasons.append(reason)
	)
	combat.attack()
	combat.tick(0.1)
	combat.cancel(&"staggered")

	assert_false(combat.is_attacking())
	assert_almost_eq(_health(), 100.0)
	assert_size(reasons, 1)
	assert_eq(reasons[0], &"staggered")


func test_an_uninterruptible_attack_commits() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.2, 0.1, 0.1)
	profile.primary.interruptible = false
	_arm(profile)

	combat.attack()
	combat.cancel(&"staggered")
	assert_true(combat.is_attacking())

	combat.tick(0.5)
	assert_almost_eq(_health(), 75.0)


func test_an_uninterruptible_attack_can_still_be_forced() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack()
	profile.primary.interruptible = false
	_arm(profile)
	combat.attack()
	combat.cancel(&"despawned", true)
	assert_false(combat.is_attacking())


func test_cancelling_when_idle_does_nothing() -> void:
	var reasons: Array[StringName] = []
	combat.attack_interrupted.connect(
		func(_c: AttackContext, reason: StringName) -> void: reasons.append(reason)
	)
	combat.cancel()
	assert_empty(reasons)


# --- Ammunition and cost --------------------------------------------------

func test_an_empty_weapon_refuses_to_attack() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0, 1))
	assert_ok(combat.attack())
	weapon.tick(1.0)
	assert_err(combat.attack(), &"weapon.empty")


func test_a_refused_attack_spends_nothing() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0, 1))
	combat.attack()
	weapon.tick(1.0)
	combat.attack()
	assert_eq(weapon.get_magazine(), 0)
	assert_almost_eq(_health(), 80.0)


func test_an_attack_spends_stamina() -> void:
	var stats := CombatFixtures.with_stamina(attacker, 100.0)
	var profile := CombatFixtures.sword()
	profile.primary.cost_stat = GameplayNames.STAT_STAMINA
	profile.primary.cost = 30.0
	CombatFixtures.assemble(attacker)
	_arm(profile)

	assert_ok(combat.attack())
	assert_almost_eq(stats.get_current(GameplayNames.STAT_STAMINA), 70.0)


func test_an_attack_that_cannot_be_afforded_is_refused_and_costs_nothing() -> void:
	var stats := CombatFixtures.with_stamina(attacker, 10.0)
	var profile := CombatFixtures.sword()
	profile.primary.cost_stat = GameplayNames.STAT_STAMINA
	profile.primary.cost = 30.0
	CombatFixtures.assemble(attacker)
	_arm(profile)

	assert_err(combat.attack(), &"combat.cost")
	assert_almost_eq(stats.get_current(GameplayNames.STAT_STAMINA), 10.0)
	assert_almost_eq(_health(), 100.0)


func test_the_profile_supplies_a_default_cost_stat() -> void:
	var stats := CombatFixtures.with_stamina(attacker, 100.0)
	var profile := CombatFixtures.sword()
	profile.primary.cost = 25.0
	CombatFixtures.assemble(attacker)
	_arm(profile)

	combat.attack()
	assert_almost_eq(stats.get_current(GameplayNames.STAT_STAMINA), 75.0)


func test_an_attack_costs_nothing_without_stats() -> void:
	var profile := CombatFixtures.sword()
	profile.primary.cost_stat = GameplayNames.STAT_STAMINA
	profile.primary.cost = 30.0
	_arm(profile)
	assert_ok(combat.attack())


# --- Held triggers --------------------------------------------------------

func test_an_automatic_weapon_repeats_while_held() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0, 5, WeaponProfile.FireMode.AUTOMATIC))

	combat.hold()
	for step in 10:
		weapon.tick(0.1)
		combat.tick(0.1)
	assert_eq(weapon.get_magazine(), 0)


func test_releasing_stops_an_automatic_weapon() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0, 5, WeaponProfile.FireMode.AUTOMATIC))

	combat.hold()
	combat.release()
	for step in 10:
		weapon.tick(0.1)
		combat.tick(0.1)
	assert_eq(weapon.get_magazine(), 4)


func test_a_single_shot_weapon_fires_once_however_long_it_is_held() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	_arm(CombatFixtures.rifle(20.0, 5, WeaponProfile.FireMode.SINGLE))

	combat.hold()
	for step in 10:
		weapon.tick(0.1)
		combat.tick(0.1)
	assert_eq(weapon.get_magazine(), 4)


func test_a_burst_fires_its_count_and_stops() -> void:
	dummy.global_position = Vector3.FORWARD * 20.0
	var profile := CombatFixtures.rifle(20.0, 10, WeaponProfile.FireMode.BURST)
	profile.burst_count = 3
	_arm(profile)

	combat.hold()
	combat.release()
	for step in 20:
		weapon.tick(0.1)
		combat.tick(0.1)
	assert_eq(weapon.get_magazine(), 7)


# --- Aim ------------------------------------------------------------------

func test_an_ai_can_aim_without_turning() -> void:
	dummy.global_position = Vector3.RIGHT * 20.0
	_arm(CombatFixtures.rifle(20.0))

	assert_ok(combat.attack())
	assert_almost_eq(_health(), 100.0, 0.01, "a shot straight ahead should miss")

	weapon.tick(1.0)
	combat.aim_at(dummy.global_position)
	assert_ok(combat.attack())
	assert_almost_eq(_health(), 80.0)


func test_clearing_the_aim_override_goes_back_to_facing() -> void:
	combat.aim_at(Vector3.RIGHT * 10.0)
	assert_ne(combat.get_aim_direction(), Vector3.FORWARD)
	combat.clear_aim_override()
	assert_almost_eq(combat.get_aim_direction().distance_to(Vector3.FORWARD), 0.0)


func test_a_zero_aim_direction_is_ignored() -> void:
	combat.set_aim_direction(Vector3.ZERO)
	assert_almost_eq(combat.get_aim_direction().distance_to(Vector3.FORWARD), 0.0)


func test_attacks_come_from_the_profiles_aim_height() -> void:
	var profile := CombatFixtures.combat_profile()
	profile.aim_height = 1.6
	combat.profile_override = profile
	CombatFixtures.assemble(attacker)
	assert_almost_eq(combat.get_aim_origin().y, 1.6)


func test_an_aim_node_overrides_the_entitys_own_transform() -> void:
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	attacker.add_child(muzzle)
	muzzle.global_position = Vector3(0.0, 2.0, -1.0)
	combat.aim = muzzle
	assert_almost_eq(combat.get_aim_origin().distance_to(Vector3(0.0, 2.0, -1.0)), 0.0)


# --- One command API ------------------------------------------------------

func test_an_npc_attacks_through_the_same_call_a_player_does() -> void:
	# The other half of the exit gate. There is no AI path: a behaviour tree
	# calls attack() exactly as a mouse button does.
	var npc := add_test_node(CombatFixtures.fighter("Guard", Vector3.ZERO)) as Node3D
	CombatFixtures.assemble(npc)
	var brain := CombatFixtures.combat_of(npc)
	brain.set_hit_provider(provider)
	CombatFixtures.weapon_of(npc).set_profile(CombatFixtures.sword(30.0))

	assert_ok(brain.attack())
	assert_almost_eq(_health(), 70.0)


func test_the_same_attack_can_be_asked_for_by_anyone_holding_the_component() -> void:
	_arm(CombatFixtures.sword(10.0))
	for caller in 3:
		combat.attack()
		combat.tick(1.0)
	assert_almost_eq(_health(), 70.0)


# --- Seams ----------------------------------------------------------------

func test_the_hit_provider_can_be_replaced() -> void:
	var other := FakeHitProvider.new()
	combat.set_hit_provider(other)
	assert_eq(combat.get_hit_provider(), other)


func test_a_provider_is_built_on_demand_when_none_was_injected() -> void:
	var lone := add_test_node(CombatFixtures.fighter("Lone")) as Node3D
	CombatFixtures.assemble(lone)
	assert_not_null(CombatFixtures.combat_of(lone).get_hit_provider())


func test_an_attack_with_no_delivery_hits_nothing_and_still_completes() -> void:
	var profile := CombatFixtures.sword()
	profile.primary.delivery = null
	_arm(profile)
	assert_ok(combat.attack())
	assert_almost_eq(_health(), 100.0)
	assert_false(combat.is_attacking())
