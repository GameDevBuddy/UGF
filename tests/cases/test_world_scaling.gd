extends FrameworkTestCase
## The M14 exit gate: region population scales without global per-frame scans.
##
## [b]This suite asserts a cost, not a behaviour.[/b] Everything else in M14
## could work perfectly and the milestone would still have failed if the cost
## of a tick grew with the size of the world — and that is not something you
## can see by watching a city look busy. So [SpawnService] reports what it
## actually examined, and these tests assert that the number stays flat as the
## world grows by two orders of magnitude.
##
## Timing is deliberately not used. A timing test on CI is a coin flip; a
## count is a fact.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var world: WorldStateService = null
var spawn: SpawnService = null
var pedestrian: EntityDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	pedestrian = WorldFixtures.spawnable(&"npc.pedestrian")
	core.get_definition_registry().register(pedestrian)

	world = WorldFixtures.world()
	add_test_node(world)

	spawn = SpawnService.new()
	spawn.name = "SpawnService"
	add_test_node(spawn)
	spawn.configure(world, core)
	spawn.set_rng(WorldFixtures.rng())


## Builds [param count] regions, each with an anchor and a crowd already in it.
##
## [param prefix] keeps two builds in one test from colliding — without it the
## second build silently merges into the first's regions and the population
## assertions read as arithmetic errors rather than duplicate ids.
func _build_world(count: int, per_region: int, prefix: String = "region") -> Array[StringName]:
	var ids: Array[StringName] = []
	for index in count:
		var id := StringName("%s.%d" % [prefix, index])
		var definition := WorldFixtures.region(
			id, [&"region.urban"], {&"population.ambient": 1000}
		)
		definition.starts_active = false
		assert_ok(world.register_region(definition))
		ids.append(id)

		var anchor := WorldFixtures.anchor(Vector3(index * 1000.0, 0.0, 0.0), id)
		add_test_node(anchor.marker)
		assert_ok(spawn.register_anchor(anchor))

		for resident in per_region:
			var body := Node3D.new()
			body.name = "Resident_%s_%d_%d" % [prefix, index, resident]
			add_test_node(body)
			# Not asserted per resident: ten thousand of them would drown the
			# report in assertions and say nothing the total below does not.
			world.set_entity_region(body, id, &"population.ambient")
	assert_eq(
		world.get_population(ids[0], &"population.ambient"),
		per_region,
		"the crowd should have registered"
	)
	return ids


# --- The claim ------------------------------------------------------------

func test_a_tick_examines_only_the_regions_that_are_awake() -> void:
	var ids := _build_world(50, 100)
	assert_eq(world.get_total_population(), 5000, "a world worth scanning")

	spawn.register_pool(WorldFixtures.pool())
	world.set_active(ids[0], true)

	spawn.tick(1.0)
	assert_eq(
		spawn.get_last_tick_cost()["regions"], 1,
		"one region awake out of fifty"
	)


func test_the_cost_of_a_tick_does_not_grow_with_the_world() -> void:
	# The claim in one test: same work awake, a hundred times the world.
	spawn.register_pool(WorldFixtures.pool())

	var small := _build_world(1, 10, "small")
	world.set_active(small[0], true)
	spawn.tick(1.0)
	var small_cost: int = spawn.get_last_tick_cost()["regions"]

	var large := _build_world(100, 100, "large")
	for index in range(1, 100):
		# Everything else stays asleep, which is the normal state of a world.
		assert_false(world.is_active(large[index]))
	spawn.tick(1.0)
	var large_cost: int = spawn.get_last_tick_cost()["regions"]

	# Region count rather than population as the evidence the world grew: the
	# spawner is doing its job on the awake region, so population moves for a
	# reason that has nothing to do with the claim under test.
	assert_eq(world.get_region_count(), 101, "the world really did grow")
	assert_true(world.get_total_population() > 10000, "and it is full of people")
	assert_eq(small_cost, large_cost, "and the tick did not grow with either")


func test_a_world_with_nothing_awake_costs_nothing() -> void:
	_build_world(50, 100)
	spawn.register_pool(WorldFixtures.pool())
	spawn.tick(1.0)
	assert_eq(spawn.get_last_tick_cost()["regions"], 0)
	assert_eq(spawn.get_last_tick_cost()["entities"], 0)


func test_a_population_count_is_a_lookup_rather_than_a_walk() -> void:
	# The other half of the claim. If counting meant filtering, every budget
	# check would be a scan and the tick above would be a lie.
	var ids := _build_world(20, 200)
	assert_eq(world.get_population(ids[7], &"population.ambient"), 200)
	assert_eq(world.get_population(ids[7]), 200)
	assert_eq(spawn.get_last_tick_cost()["entities"], 0, "asking cost no examination")


func test_a_sweep_examines_only_the_region_it_is_given() -> void:
	var ids := _build_world(10, 50)
	for id in ids:
		world.set_active(id, true)

	spawn.sweep(Vector3.ZERO, ids[3])
	assert_eq(spawn.get_last_tick_cost()["regions"], 1)
	assert_eq(
		spawn.get_last_tick_cost()["entities"], 50,
		"one region's worth, not the world's 500"
	)


func test_a_sweep_of_every_awake_region_still_skips_the_sleeping_ones() -> void:
	var ids := _build_world(10, 50)
	world.set_active(ids[0], true)
	world.set_active(ids[1], true)

	spawn.sweep(Vector3.ZERO)
	assert_eq(spawn.get_last_tick_cost()["regions"], 2)
	assert_eq(spawn.get_last_tick_cost()["entities"], 100)


# --- The mechanisms that make it true -------------------------------------

func test_nothing_in_the_spawn_or_world_services_scans_the_scene_tree() -> void:
	# The negative asserted directly. A group scan or a tree walk in either
	# file would make every claim above true today and false the first time
	# somebody adds a convenience lookup.
	for path in [
		"res://addons/universal_gameplay/spawn/spawn_service.gd",
		"res://addons/universal_gameplay/world/world_state_service.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_true(source.length() > 0, "%s should be readable" % path)
		# Comments stripped first: this suite is about what the code does, and
		# a doc comment saying "there is no get_nodes_in_group here" failed
		# its own guard on the first run.
		var code := _strip_comments(source)
		for forbidden in [
			"get_nodes_in_group", "get_tree()", "find_children", "get_children("
		]:
			assert_false(
				code.contains(forbidden),
				"%s reaches for %s" % [path.get_file(), forbidden]
			)


func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var trimmed := (line as String).strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func test_neither_service_processes_every_frame() -> void:
	# Ambient simulation is ticked, never framed. A service that quietly turned
	# _process on would pass every count assertion above and still be the thing
	# the exit gate forbids.
	assert_false(world.is_processing())
	assert_false(world.is_physics_processing())
	assert_false(spawn.is_processing())
	assert_false(spawn.is_physics_processing())


func test_an_entity_reports_its_own_region_rather_than_being_found() -> void:
	# The inversion that makes the whole thing possible: the cost is
	# proportional to movement between regions, not to population.
	var here := WorldFixtures.region(
		&"region.here", [&"region.urban"], {}, Vector3.ZERO, 50.0
	)
	var there := WorldFixtures.region(
		&"region.there", [&"region.urban"], {}, Vector3(500.0, 0.0, 0.0), 50.0
	)
	assert_ok(world.register_region(here))
	assert_ok(world.register_region(there))

	var walker := WorldFixtures.tracked("Walker", world)
	add_test_node(walker)
	WorldFixtures.assemble(walker, core)
	var tracker := WorldFixtures.find(walker, RegionTracker) as RegionTracker

	assert_eq(tracker.get_region_id(), &"region.here")
	assert_eq(world.get_population(&"region.here"), 1)

	walker.global_position = Vector3(500.0, 0.0, 0.0)
	assert_true(tracker.refresh())
	assert_eq(tracker.get_region_id(), &"region.there")
	assert_eq(world.get_population(&"region.here"), 0)
	assert_eq(world.get_population(&"region.there"), 1)


func test_an_entity_standing_still_costs_nothing_to_track() -> void:
	# The threshold is the saving: a crowd at a bus stop is never rechecked.
	var here := WorldFixtures.region(
		&"region.here", [&"region.urban"], {}, Vector3.ZERO, 50.0
	)
	assert_ok(world.register_region(here))

	var loiterer := WorldFixtures.tracked("Loiterer", world)
	add_test_node(loiterer)
	WorldFixtures.assemble(loiterer, core)
	var tracker := WorldFixtures.find(loiterer, RegionTracker) as RegionTracker

	for step in 100:
		assert_false(tracker.refresh(), "standing still never rechecks")
	assert_almost_eq(tracker.get_drift(), 0.0)
