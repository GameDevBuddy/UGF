extends FrameworkTestCase
## Covers SpawnEntry, SpawnDefinition, EncounterDefinition and DespawnPolicy:
## the content side of M14, with no service and no world.

var narrative: NarrativeStateService = null
var urban: RegionDefinition = null


func before_each() -> void:
	narrative = NarrativeStateService.new()
	add_test_node(narrative)
	urban = WorldFixtures.region(
		&"region.docks", [&"region.urban", &"region.coastal"],
		{&"population.ambient": 10}
	)


# --- Entries ---------------------------------------------------------------

func test_an_entry_with_no_definition_is_an_error() -> void:
	assert_true(SpawnEntry.new().validate().has_errors())


func test_an_inverted_range_is_an_error() -> void:
	var entry := WorldFixtures.entry(&"npc.x", 1.0, 5, 2)
	assert_true(entry.validate().has_errors())


func test_a_weightless_entry_is_a_warning() -> void:
	assert_true(WorldFixtures.entry(&"npc.x", 0.0).validate().has_warnings())


func test_a_fixed_count_needs_no_roll() -> void:
	var entry := WorldFixtures.entry(&"npc.x", 1.0, 3, 3)
	assert_false(entry.rolls_a_range())
	assert_eq(entry.roll_count(WorldFixtures.rng()), 3)


func test_a_range_is_rolled_and_stays_inside_it() -> void:
	var entry := WorldFixtures.entry(&"npc.x", 1.0, 2, 6)
	var low := 999
	var high := 0
	for attempt in 100:
		var count := entry.roll_count(WorldFixtures.rng(attempt))
		low = mini(low, count)
		high = maxi(high, count)
	assert_true(low >= 2 and high <= 6, "got %d..%d" % [low, high])
	assert_true(high > low, "the range should actually vary")


func test_an_entry_falls_back_to_the_pools_category() -> void:
	assert_eq(WorldFixtures.entry().get_category(&"population.ambient"), &"population.ambient")
	var own := WorldFixtures.entry()
	own.category = &"population.traffic"
	assert_eq(own.get_category(&"population.ambient"), &"population.traffic")


func test_an_entry_can_require_a_region_tag() -> void:
	# A gondola tagged region.canal never comes up in a desert.
	var gondola := WorldFixtures.entry(&"vehicle.gondola")
	var required: Array[StringName] = [&"region.canal"]
	gondola.required_region_tags = required
	assert_false(gondola.is_available(urban, narrative))

	var canal := WorldFixtures.region(&"region.canal", [&"region.canal"], {})
	assert_true(gondola.is_available(canal, narrative))


func test_an_entry_can_require_a_flag() -> void:
	var late := WorldFixtures.entry(&"npc.patrol")
	var required: Array[StringName] = [&"flag.curfew"]
	late.required_flags = required
	assert_false(late.is_available(urban, narrative))
	narrative.set_flag(&"flag.curfew", true)
	assert_true(late.is_available(urban, narrative))


func test_a_flagged_entry_is_unavailable_with_no_narrative_installed() -> void:
	# Rule 31: a missing optional module makes the content unavailable, not
	# the framework broken.
	var late := WorldFixtures.entry(&"npc.patrol")
	var required: Array[StringName] = [&"flag.curfew"]
	late.required_flags = required
	assert_false(late.is_available(urban, null))


# --- Pools -----------------------------------------------------------------

func test_a_pool_with_no_entries_is_an_error() -> void:
	var empty := WorldFixtures.pool(&"spawn.empty")
	var none: Array[SpawnEntry] = []
	empty.entries = none
	assert_true(empty.validate().has_errors())


func test_a_pool_applies_to_regions_by_tag() -> void:
	# One "city pedestrians" definition populates every urban region, so
	# adding a district is authoring a region rather than editing spawners.
	var pool := WorldFixtures.pool(&"spawn.pedestrians", [], [&"region.urban"])
	assert_true(pool.applies_to(urban))
	assert_false(pool.applies_to(WorldFixtures.region(&"region.hills", [&"region.wild"], {})))


func test_a_pool_with_no_tags_applies_everywhere() -> void:
	var pool := WorldFixtures.pool(&"spawn.anything", [], [])
	assert_true(pool.applies_to_every_region())
	assert_true(pool.applies_to(WorldFixtures.region(&"region.moon", [], {})))
	assert_true(
		pool.validate().count_of(ValidationIssue.Severity.INFO) > 0, "and says so"
	)


func test_a_disabled_pool_applies_nowhere() -> void:
	var pool := WorldFixtures.pool()
	pool.enabled = false
	assert_false(pool.applies_to(urban))


func test_density_is_applied_to_the_regions_own_budget() -> void:
	# One definition produces a busy centre and a quiet suburb; the difference
	# is authored on the region, where it belongs.
	var pool := WorldFixtures.pool()
	pool.density = 0.5
	assert_eq(pool.get_target_population(urban), 5)

	var quiet := WorldFixtures.region(
		&"region.suburb", [&"region.urban"], {&"population.ambient": 2}
	)
	assert_eq(pool.get_target_population(quiet), 1)


func test_a_hard_ceiling_beats_the_density() -> void:
	var pool := WorldFixtures.pool()
	pool.maximum_per_region = 3
	assert_eq(pool.get_target_population(urban), 3)


func test_a_pool_falls_back_to_the_total_budget() -> void:
	var pool := WorldFixtures.pool(&"spawn.x", [], [&"region.urban"], &"population.other")
	var region := WorldFixtures.region(&"region.plain", [&"region.urban"], {})
	region.total_budget = 8
	assert_eq(pool.get_target_population(region), 8)


func test_a_pool_picks_by_weight() -> void:
	var common := WorldFixtures.entry(&"npc.common", 9.0)
	var rare := WorldFixtures.entry(&"npc.rare", 1.0)
	var pool := WorldFixtures.pool(&"spawn.mixed", [common, rare])

	var rares := 0
	for attempt in 400:
		if pool.pick(urban, narrative, WorldFixtures.rng(attempt)) == rare:
			rares += 1
	assert_true(rares > 10 and rares < 110, "roughly a tenth of 400, got %d" % rares)


func test_a_pool_never_picks_an_unavailable_entry() -> void:
	var gated := WorldFixtures.entry(&"npc.gated", 100.0)
	var required: Array[StringName] = [&"flag.never"]
	gated.required_flags = required
	var plain := WorldFixtures.entry(&"npc.plain", 1.0)
	var pool := WorldFixtures.pool(&"spawn.mixed", [gated, plain])

	for attempt in 20:
		assert_eq(pool.pick(urban, narrative, WorldFixtures.rng(attempt)), plain)


func test_a_pool_with_nothing_available_picks_nothing() -> void:
	var gated := WorldFixtures.entry(&"npc.gated")
	var required: Array[StringName] = [&"flag.never"]
	gated.required_flags = required
	var pool := WorldFixtures.pool(&"spawn.gated", [gated])
	assert_null(pool.pick(urban, narrative, WorldFixtures.rng()))


func test_a_pool_with_no_despawn_policy_says_so() -> void:
	var pool := WorldFixtures.pool()
	pool.despawn = null
	assert_true(pool.validate().count_of(ValidationIssue.Severity.INFO) > 0)


# --- Encounters ------------------------------------------------------------

func test_an_encounter_with_nobody_in_it_is_an_error() -> void:
	var empty := WorldFixtures.encounter(&"encounter.empty")
	var none: Array[SpawnEntry] = []
	empty.members = none
	assert_true(empty.validate().has_errors())


func test_an_impossible_separation_is_a_warning() -> void:
	var crowded := WorldFixtures.encounter()
	crowded.spread = 1.0
	crowded.separation = 5.0
	assert_true(crowded.validate().has_warnings())


func test_members_are_scattered_within_the_spread() -> void:
	var ambush := WorldFixtures.encounter()
	var origin := Vector3(10.0, 0.0, 10.0)
	var positions := ambush.get_member_positions(origin, 4, WorldFixtures.rng())
	assert_size(positions, 4)
	for position in positions:
		assert_true(
			position.distance_to(origin) <= ambush.spread + 0.001,
			"%s escaped the spread" % position
		)


func test_members_are_kept_apart() -> void:
	var ambush := WorldFixtures.encounter()
	ambush.spread = 20.0
	ambush.separation = 2.0
	var positions := ambush.get_member_positions(Vector3.ZERO, 5, WorldFixtures.rng())
	for index in positions.size():
		for other in range(index + 1, positions.size()):
			assert_true(
				positions[index].distance_to(positions[other]) >= 1.9,
				"members %d and %d overlap" % [index, other]
			)


func test_an_unsatisfiable_separation_still_returns_and_does_not_hang() -> void:
	# Bounded attempts on purpose: a slightly crowded squad is a better
	# failure than a frozen frame.
	var impossible := WorldFixtures.encounter()
	impossible.spread = 1.0
	impossible.separation = 10.0
	var positions := impossible.get_member_positions(Vector3.ZERO, 8, WorldFixtures.rng())
	assert_size(positions, 8)


func test_an_encounter_can_be_gated_and_forbidden() -> void:
	var ambush := WorldFixtures.encounter()
	var required: Array[StringName] = [&"flag.act_two"]
	var forbidden: Array[StringName] = [&"flag.truce"]
	ambush.required_flags = required
	ambush.forbidden_flags = forbidden

	assert_false(ambush.is_available(narrative))
	narrative.set_flag(&"flag.act_two", true)
	assert_true(ambush.is_available(narrative))
	narrative.set_flag(&"flag.truce", true)
	assert_false(ambush.is_available(narrative))


func test_an_ungated_encounter_is_available_with_no_narrative() -> void:
	assert_true(WorldFixtures.encounter().is_available(null))


func test_an_encounter_applies_to_regions_by_tag() -> void:
	var ambush := WorldFixtures.encounter()
	var tags: Array[StringName] = [&"region.wilderness"]
	ambush.region_tags = tags
	assert_false(ambush.applies_to(urban))
	assert_true(ambush.applies_to(WorldFixtures.region(&"region.hills", [&"region.wilderness"], {})))


# --- Despawn policies ------------------------------------------------------

func test_something_too_young_is_never_despawned() -> void:
	# Otherwise something spawned just out of sight is removed the same second.
	var policy := WorldFixtures.despawn_policy(50.0, 10.0)
	assert_false(policy.allows_despawn(2.0, 500.0))
	assert_true(policy.allows_despawn(20.0, 500.0))


func test_something_close_by_is_never_despawned() -> void:
	var policy := WorldFixtures.despawn_policy(50.0, 0.0)
	assert_false(policy.allows_despawn(100.0, 10.0))
	assert_true(policy.allows_despawn(100.0, 60.0))


func test_an_expiry_outranks_every_exemption() -> void:
	# Without that, a protected entity in an active region lives forever and
	# the population only ever grows.
	var policy := WorldFixtures.despawn_policy(0.0, 1.0)
	policy.maximum_lifetime = 30.0
	policy.protect_visible = true
	policy.protect_active_regions = true
	assert_true(policy.allows_despawn(40.0, 0.0, true, true))


func test_visibility_protects_when_the_caller_supplies_it() -> void:
	var policy := WorldFixtures.despawn_policy(50.0, 0.0)
	policy.protect_visible = true
	assert_false(policy.allows_despawn(100.0, 500.0, true))
	assert_true(policy.allows_despawn(100.0, 500.0, false))


func test_an_active_region_can_protect_its_population() -> void:
	var policy := WorldFixtures.despawn_policy(50.0, 0.0)
	policy.protect_active_regions = true
	assert_false(policy.allows_despawn(100.0, 500.0, false, true))
	assert_true(policy.allows_despawn(100.0, 500.0, false, false))


func test_a_policy_that_despawns_by_nothing_is_a_warning() -> void:
	var policy := DespawnPolicy.new()
	policy.distance = 0.0
	policy.maximum_lifetime = 0.0
	assert_true(policy.validate().has_warnings())
	assert_false(policy.allows_despawn(9999.0, 9999.0))


func test_an_expiry_inside_the_protection_window_is_an_error() -> void:
	var policy := DespawnPolicy.new()
	policy.minimum_lifetime = 60.0
	policy.maximum_lifetime = 30.0
	assert_true(policy.validate().has_errors())


func test_protected_states_are_checked_separately() -> void:
	var policy := DespawnPolicy.new()
	var protected: Array[StringName] = [&"state.interacting"]
	policy.protected_states = protected
	assert_true(policy.is_protected_by_state([&"state.interacting"] as Array[StringName]))
	assert_false(policy.is_protected_by_state([&"state.moving"] as Array[StringName]))
