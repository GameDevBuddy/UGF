extends FrameworkTestCase
## Covers RegionDefinition, WorldStateService and RegionTracker: which regions
## exist, which are awake, and who is in them.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var world: WorldStateService = null
var docks: RegionDefinition = null
var hills: RegionDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	docks = WorldFixtures.region(
		&"region.docks",
		[&"region.urban", &"region.coastal"],
		{&"population.ambient": 5, &"population.traffic": 2},
		Vector3.ZERO,
		100.0
	)
	hills = WorldFixtures.region(
		&"region.hills", [&"region.wilderness"], {}, Vector3(1000.0, 0.0, 0.0), 200.0
	)
	world = WorldFixtures.world([docks, hills])
	add_test_node(world)


func _body(entity_name: String = "Body") -> Node3D:
	var node := Node3D.new()
	node.name = entity_name
	add_test_node(node)
	return node


# --- Definition ------------------------------------------------------------

func test_a_region_reports_its_budgets() -> void:
	assert_eq(docks.get_budget(&"population.ambient"), 5)
	assert_eq(docks.get_budget(&"population.nonsense"), -1, "uncapped, not zero")
	assert_true(docks.has_budget_for(&"population.traffic"))


func test_a_zero_budget_is_a_real_budget() -> void:
	# "No traffic here" has to be expressible, which is why uncapped is -1.
	var pedestrian_only := WorldFixtures.region(
		&"region.plaza", [], {&"population.traffic": 0}
	)
	assert_eq(pedestrian_only.get_budget(&"population.traffic"), 0)
	assert_true(pedestrian_only.has_budget_for(&"population.traffic"))


func test_geometry_is_optional() -> void:
	var abstract := WorldFixtures.region(&"region.abstract", [], {})
	assert_false(abstract.has_geometry())
	assert_false(abstract.contains_point(Vector3.ZERO), "membership is not geometric")


func test_a_region_with_geometry_contains_points() -> void:
	assert_true(docks.contains_point(Vector3(50.0, 0.0, 0.0)))
	assert_false(docks.contains_point(Vector3(500.0, 0.0, 0.0)))


func test_distance_is_measured_to_the_edge_not_the_centre() -> void:
	assert_almost_eq(docks.distance_to(Vector3(150.0, 0.0, 0.0)), 50.0)
	assert_almost_eq(docks.distance_to(Vector3(10.0, 0.0, 0.0)), 0.0, 0.001, "inside")


func test_mismatched_budget_arrays_are_an_error() -> void:
	var broken := RegionDefinition.new()
	broken.id = &"region.broken"
	var categories: Array[StringName] = [&"a", &"b"]
	var limits: Array[int] = [1]
	broken.budget_categories = categories
	broken.budget_limits = limits
	assert_true(broken.validate().has_errors())


func test_activation_distance_without_geometry_is_a_warning() -> void:
	var abstract := WorldFixtures.region(&"region.abstract", [], {})
	abstract.activation_distance = 100.0
	assert_true(abstract.validate().has_warnings())


# --- Registration ----------------------------------------------------------

func test_regions_register_and_report() -> void:
	assert_eq(world.get_region_count(), 2)
	assert_true(world.has_region(&"region.docks"))
	assert_eq(world.get_region(&"region.docks"), docks)


func test_a_region_with_no_id_is_refused() -> void:
	assert_err(world.register_region(RegionDefinition.new()), &"world.no_region_id")


func test_registering_the_same_region_twice_is_refused() -> void:
	assert_err(world.register_region(docks), &"world.duplicate_region")


func test_unregistering_a_region_empties_it() -> void:
	var body := _body()
	assert_ok(world.set_entity_region(body, &"region.docks", &"population.ambient"))
	assert_true(world.unregister_region(&"region.docks"))
	assert_false(world.has_region(&"region.docks"))
	assert_false(world.is_placed(body), "and its occupants are no longer placed")


func test_regions_can_be_found_by_tag() -> void:
	# What a spawn definition matches on, so one definition populates every
	# city rather than one per city.
	assert_eq(world.find_regions_with_tag(&"region.urban"), [&"region.docks"])
	assert_eq(world.find_regions_with_tag(&"region.wilderness"), [&"region.hills"])
	assert_empty(world.find_regions_with_tag(&"region.moon"))


# --- Activation ------------------------------------------------------------

func test_regions_start_active_by_default() -> void:
	assert_true(world.is_active(&"region.docks"))
	assert_eq(world.get_active_region_count(), 2)


func test_activation_changes_are_announced_once() -> void:
	var changes: Array = []
	world.region_deactivated.connect(func(id: StringName) -> void: changes.append(["off", id]))
	world.region_activated.connect(func(id: StringName) -> void: changes.append(["on", id]))

	assert_true(world.set_active(&"region.docks", false))
	assert_false(world.set_active(&"region.docks", false), "already off")
	assert_true(world.set_active(&"region.docks", true))
	assert_eq(changes, [["off", &"region.docks"], ["on", &"region.docks"]])


func test_activation_can_follow_an_observer() -> void:
	docks.activation_distance = 50.0
	hills.activation_distance = 50.0
	world.set_active(&"region.docks", false)
	world.set_active(&"region.hills", false)

	assert_eq(world.refresh_activation(Vector3.ZERO), 1)
	assert_true(world.is_active(&"region.docks"))
	assert_false(world.is_active(&"region.hills"))

	assert_eq(world.refresh_activation(Vector3(1000.0, 0.0, 0.0)), 2, "one off, one on")
	assert_false(world.is_active(&"region.docks"))
	assert_true(world.is_active(&"region.hills"))


func test_a_region_with_no_activation_distance_is_left_alone() -> void:
	# Explicit activation is a valid choice; a project streaming by its own
	# rules should not have them silently overridden.
	world.set_active(&"region.docks", true)
	world.refresh_activation(Vector3(99999.0, 0.0, 0.0))
	assert_true(world.is_active(&"region.docks"))


# --- Placement -------------------------------------------------------------

func test_an_entity_can_be_placed_and_counted() -> void:
	var body := _body()
	assert_ok(world.set_entity_region(body, &"region.docks", &"population.ambient"))
	assert_eq(world.get_entity_region(body), &"region.docks")
	assert_eq(world.get_entity_category(body), &"population.ambient")
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 1)
	assert_eq(world.get_population(&"region.docks"), 1)


func test_moving_between_regions_moves_the_count_too() -> void:
	var body := _body()
	assert_ok(world.set_entity_region(body, &"region.docks", &"population.ambient"))
	assert_ok(world.set_entity_region(body, &"region.hills", &"population.ambient"))
	assert_eq(world.get_population(&"region.docks"), 0, "and does not double count")
	assert_eq(world.get_population(&"region.hills"), 1)


func test_moving_is_announced_with_both_ends() -> void:
	var moves: Array = []
	world.entity_moved.connect(
		func(_who: Node, from: StringName, to: StringName) -> void: moves.append([from, to])
	)
	var body := _body()
	world.set_entity_region(body, &"region.docks", &"population.ambient")
	world.set_entity_region(body, &"region.hills", &"population.ambient")
	world.remove_entity(body)
	assert_eq(
		moves,
		[
			[&"", &"region.docks"],
			[&"region.docks", &"region.hills"],
			[&"region.hills", &""],
		]
	)


func test_placing_into_a_region_that_does_not_exist_is_refused() -> void:
	assert_err(
		world.set_entity_region(_body(), &"region.atlantis"), &"world.no_such_region"
	)


func test_removing_an_entity_takes_it_out_of_the_count() -> void:
	var body := _body()
	world.set_entity_region(body, &"region.docks", &"population.ambient")
	assert_true(world.remove_entity(body))
	assert_eq(world.get_population(&"region.docks"), 0)
	assert_false(world.is_placed(body))


func test_categories_are_counted_separately() -> void:
	world.set_entity_region(_body("A"), &"region.docks", &"population.ambient")
	world.set_entity_region(_body("B"), &"region.docks", &"population.traffic")
	assert_eq(world.get_population(&"region.docks", &"population.ambient"), 1)
	assert_eq(world.get_population(&"region.docks", &"population.traffic"), 1)
	assert_eq(world.get_population(&"region.docks"), 2)


func test_the_entities_in_a_region_can_be_listed() -> void:
	var one := _body("One")
	var two := _body("Two")
	world.set_entity_region(one, &"region.docks", &"population.ambient")
	world.set_entity_region(two, &"region.docks", &"population.traffic")
	assert_size(world.get_entities_in(&"region.docks"), 2)
	assert_eq(world.get_entities_in(&"region.docks", &"population.traffic"), [two])


func test_a_point_resolves_to_a_region() -> void:
	assert_eq(world.find_region_at(Vector3(10.0, 0.0, 0.0)), &"region.docks")
	assert_eq(world.find_region_at(Vector3(1000.0, 0.0, 0.0)), &"region.hills")
	assert_eq(world.find_region_at(Vector3(0.0, 0.0, 99999.0)), &"")


# --- Budgets ---------------------------------------------------------------

func test_room_runs_out_at_the_budget() -> void:
	for index in 5:
		world.set_entity_region(_body("A%d" % index), &"region.docks", &"population.ambient")
	assert_false(world.has_room(&"region.docks", &"population.ambient"))
	assert_true(world.has_room(&"region.docks", &"population.traffic"))


func test_headroom_reports_what_would_fit() -> void:
	world.set_entity_region(_body(), &"region.docks", &"population.ambient")
	assert_eq(world.get_headroom(&"region.docks", &"population.ambient"), 4)
	assert_eq(
		world.get_headroom(&"region.docks", &"population.nonsense"), -1,
		"an uncapped category is unbounded"
	)


func test_a_total_budget_binds_an_uncapped_category() -> void:
	# Otherwise "unlimited civilians" means unlimited anything.
	docks.total_budget = 3
	for index in 3:
		world.set_entity_region(_body("A%d" % index), &"region.docks", &"population.other")
	assert_false(world.has_room(&"region.docks", &"population.other"))
	assert_eq(world.get_headroom(&"region.docks", &"population.other"), 0)


func test_the_tighter_of_the_two_budgets_wins() -> void:
	docks.total_budget = 2
	world.set_entity_region(_body(), &"region.docks", &"population.ambient")
	assert_eq(
		world.get_headroom(&"region.docks", &"population.ambient"), 1,
		"the total's 1 beats the category's 4"
	)


func test_an_unknown_region_has_no_room() -> void:
	assert_false(world.has_room(&"region.atlantis", &"population.ambient"))


# --- Freed entities --------------------------------------------------------

func test_a_freed_entity_is_not_listed() -> void:
	var body := _body()
	world.set_entity_region(body, &"region.docks", &"population.ambient")
	body.get_parent().remove_child(body)
	body.free()
	assert_empty(world.get_entities_in(&"region.docks"))


func test_pruning_drops_freed_entities_from_the_count() -> void:
	var body := _body()
	world.set_entity_region(body, &"region.docks", &"population.ambient")
	body.get_parent().remove_child(body)
	body.free()
	assert_eq(world.get_population(&"region.docks"), 1, "the count is stale until pruned")
	assert_eq(world.prune(&"region.docks"), 1)
	assert_eq(world.get_population(&"region.docks"), 0)


# --- Persistence -----------------------------------------------------------

func test_which_regions_are_awake_survives_a_save() -> void:
	world.set_active(&"region.docks", false)
	var saved := world.capture_state()

	var other := WorldFixtures.world([docks, hills])
	add_test_node(other)
	other.restore_state(saved)

	assert_true(world.is_persistent())
	assert_false(other.is_active(&"region.docks"))
	assert_true(other.is_active(&"region.hills"))


func test_population_is_not_saved() -> void:
	# The plan's world layer: ambient population is regenerated from
	# definitions rather than persisted, and authored entities save themselves
	# through their own components.
	world.set_entity_region(_body(), &"region.docks", &"population.ambient")
	assert_false(world.capture_state().has("population"))


# --- Tracking --------------------------------------------------------------

func test_a_tracker_registers_its_entity_where_it_stands() -> void:
	var walker := WorldFixtures.tracked("Walker", world)
	walker.position = Vector3(10.0, 0.0, 0.0)
	add_test_node(walker)
	WorldFixtures.assemble(walker, core)

	var tracker := WorldFixtures.find(walker, RegionTracker) as RegionTracker
	assert_true(tracker.is_registered())
	assert_eq(tracker.get_region_id(), &"region.docks")


func test_a_tracker_can_be_told_its_region_explicitly() -> void:
	# What a project's own streaming volume and a teleport call.
	var walker := WorldFixtures.tracked("Walker", world, &"population.ambient", &"region.hills")
	add_test_node(walker)
	WorldFixtures.assemble(walker, core)

	var tracker := WorldFixtures.find(walker, RegionTracker) as RegionTracker
	assert_eq(tracker.get_region_id(), &"region.hills")
	assert_true(tracker.set_region(&"region.docks"))
	assert_eq(world.get_population(&"region.docks"), 1)
	assert_eq(world.get_population(&"region.hills"), 0)


func test_a_region_change_is_announced() -> void:
	var changes: Array = []
	var walker := WorldFixtures.tracked("Walker", world, &"population.ambient", &"region.docks")
	add_test_node(walker)
	WorldFixtures.assemble(walker, core)
	var tracker := WorldFixtures.find(walker, RegionTracker) as RegionTracker
	tracker.region_changed.connect(
		func(from: StringName, to: StringName) -> void: changes.append([from, to])
	)
	tracker.set_region(&"region.hills")
	assert_eq(changes, [[&"region.docks", &"region.hills"]])


func test_an_entity_leaving_the_tree_leaves_the_count() -> void:
	# Otherwise a region slowly fills with things that no longer exist and
	# stops accepting spawns.
	var walker := WorldFixtures.tracked("Walker", world, &"population.ambient", &"region.docks")
	add_test_node(walker)
	WorldFixtures.assemble(walker, core)
	assert_eq(world.get_population(&"region.docks"), 1)

	walker.get_parent().remove_child(walker)
	walker.free()
	assert_eq(world.get_population(&"region.docks"), 0)


func test_a_tracker_with_no_world_is_inert_rather_than_broken() -> void:
	# Rule 31: a project with no World module installed still runs.
	var walker := WorldFixtures.tracked("Walker", null)
	add_test_node(walker)
	WorldFixtures.assemble(walker, null)
	var tracker := WorldFixtures.find(walker, RegionTracker) as RegionTracker
	assert_false(tracker.is_registered())
	assert_false(tracker.refresh())
	assert_eq(tracker.get_region_id(), &"")
