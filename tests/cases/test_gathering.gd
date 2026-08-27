extends FrameworkTestCase
## Covers ResourceNodeDefinition, ResourceNode and HarvestAction: what the
## world gives up when worked, what it costs the tool, and when it comes back.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var harvester: Node3D = null
var inventory: InventoryComponent = null
var wood: ItemDefinition = null
var axe: ItemDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	wood = ItemFixtures.stackable(&"item.wood", 99, 1.0)
	axe = SurvivalFixtures.tool_item(&"item.axe", &"tool.axe", 100.0)
	for definition in [wood, axe]:
		core.get_definition_registry().register(definition)
	core.get_definition_registry().register(
		CommerceFixtures.loot_table(
			&"loot.tree",
			[CommerceFixtures.loot_entry(&"item.wood", 3, 3, 0.0, true)],
			0
		)
	)

	harvester = SurvivalFixtures.survivor("Woodcutter")
	add_test_node(harvester)
	SurvivalFixtures.assemble(harvester, core)
	inventory = SurvivalFixtures.find(harvester, InventoryComponent) as InventoryComponent


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _tree(
	tool_tag: StringName = &"", charges: int = 1, respawn: float = 0.0
) -> ResourceNode:
	var definition := SurvivalFixtures.resource_definition(
		&"node.tree", &"loot.tree", tool_tag, charges
	)
	definition.respawn_time = respawn
	var entity := SurvivalFixtures.resource_node(definition)
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	var node := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
	node.set_rng(_rng())
	return node


func _carry(definition: ItemDefinition, quantity: int = 1) -> ItemInstance:
	assert_ok(inventory.add(ItemInstance.create(definition, quantity)))
	return inventory.find(definition.id)


# --- Definition ------------------------------------------------------------

func test_a_node_with_no_loot_table_is_an_error() -> void:
	var definition := SurvivalFixtures.resource_definition(&"node.empty", &"")
	assert_true(definition.validate().has_errors())


func test_an_unlimited_node_with_a_respawn_time_is_a_warning() -> void:
	var definition := SurvivalFixtures.resource_definition(&"node.spring")
	definition.charges = 0
	definition.respawn_time = 60.0
	assert_true(definition.is_unlimited())
	assert_true(definition.validate().has_warnings())


# --- Harvesting ------------------------------------------------------------

func test_harvesting_puts_the_yield_in_the_bag() -> void:
	var tree := _tree()
	assert_ok(tree.harvest(harvester))
	assert_eq(inventory.count(&"item.wood"), 3)


func test_harvesting_is_announced_with_what_came_out() -> void:
	var yielded: Array = []
	var tree := _tree()
	tree.harvested.connect(
		func(_by: Node, instances: Array[ItemInstance]) -> void:
			for instance in instances:
				yielded.append([instance.get_definition_id(), instance.quantity])
	)
	assert_ok(tree.harvest(harvester))
	assert_eq(yielded, [[&"item.wood", 3]])


func test_a_yield_is_the_same_twice_from_the_same_seed() -> void:
	# Injected RNG, so a test gets the same drop twice and a networked game can
	# share the stream.
	var table := CommerceFixtures.loot_table(
		&"loot.bush", [CommerceFixtures.loot_entry(&"item.wood", 1, 9, 0.0, true)], 0
	)
	core.get_definition_registry().register(table)

	var counts: Array = []
	for attempt in 2:
		var bush_definition := SurvivalFixtures.resource_definition(
			&"node.bush", &"loot.bush"
		)
		var entity := SurvivalFixtures.resource_node(bush_definition)
		add_test_node(entity)
		SurvivalFixtures.assemble(entity, core)
		var bush := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
		bush.set_rng(_rng(99))

		var picker := SurvivalFixtures.survivor("Picker%d" % attempt)
		add_test_node(picker)
		SurvivalFixtures.assemble(picker, core)
		assert_ok(bush.harvest(picker))
		var bag := SurvivalFixtures.find(picker, InventoryComponent) as InventoryComponent
		counts.append(bag.count(&"item.wood"))
	assert_eq(counts[0], counts[1])
	assert_true(counts[0] > 0, "the roll should actually yield something")


func test_a_spent_node_is_refused() -> void:
	var tree := _tree()
	assert_ok(tree.harvest(harvester))
	assert_true(tree.is_depleted())
	assert_err(tree.harvest(harvester), &"node.depleted")


func test_depletion_is_announced() -> void:
	var spent: Array = []
	var tree := _tree(&"", 2)
	tree.depleted.connect(func() -> void: spent.append(1))
	assert_ok(tree.harvest(harvester))
	assert_empty(spent, "one charge left")
	assert_ok(tree.harvest(harvester))
	assert_size(spent, 1)


func test_an_unlimited_node_never_runs_out() -> void:
	var definition := SurvivalFixtures.resource_definition(&"node.spring")
	definition.charges = 0
	var entity := SurvivalFixtures.resource_node(definition)
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	var spring := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
	spring.set_rng(_rng())

	for attempt in 5:
		assert_ok(spring.harvest(harvester))
	assert_false(spring.is_depleted())


func test_harvesting_with_nowhere_to_put_it_is_refused() -> void:
	var rock := Node3D.new()
	rock.name = "Rock"
	add_test_node(rock)
	var tree := _tree()
	assert_err(tree.harvest(rock), &"node.no_inventory")


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array = []
	var tree := _tree()
	tree.harvest_refused.connect(
		func(_by: Node, reason: StringName) -> void: refusals.append(reason)
	)
	assert_ok(tree.harvest(harvester))
	assert_err(tree.harvest(harvester), &"node.depleted")
	assert_eq(refusals, [&"node.depleted"])


func test_an_unregistered_table_yields_nothing() -> void:
	var definition := SurvivalFixtures.resource_definition(&"node.ghost", &"loot.ghost")
	var entity := SurvivalFixtures.resource_node(definition)
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	var ghost := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
	assert_err(ghost.harvest(harvester), &"node.unknown_table")
	assert_eq(ghost.get_charges(), 1, "and the charge is not spent")


# --- Tools -----------------------------------------------------------------

func test_a_node_needing_a_tool_refuses_bare_hands() -> void:
	var tree := _tree(&"tool.axe")
	assert_err(tree.harvest(harvester), &"node.no_tool")


func test_the_right_tool_allows_it() -> void:
	_carry(axe)
	var tree := _tree(&"tool.axe")
	assert_ok(tree.harvest(harvester))
	assert_eq(inventory.count(&"item.wood"), 3)


func test_the_tool_wears() -> void:
	var tool := _carry(axe)
	var tree := _tree(&"tool.axe", 3)
	tree.get_node_definition().tool_wear = 25.0
	assert_ok(tree.harvest(harvester))
	assert_almost_eq(tool.durability, 75.0)
	assert_ok(tree.harvest(harvester))
	assert_almost_eq(tool.durability, 50.0)


func test_a_broken_axe_is_not_an_axe() -> void:
	# Letting a worn-out tool keep working would make durability decorative.
	var tool := _carry(axe)
	tool.degrade(100.0)
	var tree := _tree(&"tool.axe")
	assert_err(tree.harvest(harvester), &"node.no_tool")


func test_find_tool_reports_what_would_be_used() -> void:
	var tree := _tree(&"tool.axe")
	assert_null(tree.find_tool(harvester))
	var tool := _carry(axe)
	assert_eq(tree.find_tool(harvester), tool)


func test_a_node_needing_no_tool_wears_nothing() -> void:
	var tool := _carry(axe)
	var tree := _tree()
	tree.get_node_definition().tool_wear = 50.0
	assert_ok(tree.harvest(harvester))
	assert_almost_eq(tool.durability, 100.0)


# --- Respawn ---------------------------------------------------------------

func test_a_spent_node_comes_back_on_its_timer() -> void:
	var tree := _tree(&"", 1, 30.0)
	assert_ok(tree.harvest(harvester))
	assert_true(tree.is_depleted())
	assert_almost_eq(tree.get_time_until_respawn(), 30.0)

	tree.tick(10.0)
	assert_true(tree.is_depleted())
	assert_almost_eq(tree.get_time_until_respawn(), 20.0)

	tree.tick(20.0)
	assert_false(tree.is_depleted())
	assert_eq(tree.get_charges(), 1)


func test_replenishing_is_announced() -> void:
	var back: Array = []
	var tree := _tree(&"", 1, 5.0)
	tree.replenished.connect(func() -> void: back.append(1))
	assert_ok(tree.harvest(harvester))
	tree.tick(5.0)
	assert_size(back, 1)


func test_a_node_that_never_respawns_stays_spent() -> void:
	var tree := _tree()
	assert_ok(tree.harvest(harvester))
	tree.tick(10000.0)
	assert_true(tree.is_depleted())
	assert_almost_eq(tree.get_time_until_respawn(), 0.0)


# --- Persistence -----------------------------------------------------------

func test_a_worked_node_survives_a_save() -> void:
	var tree := _tree(&"", 3, 60.0)
	assert_ok(tree.harvest(harvester))
	assert_ok(tree.harvest(harvester))
	var saved := tree.capture_state()

	var other := _tree(&"", 3, 60.0)
	other.restore_state(saved)
	assert_true(tree.is_persistent())
	assert_eq(other.get_charges(), 1)


func test_a_partially_respawned_node_survives_a_save() -> void:
	var tree := _tree(&"", 1, 60.0)
	assert_ok(tree.harvest(harvester))
	tree.tick(45.0)
	var saved := tree.capture_state()

	var other := _tree(&"", 1, 60.0)
	other.restore_state(saved)
	assert_almost_eq(other.get_time_until_respawn(), 15.0)


# --- Interaction -----------------------------------------------------------

func test_a_tree_is_chopped_through_the_interaction_pipeline() -> void:
	# The whole point of HarvestAction: a tree is worked through exactly the
	# pipeline a door is opened with, so a timed harvest is an interaction
	# duration and not a second timer beside it.
	var tree := _tree()
	var chop := InteractionFixtures.definition(&"interaction.chop", &"verb.chop", "Chop")
	chop.action = HarvestAction.new()

	var component := InteractionComponent.new()
	component.name = "InteractionComponent"
	var offered: Array[InteractionDefinition] = [chop]
	component.interactions_override = offered
	component.auto_tick = false
	tree.get_parent().add_child(component)

	var interactor := InteractorComponent.new()
	interactor.name = "InteractorComponent"
	interactor.auto_tick = false
	harvester.add_child(interactor)

	SurvivalFixtures.assemble(tree.get_parent(), core)
	SurvivalFixtures.assemble(harvester, core)

	assert_ok(interactor.begin(component))
	assert_eq(inventory.count(&"item.wood"), 3)
	assert_true(tree.is_depleted())


func test_a_spent_tree_offers_nothing_worth_pressing() -> void:
	# can_execute is what makes the refusal legible: the prompt goes away
	# rather than the player being told no after the animation.
	var tree := _tree()
	assert_ok(tree.harvest(harvester))
	var context := InteractionContext.create(harvester, tree.get_parent())
	assert_err(HarvestAction.new().can_execute(context), &"node.depleted")


func test_harvesting_something_that_is_not_a_node_is_refused() -> void:
	var context := InteractionContext.create(harvester, harvester)
	assert_err(HarvestAction.new().execute(context), &"harvest.no_node")
