extends FrameworkTestCase
## Charge fire, aim as a character state, animation-driven hit windows,
## weapon hurtboxes and lock-on targeting -- the rest of Implementation Plan 13
## and 14 that M6 did not build.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


# --- Charge fire ----------------------------------------------------------

func _charge_weapon(charge_time: float = 1.0, minimum: float = 0.25) -> WeaponProfile:
	var profile := CombatFixtures.rifle(20.0, 10, WeaponProfile.FireMode.CHARGE)
	profile.charge_time = charge_time
	profile.minimum_charge = minimum
	profile.charge_multiplier = 3.0
	profile.rate_per_second = 0.0
	return profile


func _armed(profile: WeaponProfile) -> Node3D:
	var entity := CombatFixtures.fighter("Archer", Vector3.ZERO, profile)
	add_test_node(entity)
	CombatFixtures.assemble(entity)
	return entity


func test_a_charge_builds_while_held() -> void:
	var weapon := CombatFixtures.weapon_of(_armed(_charge_weapon(1.0)))
	assert_ok(weapon.begin_charge())
	weapon.tick(0.5)
	assert_almost_eq(weapon.get_charge(), 0.5, 0.01)


func test_a_charge_does_not_build_on_its_own() -> void:
	# A weapon that charged without the trigger held would fire itself the
	# moment the player stopped paying attention.
	var weapon := CombatFixtures.weapon_of(_armed(_charge_weapon(1.0)))
	weapon.tick(0.5)
	assert_eq(weapon.get_charge(), 0.0)


func test_a_full_charge_multiplies_the_damage() -> void:
	var weapon := CombatFixtures.weapon_of(_armed(_charge_weapon(1.0)))
	weapon.begin_charge()
	weapon.tick(1.0)

	var released := weapon.release_charge()

	assert_ok(released)
	assert_almost_eq(float(released.payload), 3.0, 0.01, "The full multiplier")


func test_a_minimum_charge_does_a_weapons_normal_damage() -> void:
	# Not a fraction of it. The charge is a bonus for waiting, not a tax for
	# not waiting long enough.
	var weapon := CombatFixtures.weapon_of(_armed(_charge_weapon(1.0, 0.25)))
	weapon.begin_charge()
	weapon.tick(0.25)

	assert_almost_eq(float(weapon.release_charge().payload), 1.0, 0.01)


func test_releasing_below_the_minimum_costs_nothing() -> void:
	# A tap that fired a limp shot would read as a wasted round rather than as
	# a missed input.
	var entity := _armed(_charge_weapon(1.0, 0.5))
	var weapon := CombatFixtures.weapon_of(entity)
	var before := weapon.get_magazine()
	weapon.begin_charge()
	weapon.tick(0.1)

	assert_err(weapon.release_charge(), &"weapon.charge_too_low")
	assert_eq(weapon.get_magazine(), before, "A round was spent on nothing")
	assert_eq(weapon.get_cooldown_remaining(), 0.0, "And it started a cooldown")


func test_a_wasted_charge_is_kept_rather_than_dumped() -> void:
	# So a player who taps twice accumulates towards a shot instead of
	# starting over each time.
	var weapon := CombatFixtures.weapon_of(_armed(_charge_weapon(1.0, 0.5)))
	weapon.begin_charge()
	weapon.tick(0.3)
	weapon.release_charge()
	assert_almost_eq(weapon.get_charge(), 0.3, 0.01)


func test_a_charge_decays_once_let_go() -> void:
	var profile := _charge_weapon(1.0, 0.5)
	profile.charge_decay_per_second = 1.0
	var weapon := CombatFixtures.weapon_of(_armed(profile))
	weapon.begin_charge()
	weapon.tick(0.4)
	weapon.release_charge()

	weapon.tick(0.3)

	assert_almost_eq(weapon.get_charge(), 0.1, 0.01)


func test_charging_an_empty_magazine_is_refused() -> void:
	# A charge that built on an empty weapon is a player holding a trigger for
	# a shot that was never going to happen.
	var entity := _armed(_charge_weapon(1.0))
	var weapon := CombatFixtures.weapon_of(entity)
	while not weapon.is_magazine_empty():
		weapon.consume_shot()
	assert_err(weapon.begin_charge(), &"weapon.empty")


func test_a_weapon_that_releases_at_full_stops_charging_there() -> void:
	var profile := _charge_weapon(1.0)
	profile.releases_at_full = true
	var weapon := CombatFixtures.weapon_of(_armed(profile))
	weapon.begin_charge()
	weapon.tick(1.2)

	assert_false(weapon.is_charging(), "It let go by itself")
	assert_almost_eq(float(weapon.release_charge().payload), 3.0, 0.01)


func test_the_charge_reaches_the_damage() -> void:
	# The whole chain: profile to weapon to attack context to damage.
	var attacker := CombatFixtures.fighter(
		"Archer", Vector3.ZERO, _charge_weapon(1.0)
	)
	var target := CombatFixtures.dummy("Target", Vector3(0.0, 0.0, -1.0), 200.0)
	add_test_node(attacker)
	add_test_node(target)
	CombatFixtures.assemble(attacker)
	CombatFixtures.assemble(target)

	var combat := CombatFixtures.combat_of(attacker)
	var provider := FakeHitProvider.new()
	var reachable: Array[Node3D] = [target]
	provider.targets = reachable
	combat.set_hit_provider(provider)

	var weapon := CombatFixtures.weapon_of(attacker)
	weapon.begin_charge()
	weapon.tick(1.0)
	var scale := float(weapon.release_charge().payload)

	combat.attack(false, scale)
	combat.tick(1.0)

	var health := CombatFixtures.health_of(target)
	assert_eq(health.get_current(), 140.0, "Twenty at triple charge is sixty")


func test_an_uncharged_weapon_is_unaffected() -> void:
	var weapon := CombatFixtures.weapon_of(_armed(CombatFixtures.rifle()))
	assert_err(weapon.begin_charge(), &"weapon.not_charged")


# --- Aim as a character state --------------------------------------------

func test_aiming_tightens_the_cone() -> void:
	var entity := _armed(CombatFixtures.rifle())
	var combat := CombatFixtures.combat_of(entity)
	var weapon := CombatFixtures.weapon_of(entity)
	weapon.consume_shot()
	var hip := weapon.get_spread()
	assert_true(hip > 0.0, "There is a cone to tighten")

	combat.set_aiming(true)

	assert_true(weapon.get_spread() < hip, "Aiming did nothing")


func test_the_aim_state_lives_on_the_character_not_the_weapon() -> void:
	# Plan 13 is explicit. Swapping weapons mid-aim keeps the character aiming,
	# which a flag on the weapon would get wrong.
	var entity := _armed(CombatFixtures.rifle())
	var combat := CombatFixtures.combat_of(entity)
	combat.set_aiming(true)

	CombatFixtures.weapon_of(entity).set_profile(CombatFixtures.rifle(50.0))

	assert_true(combat.is_aiming(), "Changing weapon dropped the aim")
	assert_true(CombatFixtures.state_of(entity).has_state(GameplayNames.STATE_AIMING))


func test_a_weapon_with_no_semantic_state_never_tightens() -> void:
	var weapon := WeaponComponent.new()
	weapon.name = "WeaponComponent"
	weapon.profile_override = CombatFixtures.rifle()
	weapon.auto_tick = false
	add_test_node(weapon)
	weapon.initialize(EntityContext.create(weapon, null, core))
	assert_false(weapon.is_aiming())


# --- Animation-driven hit windows ----------------------------------------

func _relay_on(entity: Node) -> AnimationEventRelay:
	var relay := AnimationEventRelay.new()
	relay.name = "AnimationEventRelay"
	relay.record_history = true
	entity.add_child(relay)
	return relay


func test_the_relay_passes_an_event_to_a_subscriber() -> void:
	var entity := add_test_node(Node3D.new())
	var relay := _relay_on(entity)
	relay.initialize(EntityContext.create(entity, null, core))
	var heard: Array[StringName] = []
	relay.subscribe(&"animation.hit", func(_payload: Variant) -> void: heard.append(&"hit"))

	relay.fire(&"animation.hit")

	assert_eq(heard, [&"hit"] as Array[StringName])


func test_the_relay_drops_events_it_was_not_asked_for() -> void:
	# An animation shared between a dozen characters fires events most of them
	# do not care about, and a listener that has to check gets it wrong once.
	var entity := add_test_node(Node3D.new())
	var relay := _relay_on(entity)
	var wanted: Array[StringName] = [&"animation.hit"]
	relay.accepted_events = wanted
	relay.initialize(EntityContext.create(entity, null, core))

	relay.fire(&"animation.footstep")
	relay.fire(&"animation.hit")

	assert_size(relay.get_history(), 1)


func test_an_animation_event_opens_the_damage_window_early() -> void:
	var profile := CombatFixtures.timed_attack(2.0, 0.1, 0.1)
	var attacker := CombatFixtures.fighter("Swordsman")
	var target := CombatFixtures.dummy("Target", Vector3(0.0, 0.0, -1.0))
	add_test_node(attacker)
	add_test_node(target)
	var relay := _relay_on(attacker)
	var combat := CombatFixtures.combat_of(attacker)
	combat.window_from_animation = true
	CombatFixtures.assemble(attacker)
	CombatFixtures.assemble(target)

	var provider := FakeHitProvider.new()
	var reachable: Array[Node3D] = [target]
	provider.targets = reachable
	combat.set_hit_provider(provider)
	combat.profile_override.unarmed = profile

	combat.attack()
	combat.tick(0.1)
	assert_eq(
		CombatFixtures.health_of(target).get_current(),
		100.0,
		"Two seconds of startup have not elapsed"
	)

	relay.fire(&"animation.hit")

	assert_true(
		CombatFixtures.health_of(target).get_current() < 100.0,
		"The animation said now and nothing happened"
	)


func test_a_stray_animation_event_does_not_swing_at_nothing() -> void:
	var attacker := CombatFixtures.fighter("Swordsman")
	add_test_node(attacker)
	var relay := _relay_on(attacker)
	var combat := CombatFixtures.combat_of(attacker)
	combat.window_from_animation = true
	CombatFixtures.assemble(attacker)

	relay.fire(&"animation.hit")

	assert_false(combat.is_attacking())


func test_the_authored_timing_still_works_as_a_backstop() -> void:
	# An animation retimed, renamed or never authored must not leave a sword
	# that never connects and no error anywhere.
	var attacker := CombatFixtures.fighter("Swordsman")
	var target := CombatFixtures.dummy("Target", Vector3(0.0, 0.0, -1.0))
	add_test_node(attacker)
	add_test_node(target)
	_relay_on(attacker)
	var combat := CombatFixtures.combat_of(attacker)
	combat.window_from_animation = true
	CombatFixtures.assemble(attacker)
	CombatFixtures.assemble(target)

	var provider := FakeHitProvider.new()
	var reachable: Array[Node3D] = [target]
	provider.targets = reachable
	combat.set_hit_provider(provider)

	combat.attack()
	combat.tick(1.0)

	assert_true(
		CombatFixtures.health_of(target).get_current() < 100.0,
		"No animation ever fired and the swing did nothing"
	)


# --- Lock-on targeting ----------------------------------------------------

func _seeker(mode: TargetingComponent.Mode) -> TargetingComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Seeker"
	var targeting := TargetingComponent.new()
	targeting.name = "TargetingComponent"
	targeting.mode = mode
	targeting.auto_tick = false
	targeting.acquire_range = 50.0
	entity.add_child(targeting)
	targeting.initialize(EntityContext.create(entity, null, core))
	return targeting


func _mark(position: Vector3, entity_name: String = "Mark") -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = entity_name
	entity.global_position = position
	return entity


func test_free_aim_picks_nothing() -> void:
	var targeting := _seeker(TargetingComponent.Mode.FREE)
	var marks: Array[Node] = [_mark(Vector3(0.0, 0.0, -5.0))]
	targeting.set_candidates(marks)
	targeting.tick(0.1)
	assert_false(targeting.has_target())


func test_a_soft_target_picks_the_nearest_in_the_cone() -> void:
	# Nearest rather than most central: a distant enemy dead ahead is almost
	# never the one being shot at, and an assist that preferred it would fight
	# the player.
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	var far := _mark(Vector3(0.0, 0.0, -30.0), "Far")
	var near := _mark(Vector3(2.0, 0.0, -6.0), "Near")
	var marks: Array[Node] = [far, near]
	targeting.set_candidates(marks)

	targeting.tick(0.1)

	assert_eq(targeting.get_target(), near)


func test_a_soft_target_outside_the_cone_is_ignored() -> void:
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	var marks: Array[Node] = [_mark(Vector3(0.0, 0.0, 8.0), "Behind")]
	targeting.set_candidates(marks)
	targeting.tick(0.1)
	assert_false(targeting.has_target())


func test_a_soft_target_is_given_up_when_it_leaves() -> void:
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	var mark := _mark(Vector3(0.0, 0.0, -6.0))
	var marks: Array[Node] = [mark]
	targeting.set_candidates(marks)
	targeting.tick(0.1)
	assert_true(targeting.has_target())

	mark.global_position = Vector3(0.0, 0.0, 200.0)
	targeting.tick(0.1)

	assert_false(targeting.has_target())


func test_a_soft_target_does_not_flicker_at_the_boundary() -> void:
	# One threshold is the classic way to make an aim assist feel broken.
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	targeting.acquire_arc_degrees = 30.0
	targeting.release_arc_degrees = 60.0
	var mark := _mark(Vector3(0.0, 0.0, -10.0))
	var marks: Array[Node] = [mark]
	targeting.set_candidates(marks)
	targeting.tick(0.1)
	assert_true(targeting.has_target(), "Acquired dead ahead")

	# Now out past the acquire arc but inside the release arc.
	mark.global_position = Vector3(-6.0, 0.0, -10.0)
	targeting.tick(0.1)

	assert_true(targeting.has_target(), "It let go the moment the target drifted")


func test_a_hard_lock_holds_through_what_a_soft_target_gives_up() -> void:
	var targeting := _seeker(TargetingComponent.Mode.HARD)
	var mark := _mark(Vector3(0.0, 0.0, -6.0))
	var marks: Array[Node] = [mark]
	targeting.set_candidates(marks)
	assert_ok(targeting.lock())

	# Straight behind: a soft target would have dropped it two frames ago.
	mark.global_position = Vector3(0.0, 0.0, 6.0)
	targeting.tick(0.1)

	assert_true(targeting.is_locked())
	assert_eq(targeting.get_target(), mark)


func test_a_hard_lock_drops_when_the_target_leaves_range() -> void:
	var targeting := _seeker(TargetingComponent.Mode.HARD)
	var mark := _mark(Vector3(0.0, 0.0, -6.0))
	var marks: Array[Node] = [mark]
	targeting.set_candidates(marks)
	targeting.lock()

	mark.global_position = Vector3(0.0, 0.0, -400.0)
	targeting.tick(0.1)

	assert_false(targeting.is_locked())


func test_locking_onto_nothing_is_refused() -> void:
	# So a caller plays a failure sound rather than showing an empty reticle.
	var targeting := _seeker(TargetingComponent.Mode.HARD)
	assert_err(targeting.lock(), &"targeting.nothing_in_range")


func test_a_lock_can_be_cycled() -> void:
	var targeting := _seeker(TargetingComponent.Mode.HARD)
	var first := _mark(Vector3(-1.0, 0.0, -6.0), "First")
	var second := _mark(Vector3(1.0, 0.0, -7.0), "Second")
	var marks: Array[Node] = [first, second]
	targeting.set_candidates(marks)
	targeting.lock()
	var before := targeting.get_target()

	assert_ok(targeting.cycle())

	assert_ne(targeting.get_target(), before)


func test_cycling_with_one_candidate_is_refused() -> void:
	var targeting := _seeker(TargetingComponent.Mode.HARD)
	var marks: Array[Node] = [_mark(Vector3(0.0, 0.0, -6.0))]
	targeting.set_candidates(marks)
	targeting.lock()
	assert_err(targeting.cycle(), &"targeting.nothing_to_cycle")


func test_the_aim_direction_points_at_the_target() -> void:
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	var marks: Array[Node] = [_mark(Vector3(0.0, 0.0, -6.0))]
	targeting.set_candidates(marks)
	targeting.tick(0.1)

	assert_almost_eq(targeting.get_aim_direction().z, -1.0, 0.01)


func test_a_dead_target_is_not_a_target() -> void:
	var targeting := _seeker(TargetingComponent.Mode.SOFT)
	var corpse := CombatFixtures.dummy("Corpse", Vector3(0.0, 0.0, -6.0))
	add_test_node(corpse)
	CombatFixtures.assemble(corpse)
	var marks: Array[Node] = [corpse]
	targeting.set_candidates(marks)
	targeting.tick(0.1)
	assert_true(targeting.has_target(), "Alive to begin with")

	CombatFixtures.health_of(corpse).kill()
	targeting.tick(0.1)

	assert_false(targeting.has_target())
