extends FrameworkTestCase
## Covers SpawnService and SpawnAnchor: placing things, refusing to, and
## taking them away again.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var world: WorldStateService = null
var spawn: SpawnService = null
var narrative: NarrativeStateService = null
var docks: RegionDefinition = null
var pedestrian: EntityDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	pedestrian = WorldFixtures.spawnable(&"npc.pedestrian")
	core.get_definition_registry().register(pedestrian)

	docks = WorldFixtures.region(
		&"region.docks", [&"region.urban"], {&"population.ambient": 4}, Vector3.ZERO, 100.0
	)
	world = WorldFixtures.world([docks])
	add_test_node(world)

	narrative = NarrativeStateService.new()
	add_test_node(narrative)

	spawn = SpawnService.new()
	spawn.name = "SpawnService"
	add_test_node(spawn)
	spawn.configure(world, core, narrative)
	spawn.set_rng(WorldFixtures.rng())


func _anchor(position: Vector3 = Vector3.ZERO, reuse: float = 0.0) -> SpawnAnchor:
	var anchor := WorldFixtures.anchor(position, &"region.docks", reuse)
	add_test_node(anchor.marker)
	assert_ok(spawn.register_anchor(anchor))
	return anchor


# --- Registration ----------------------------------------------------------

func test_pools_register_and_report() -> void:
	assert_ok(spawn.register_pool(WorldFixtures.pool()))
	assert_size(spawn.get_pools(), 1)


func test_a_pool_with_no_id_is_refused() -> void:
	assert_err(spawn.register_pool(SpawnDefinition.new()), &"spawn.no_pool_id")


func test_the_same_pool_twice_is_refused() -> void:
	var pool := WorldFixtures.pool()
	assert_ok(spawn.register_pool(pool))
	assert_err(spawn.register_pool(pool), &"spawn.duplicate_pool")


func test_anchors_are_bucketed_by_region() -> void:
	# The bucketing that makes placement a lookup rather than a search.
	_anchor()
	_anchor(Vector3(10.0, 0.0, 0.0))
	assert_eq(spawn.get_anchor_count(&"region.docks"), 2)
	assert_eq(spawn.get_anchor_count(&"region.elsewhere"), 0)


func test_an_anchor_can_work_out_its_own_region_once() -> void:
	var anchor := WorldFixtures.anchor(Vector3(10.0, 0.0, 0.0), &"")
	add_test_node(anchor.marker)
	assert_ok(spawn.register_anchor(anchor))
	assert_eq(anchor.get_region_id(), &"region.docks")


func test_an_anchor_standing_nowhere_is_refused() -> void:
	var anchor := WorldFixtures.anchor(Vector3(9999.0, 0.0, 0.0), &"")
	add_test_node(anchor.marker)
	assert_err(spawn.register_anchor(anchor), &"spawn.anchor_outside_regions")


func test_an_anchor_can_be_unregistered() -> void:
	var anchor := _anchor()
	assert_true(spawn.unregister_anchor(anchor))
	assert_eq(spawn.get_anchor_count(&"region.docks"), 0)


# --- Spawning --------------------------------------------------------------

func test_spawning_places_an_entity_and_counts_it() -> void:
	_anchor()
	var pool := WorldFixtures.pool()
	var placed := spawn.spawn_one(pool, &"region.docks")
	assert_ok(placed)
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 1)
	assert_not_null(placed.payload)


func test_a_spawned_entity_is_bound_to_its_definition() -> void:
	# It goes through EntityFactory, so a spawned entity is built exactly the
	# way a loaded one is rather than by a second, subtly different path.
	_anchor()
	var placed := spawn.spawn_one(WorldFixtures.pool(), &"region.docks")
	assert_ok(placed)
	var entity: Node = placed.payload
	var binder := EntitySerializer.find_binder(entity)
	assert_not_null(binder)
	assert_eq(binder.get_definition(), pedestrian)


func test_a_spawned_entity_lands_at_its_anchor() -> void:
	_anchor(Vector3(25.0, 0.0, -5.0))
	var placed := spawn.spawn_one(WorldFixtures.pool(), &"region.docks")
	assert_ok(placed)
	assert_almost_eq((placed.payload as Node3D).global_position.x, 25.0)


func test_spawning_is_announced() -> void:
	var placed: Array = []
	spawn.spawned.connect(
		func(_entity: Node, region: StringName, category: StringName) -> void:
			placed.append([region, category])
	)
	_anchor()
	assert_ok(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"))
	assert_eq(placed, [[&"region.docks", &"population.ambient"]])


func test_spawning_stops_at_the_budget() -> void:
	_anchor()
	var pool := WorldFixtures.pool()
	for index in 4:
		assert_ok(spawn.spawn_one(pool, &"region.docks"))
	assert_err(spawn.spawn_one(pool, &"region.docks"), &"spawn.budget_full")
	assert_eq(world.get_population(&"region.docks"), 4)


func test_spawning_into_a_dormant_region_is_refused() -> void:
	_anchor()
	world.set_active(&"region.docks", false)
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.region_dormant")


func test_spawning_with_no_anchor_is_refused() -> void:
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.no_anchor")


func test_spawning_into_a_region_that_does_not_exist_is_refused() -> void:
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.atlantis"), &"spawn.no_such_region")


func test_a_locked_pool_is_refused() -> void:
	_anchor()
	var pool := WorldFixtures.pool()
	var required: Array[StringName] = [&"flag.act_two"]
	pool.required_flags = required
	assert_err(spawn.spawn_one(pool, &"region.docks"), &"spawn.locked")
	narrative.set_flag(&"flag.act_two", true)
	assert_ok(spawn.spawn_one(pool, &"region.docks"))


func test_a_disabled_service_spawns_nothing() -> void:
	_anchor()
	spawn.enabled = false
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.disabled")


func test_an_unregistered_definition_is_refused_with_a_reason() -> void:
	_anchor()
	var pool := WorldFixtures.pool(&"spawn.ghosts", [WorldFixtures.entry(&"npc.ghost")])
	assert_true(spawn.spawn_one(pool, &"region.docks").is_err())
	assert_eq(world.get_population(&"region.docks"), 0)


func test_every_refusal_is_announced_with_its_reason() -> void:
	# The plan's Spawn Debugger asks for "reasons for rejection", and
	# reconstructing them afterwards is guesswork.
	var reasons: Array = []
	spawn.spawn_refused.connect(
		func(_id: StringName, _region: StringName, reason: StringName) -> void:
			reasons.append(reason)
	)
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.no_anchor")
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.atlantis"), &"spawn.no_such_region")
	assert_eq(reasons, [&"spawn.no_anchor", &"spawn.no_such_region"])


# --- Anchors ---------------------------------------------------------------

func test_an_anchor_cools_down_after_use() -> void:
	# So a doorway does not emit a crowd in one tick.
	var anchor := _anchor(Vector3.ZERO, 5.0)
	var pool := WorldFixtures.pool()
	assert_ok(spawn.spawn_one(pool, &"region.docks"))
	assert_false(anchor.is_ready())
	assert_err(spawn.spawn_one(pool, &"region.docks"), &"spawn.no_anchor")

	anchor.tick(5.0)
	assert_true(anchor.is_ready())
	assert_ok(spawn.spawn_one(pool, &"region.docks"))


func test_a_disabled_anchor_is_not_used() -> void:
	var anchor := _anchor()
	anchor.enabled = false
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.no_anchor")


func test_an_anchor_can_restrict_which_categories_it_accepts() -> void:
	var anchor := _anchor()
	var accepts: Array[StringName] = [&"population.traffic"]
	anchor.accepts_categories = accepts
	assert_err(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"), &"spawn.no_anchor")
	assert_true(anchor.accepts(&"population.traffic"))


func test_scatter_spreads_placements_around_the_anchor() -> void:
	var anchor := _anchor(Vector3(50.0, 0.0, 0.0))
	anchor.scatter = 10.0
	var seen: Array = []
	for attempt in 6:
		var position := anchor.get_spawn_position(WorldFixtures.rng(attempt))
		assert_true(position.distance_to(Vector3(50.0, 0.0, 0.0)) <= 10.001)
		seen.append(position)
	assert_ne(seen[0], seen[1], "a stack of identical pedestrians is the bug")


# --- Ticking ---------------------------------------------------------------

func test_a_tick_tops_a_region_up_to_its_target() -> void:
	_anchor()
	spawn.register_pool(WorldFixtures.pool())
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 4)


func test_a_tick_does_not_exceed_the_target() -> void:
	_anchor()
	spawn.register_pool(WorldFixtures.pool())
	for step in 5:
		spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 4)


func test_a_batch_size_makes_repopulation_a_trickle() -> void:
	_anchor()
	var pool := WorldFixtures.pool()
	pool.batch_size = 1
	pool.interval = 0.0
	spawn.register_pool(pool)

	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 1)
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 2)


func test_an_interval_paces_the_attempts() -> void:
	_anchor()
	var pool := WorldFixtures.pool()
	pool.batch_size = 1
	pool.interval = 10.0
	spawn.register_pool(pool)

	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 1)
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 1, "not yet")
	spawn.tick(10.0)
	assert_eq(world.get_population(&"region.docks"), 2)


func test_a_pool_that_does_not_apply_to_a_region_is_skipped() -> void:
	_anchor()
	spawn.register_pool(WorldFixtures.pool(&"spawn.wildlife", [], [&"region.wilderness"]))
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 0)


# --- Encounters ------------------------------------------------------------

func test_an_encounter_places_everybody_together() -> void:
	var placed: Array = []
	spawn.encounter_spawned.connect(
		func(id: StringName, members: Array[Node]) -> void: placed.append([id, members.size()])
	)
	var ambush := WorldFixtures.encounter(
		&"encounter.ambush",
		[WorldFixtures.entry(), WorldFixtures.entry(), WorldFixtures.entry()]
	)
	assert_ok(spawn.spawn_encounter(ambush, &"region.docks", Vector3.ZERO))
	assert_eq(world.get_population(&"region.docks", &"population.encounter"), 3)
	assert_eq(placed, [[&"encounter.ambush", 3]])


func test_an_encounter_needs_no_anchor() -> void:
	# It is placed where the caller says, which is what "an authored event"
	# means. Registering an anchor for every ambush would be absurd.
	assert_eq(spawn.get_anchor_count(), 0)
	assert_ok(spawn.spawn_encounter(WorldFixtures.encounter(), &"region.docks", Vector3.ZERO))


func test_an_encounter_that_does_not_fit_places_nobody() -> void:
	# Validate-then-mutate: a refused encounter must not leave half an ambush
	# standing about (rule 17).
	docks.budget_categories = [&"population.encounter"] as Array[StringName]
	docks.budget_limits = [2] as Array[int]
	var ambush := WorldFixtures.encounter(
		&"encounter.ambush",
		[WorldFixtures.entry(), WorldFixtures.entry(), WorldFixtures.entry()]
	)
	assert_err(
		spawn.spawn_encounter(ambush, &"region.docks", Vector3.ZERO), &"spawn.budget_full"
	)
	assert_eq(world.get_population(&"region.docks"), 0)


func test_a_locked_encounter_is_refused() -> void:
	var ambush := WorldFixtures.encounter()
	var required: Array[StringName] = [&"flag.act_two"]
	ambush.required_flags = required
	assert_err(spawn.spawn_encounter(ambush, &"region.docks", Vector3.ZERO), &"spawn.locked")


func test_a_one_off_encounter_records_itself_in_the_store_that_exists() -> void:
	# A set of its own would need saving separately; a narrative flag survives
	# a save for free (rule 23).
	var ambush := WorldFixtures.encounter(&"encounter.once")
	assert_false(spawn.has_run(ambush))
	assert_ok(spawn.spawn_encounter(ambush, &"region.docks", Vector3.ZERO))
	assert_true(spawn.has_run(ambush))
	assert_true(narrative.get_flag(&"encounter.encounter.once.run"))


func test_a_repeatable_encounter_waits_out_its_cooldown() -> void:
	var patrol := WorldFixtures.encounter(&"encounter.patrol")
	patrol.repeatable = true
	patrol.cooldown = 30.0
	assert_ok(spawn.spawn_encounter(patrol, &"region.docks", Vector3.ZERO))
	assert_err(
		spawn.spawn_encounter(patrol, &"region.docks", Vector3.ZERO), &"spawn.cooling_down"
	)
	spawn.tick(30.0)
	assert_ok(spawn.spawn_encounter(patrol, &"region.docks", Vector3.ZERO))


func test_an_encounter_with_nobody_in_it_is_refused() -> void:
	var empty := WorldFixtures.encounter(&"encounter.empty")
	var none: Array[SpawnEntry] = []
	empty.members = none
	assert_err(spawn.spawn_encounter(empty, &"region.docks", Vector3.ZERO), &"spawn.no_members")


# --- Despawning ------------------------------------------------------------

func test_despawning_takes_an_entity_out_of_the_count() -> void:
	_anchor()
	var placed := spawn.spawn_one(WorldFixtures.pool(), &"region.docks")
	assert_ok(placed)
	assert_true(spawn.despawn(placed.payload))
	assert_eq(world.get_population(&"region.docks"), 0)
	assert_eq(spawn.get_tracked_count(), 0)


func test_despawning_is_announced_with_its_reason() -> void:
	var removed: Array = []
	spawn.despawned.connect(
		func(_entity: Node, region: StringName, reason: StringName) -> void:
			removed.append([region, reason])
	)
	_anchor()
	var placed := spawn.spawn_one(WorldFixtures.pool(), &"region.docks")
	spawn.despawn(placed.payload, &"despawn.testing")
	assert_eq(removed, [[&"region.docks", &"despawn.testing"]])


func test_a_sweep_removes_what_is_far_away() -> void:
	_anchor(Vector3(80.0, 0.0, 0.0))
	var pool := WorldFixtures.pool()
	pool.despawn = WorldFixtures.despawn_policy(50.0, 0.0)
	assert_ok(spawn.spawn_one(pool, &"region.docks"))

	assert_eq(spawn.sweep(Vector3(79.0, 0.0, 0.0)), 0, "the observer is right there")
	assert_eq(spawn.sweep(Vector3(-500.0, 0.0, 0.0)), 1)
	assert_eq(world.get_population(&"region.docks"), 0)


func test_a_sweep_leaves_what_has_no_policy() -> void:
	# Right for an authored encounter, wrong for traffic — and the difference
	# is data.
	_anchor(Vector3(80.0, 0.0, 0.0))
	var pool := WorldFixtures.pool()
	pool.despawn = null
	assert_ok(spawn.spawn_one(pool, &"region.docks"))
	assert_eq(spawn.sweep(Vector3(-9999.0, 0.0, 0.0)), 0)


func test_a_sweep_respects_protected_states() -> void:
	# Somebody the player is talking to is not ambient any more.
	_anchor(Vector3(80.0, 0.0, 0.0))
	var pool := WorldFixtures.pool()
	pool.despawn = WorldFixtures.despawn_policy(50.0, 0.0)
	var protected: Array[StringName] = [GameplayNames.STATE_INTERACTING]
	pool.despawn.protected_states = protected
	var placed := spawn.spawn_one(pool, &"region.docks")
	assert_ok(placed)

	var state := WorldFixtures.find(placed.payload, SemanticState) as SemanticState
	state.set_state(GameplayNames.STATE_INTERACTING, true)
	assert_eq(spawn.sweep(Vector3(-9999.0, 0.0, 0.0)), 0)

	state.set_state(GameplayNames.STATE_INTERACTING, false)
	assert_eq(spawn.sweep(Vector3(-9999.0, 0.0, 0.0)), 1)


func test_a_whole_region_can_be_emptied() -> void:
	_anchor()
	spawn.register_pool(WorldFixtures.pool())
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 4)
	assert_eq(spawn.despawn_region(&"region.docks"), 4)
	assert_eq(world.get_population(&"region.docks"), 0)


func test_emptying_a_region_leaves_entities_it_did_not_place() -> void:
	# An authored NPC standing in a district is not the spawner's to remove.
	var authored := Node3D.new()
	authored.name = "Authored"
	add_test_node(authored)
	assert_ok(world.set_entity_region(authored, &"region.docks", &"population.ambient"))

	_anchor()
	assert_ok(spawn.spawn_one(WorldFixtures.pool(), &"region.docks"))
	assert_eq(spawn.despawn_region(&"region.docks"), 1)
	assert_eq(world.get_population(&"region.docks"), 1, "the authored one stays")


# --- Adoption --------------------------------------------------------------

func test_an_authored_entity_can_be_adopted_into_the_budget() -> void:
	var authored := Node3D.new()
	authored.name = "Authored"
	add_test_node(authored)
	assert_ok(spawn.adopt(authored, &"region.docks", &"population.ambient"))
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 1)
	assert_eq(spawn.get_tracked_count(), 1)


func test_an_adopted_entity_can_be_swept_like_any_other() -> void:
	var authored := Node3D.new()
	authored.name = "Authored"
	authored.position = Vector3(80.0, 0.0, 0.0)
	add_test_node(authored)
	assert_ok(
		spawn.adopt(
			authored, &"region.docks", &"population.ambient",
			WorldFixtures.despawn_policy(50.0, 0.0)
		)
	)
	assert_eq(spawn.sweep(Vector3(-500.0, 0.0, 0.0)), 1)


func test_adopting_into_a_region_that_does_not_exist_is_refused() -> void:
	var authored := Node3D.new()
	authored.name = "Authored"
	add_test_node(authored)
	assert_err(spawn.adopt(authored, &"region.atlantis", &"x"), &"world.no_such_region")


# --- Traffic ---------------------------------------------------------------
#
# The plan lists "traffic agents/hooks" as an M14 deliverable. There is no
# traffic class here and there is not meant to be: traffic is a SpawnDefinition
# whose entries are vehicles, whose anchors are lay-bys and whose despawn
# policy is aggressive. These tests are the evidence for that claim, because a
# module doc asserting it proves nothing.

func _traffic_pool() -> SpawnDefinition:
	var car := WorldFixtures.spawnable(&"vehicle.sedan")
	core.get_definition_registry().register(car)
	var pool := WorldFixtures.pool(
		&"spawn.traffic",
		[WorldFixtures.entry(&"vehicle.sedan")],
		[&"region.urban"],
		&"population.traffic"
	)
	pool.despawn = WorldFixtures.despawn_policy(40.0, 0.0)
	return pool


func test_traffic_is_a_category_rather_than_a_class() -> void:
	docks.budget_categories = (
		[&"population.ambient", &"population.traffic"] as Array[StringName]
	)
	docks.budget_limits = [4, 2] as Array[int]
	_anchor()
	spawn.register_pool(WorldFixtures.pool())
	spawn.register_pool(_traffic_pool())

	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 4)
	assert_eq(world.get_population(&"region.docks", &"population.traffic"), 2)
	assert_eq(world.get_population(&"region.docks"), 6)


func test_traffic_and_pedestrians_are_budgeted_independently() -> void:
	# A jammed road must not stop the pavement filling, which is the whole
	# reason budgets are per category rather than one number.
	docks.budget_categories = (
		[&"population.ambient", &"population.traffic"] as Array[StringName]
	)
	docks.budget_limits = [4, 0] as Array[int]
	_anchor()
	spawn.register_pool(WorldFixtures.pool())
	spawn.register_pool(_traffic_pool())

	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks", &"population.traffic"), 0, "no cars here")
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 4)


func test_traffic_despawns_more_aggressively_than_pedestrians() -> void:
	docks.budget_categories = (
		[&"population.ambient", &"population.traffic"] as Array[StringName]
	)
	docks.budget_limits = [2, 2] as Array[int]
	_anchor(Vector3(50.0, 0.0, 0.0))

	var pedestrians := WorldFixtures.pool()
	pedestrians.despawn = WorldFixtures.despawn_policy(200.0, 0.0)
	spawn.register_pool(pedestrians)
	spawn.register_pool(_traffic_pool())
	spawn.tick(1.0)
	assert_eq(world.get_population(&"region.docks"), 4)

	# Far enough for the traffic policy's 40m and not the pedestrians' 200m.
	assert_eq(spawn.sweep(Vector3(-50.0, 0.0, 0.0)), 2)
	assert_eq(world.get_population(&"region.docks", &"population.traffic"), 0)
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 2)


# --- Determinism -----------------------------------------------------------

func test_the_same_seed_produces_the_same_crowd() -> void:
	# Injected RNG, so a test gets the same city twice and a networked game
	# can share the stream rather than each client inventing its own.
	var positions: Array = []
	for attempt in 2:
		var anchor := WorldFixtures.anchor(Vector3.ZERO, &"region.docks", 0.0)
		anchor.scatter = 20.0
		add_test_node(anchor.marker)

		var service := SpawnService.new()
		service.name = "SpawnService%d" % attempt
		add_test_node(service)
		var scratch := WorldFixtures.world([
			WorldFixtures.region(
				&"region.docks", [&"region.urban"], {&"population.ambient": 3}
			)
		])
		add_test_node(scratch)
		service.configure(scratch, core, narrative)
		service.set_rng(WorldFixtures.rng(777))
		assert_ok(service.register_anchor(anchor))
		service.register_pool(WorldFixtures.pool())
		service.tick(1.0)

		var run: Array = []
		for entity in scratch.get_entities_in(&"region.docks"):
			run.append((entity as Node3D).global_position)
		positions.append(run)

	assert_size(positions[0], 3)
	assert_eq(positions[0], positions[1])
