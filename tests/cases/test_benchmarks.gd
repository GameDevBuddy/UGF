extends FrameworkTestCase
## M19 benchmarks: the operations a game does thousands of times a frame, and
## the promise that they do not get slower as the world gets bigger.
##
## Every claim here is a claim about [i]shape[/i], not about speed. See
## [BenchmarkHarness] for why: a wall-clock threshold on a shared CI runner is
## a test that fails for reasons unrelated to the change, and a test like that
## gets muted within a month.
##
## The numbers still get printed. A reviewer comparing two runs of the log can
## see a 40% regression that no assertion would ever catch, which is what a
## benchmark report is for.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

## Loaded rather than named: the fixture deliberately has no class_name, so
## it stands in for a module-owned event the way a real one arrives.
const SampleEventScript := preload("res://tests/support/sample_event.gd")

## How much per-call cost may grow between the small and large data sets.
##
## The data sets differ by 50x. An operation that walks its data would come in
## near 50; noise on a loaded runner is worth perhaps 2. Four is far enough
## from both that it answers the only question being asked.
const GROWTH_TOLERANCE: float = 4.0

const SMALL: int = 100
const LARGE: int = 5000
const REPEATS: int = 20000

var bus: Node = null
var _spawned: Array[Node] = []


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false


func after_each() -> void:
	# Entities are deliberately kept out of the tree -- the point is to make
	# fifty thousand of them cheaply -- so nothing else will free them.
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	super()


# --- Population queries ---------------------------------------------------

func test_population_queries_do_not_slow_down_as_a_region_fills() -> void:
	# The M14 promise. A structural test already proves no code path scans the
	# tree; this proves the counter it keeps instead is actually a counter.
	var small := _measure_population(SMALL)
	var large := _measure_population(LARGE)

	BenchmarkHarness.report("Population query", [small, large])
	var factor := BenchmarkHarness.growth(small, large)
	assert_true(
		factor < GROWTH_TOLERANCE,
		(
			"get_population() cost grew %.1fx for %dx the entities -- it is counting, not reading."
			% [factor, LARGE / SMALL]
		)
	)


func _measure_population(count: int) -> BenchmarkHarness.Sample:
	var world := WorldFixtures.world([WorldFixtures.region(&"region.city")])
	add_test_node(world)
	for index in count:
		var entity := Node.new()
		entity.name = "Entity%d" % index
		_spawned.append(entity)
		world.set_entity_region(entity, &"region.city", &"npc.pedestrian")

	return BenchmarkHarness.measure(
		"get_population() over %d entities" % count,
		REPEATS,
		func() -> void: world.get_population(&"region.city", &"npc.pedestrian")
	)


# --- Definition lookup ----------------------------------------------------

func test_definition_lookup_does_not_slow_down_as_content_grows() -> void:
	# Rule 32 says content is addressed by semantic id. That is only a good
	# idea if resolving one is a hash lookup; a project with ten thousand
	# definitions resolves ids constantly.
	var small := _measure_lookup(SMALL)
	var large := _measure_lookup(LARGE)

	BenchmarkHarness.report("Definition lookup by id", [small, large])
	var factor := BenchmarkHarness.growth(small, large)
	assert_true(
		factor < GROWTH_TOLERANCE,
		"get_definition() cost grew %.1fx for %dx the content." % [factor, LARGE / SMALL]
	)


func _measure_lookup(count: int) -> BenchmarkHarness.Sample:
	var registry := DefinitionRegistry.new()
	for index in count:
		var definition := ItemDefinition.new()
		definition.id = StringName("bench.item.%d" % index)
		definition.display_name = "Bench %d" % index
		registry.register(definition)

	# Always the last id registered: if anything is walking the collection,
	# the entry at the end is where it shows.
	var target := StringName("bench.item.%d" % (count - 1))
	return BenchmarkHarness.measure(
		"get_definition() among %d definitions" % count,
		REPEATS,
		func() -> void: registry.get_definition(target)
	)


# --- Event publication ----------------------------------------------------

func test_publishing_does_not_slow_down_as_more_event_types_exist() -> void:
	# A full install registers a few hundred event names. Publishing one must
	# cost what its own subscriber list costs and nothing more, or every
	# module a project enables would tax every module it already had.
	var small := _measure_publish(SMALL)
	var large := _measure_publish(LARGE)

	BenchmarkHarness.report("Event publication", [small, large])
	var factor := BenchmarkHarness.growth(small, large)
	assert_true(
		factor < GROWTH_TOLERANCE,
		"publish() cost grew %.1fx for %dx the registered event names." % [factor, LARGE / SMALL]
	)


func _measure_publish(count: int) -> BenchmarkHarness.Sample:
	var local := make_autoload(BUS_SCRIPT, "BenchBus%d" % count)
	local.warn_on_unregistered = false
	for index in count:
		local.register_event(StringName("bench.event.%d" % index))
	local.register_event(SampleEventScript.EVENT_NAME)

	var received: Array[int] = [0]
	local.subscribe(
		SampleEventScript.EVENT_NAME, func(_event: FrameworkEvent) -> void: received[0] += 1
	)

	var event: FrameworkEvent = SampleEventScript.new()
	var sample := BenchmarkHarness.measure(
		"publish() with %d event names registered" % count,
		REPEATS,
		func() -> void: local.publish(event)
	)

	assert_true(received[0] > 0, "The benchmark published to nobody")
	return sample


# --- Service lookup -------------------------------------------------------

func test_service_lookup_does_not_slow_down_as_modules_register() -> void:
	# Rule 25 forbids hot-loop global discovery, and the reason a component is
	# allowed to ask Core for a service at all is that asking is a hash
	# lookup. If it stopped being one, rule 25 would need rewriting.
	var small := _measure_service_lookup(SMALL)
	var large := _measure_service_lookup(LARGE)

	BenchmarkHarness.report("Service lookup by id", [small, large])
	var factor := BenchmarkHarness.growth(small, large)
	assert_true(
		factor < GROWTH_TOLERANCE,
		"get_service() cost grew %.1fx for %dx the services." % [factor, LARGE / SMALL]
	)


func _measure_service_lookup(count: int) -> BenchmarkHarness.Sample:
	var registry := ServiceRegistry.new()
	var held: Array[RefCounted] = []
	for index in count:
		var service := RefCounted.new()
		held.append(service)
		registry.register(StringName("bench.service.%d" % index), service)

	var target := StringName("bench.service.%d" % (count - 1))
	var sample := BenchmarkHarness.measure(
		"get_service() among %d services" % count,
		REPEATS,
		func() -> void: registry.get_service(target)
	)
	registry.clear()
	held.clear()
	return sample


# --- The report -----------------------------------------------------------

func test_hot_path_throughput_is_reported() -> void:
	# No assertion on the numbers, by design. This exists so a reviewer can
	# diff two CI logs and see a regression that is real but well inside any
	# tolerance a test could safely use.
	var samples: Array[BenchmarkHarness.Sample] = []

	var definition := ItemDefinition.new()
	definition.id = &"bench.item.stone"
	definition.display_name = "Stone"
	definition.max_stack = 999

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var bag := InventoryProfile.new()
	bag.slot_count = 64
	inventory.profile_override = bag
	add_test_node(inventory)
	inventory.initialize(EntityContext.create(inventory, null, null))

	samples.append(
		BenchmarkHarness.measure(
			"InventoryComponent.count()",
			REPEATS,
			func() -> void: inventory.count(&"bench.item.stone")
		)
	)

	var modifier := StatModifier.new()
	modifier.stat = &"bench.stat.power"
	modifier.mode = StatModifier.Mode.FLAT
	modifier.value = 5.0
	var modifiers: Array[StatModifier] = [modifier]
	samples.append(
		BenchmarkHarness.measure(
			"StatCalculator.calculate() with 1 modifier",
			REPEATS,
			func() -> void: StatCalculator.calculate(10.0, modifiers, &"bench.stat.power")
		)
	)

	var intent := MovementIntent.new()
	intent.direction = Vector3(0.0, 0.0, -1.0)
	var profile := MovementProfile.new()
	samples.append(
		BenchmarkHarness.measure(
			"MovementSolver.solve_planar_velocity()",
			REPEATS,
			func() -> void: MovementSolver.solve_planar_velocity(
				Vector3(1.0, 0.0, 0.0), intent, profile, true, 0.016
			)
		)
	)

	BenchmarkHarness.report("Hot path throughput (reported, not asserted)", samples)
	assert_true(samples.size() == 3, "Every hot-path sample was collected")
