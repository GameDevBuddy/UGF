extends FrameworkTestCase
## The M12 exit gate: gather, craft, consume, and needs that survive a save.
##
## What is being asserted is that three modules that do not know about each
## other compose into one loop. Gathering yields through M11's loot tables and
## has never heard of recipes; Crafting reads an inventory and has never heard
## of resource nodes; Survival restores meters and has never heard of either.
## The only thing joining them is the bag they all reach through.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var survivor: Node3D = null
var inventory: InventoryComponent = null
var needs: NeedsComponent = null
var crafting: CraftingComponent = null
var consumer: ConsumerComponent = null

var berries: ItemDefinition = null
var jam: ItemDefinition = null
var knife: ItemDefinition = null
var hunger: NeedDefinition = null
var jam_recipe: RecipeDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	berries = ItemFixtures.stackable(&"item.berries", 99, 0.1)
	jam = SurvivalFixtures.meal(&"item.jam", [&"need.hunger"], [60.0])
	knife = SurvivalFixtures.tool_item(&"item.knife", &"tool.knife", 20.0)
	for definition in [berries, jam, knife]:
		core.get_definition_registry().register(definition)
	core.get_definition_registry().register(
		CommerceFixtures.loot_table(
			&"loot.bush",
			[CommerceFixtures.loot_entry(&"item.berries", 3, 3, 0.0, true)],
			0
		)
	)

	jam_recipe = SurvivalFixtures.recipe(
		&"recipe.jam",
		[
			SurvivalFixtures.ingredient(&"item.berries", 6),
			SurvivalFixtures.tool_ingredient(&"tool.knife", 5.0),
		],
		&"item.jam",
		1,
		2.0
	)
	jam_recipe.required_station_tags = _tags([&"station.campfire"])

	hunger = SurvivalFixtures.need(&"need.hunger", 1.0)
	survivor = SurvivalFixtures.survivor("Survivor", [hunger])
	add_test_node(survivor)
	SurvivalFixtures.assemble(survivor, core)

	inventory = SurvivalFixtures.find(survivor, InventoryComponent) as InventoryComponent
	needs = SurvivalFixtures.find(survivor, NeedsComponent) as NeedsComponent
	crafting = SurvivalFixtures.find(survivor, CraftingComponent) as CraftingComponent
	consumer = SurvivalFixtures.find(survivor, ConsumerComponent) as ConsumerComponent


func _tags(values: Array) -> Array[StringName]:
	var typed: Array[StringName] = []
	typed.assign(values)
	return typed


func _bush(charges: int = 3) -> ResourceNode:
	var definition := SurvivalFixtures.resource_definition(
		&"node.bush", &"loot.bush", &"", charges
	)
	var entity := SurvivalFixtures.resource_node(definition)
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	var node := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	node.set_rng(rng)
	return node


func _campfire() -> CraftingStation:
	var fire := SurvivalFixtures.station([&"station.campfire"])
	add_test_node(fire)
	return fire


# --- The loop --------------------------------------------------------------

func test_gather_craft_consume() -> void:
	var bush := _bush()
	assert_ok(inventory.add(ItemInstance.create(knife, 1)))
	needs.tick(70.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 30.0)

	# Gather: two passes of the bush for the six berries the recipe wants.
	assert_ok(bush.harvest(survivor))
	assert_ok(bush.harvest(survivor))
	assert_eq(inventory.count(&"item.berries"), 6)

	# Craft: at a campfire, over two seconds, wearing the knife.
	crafting.set_station(_campfire())
	assert_ok(crafting.craft(jam_recipe))
	assert_true(crafting.is_crafting())
	assert_eq(inventory.count(&"item.berries"), 0, "spent up front")
	crafting.tick(2.0)
	assert_false(crafting.is_crafting())
	assert_eq(inventory.count(&"item.jam"), 1)
	assert_almost_eq(inventory.find(&"item.knife").durability, 15.0)

	# Consume: the jam becomes hunger, and is gone.
	assert_ok(consumer.consume_by_id(&"item.jam"))
	assert_almost_eq(needs.get_value(&"need.hunger"), 90.0)
	assert_eq(inventory.count(&"item.jam"), 0)


func test_the_loop_stalls_at_each_missing_step_rather_than_half_running() -> void:
	# Every stage refuses cleanly and costs nothing, which is what makes the
	# loop safe to drive from a UI that does not pre-check.
	var bush := _bush()
	crafting.set_station(_campfire())

	assert_err(crafting.craft(jam_recipe), &"craft.missing_ingredient")
	assert_ok(bush.harvest(survivor))
	assert_err(crafting.craft(jam_recipe), &"craft.missing_ingredient")
	assert_ok(bush.harvest(survivor))
	assert_err(crafting.craft(jam_recipe), &"craft.missing_ingredient")
	assert_eq(inventory.count(&"item.berries"), 6, "still six, nothing eaten")

	assert_ok(inventory.add(ItemInstance.create(knife, 1)))
	assert_ok(crafting.craft(jam_recipe))
	assert_err(consumer.consume_by_id(&"item.jam"), &"consume.not_carried")
	crafting.tick(2.0)
	assert_ok(consumer.consume_by_id(&"item.jam"))


func test_the_loop_runs_without_a_campfire_when_the_recipe_does_not_ask_for_one() -> void:
	# Rule 31 at the content level: a station is a requirement of the recipe,
	# not of the module.
	jam_recipe.required_station_tags = _tags([])
	jam_recipe.craft_time = 0.0
	var bush := _bush()
	assert_ok(inventory.add(ItemInstance.create(knife, 1)))
	assert_ok(bush.harvest(survivor))
	assert_ok(bush.harvest(survivor))
	assert_ok(crafting.craft(jam_recipe))
	assert_eq(inventory.count(&"item.jam"), 1)


func test_a_worn_out_knife_stops_the_loop_at_crafting() -> void:
	var bush := _bush()
	var tool := ItemInstance.create(knife, 1)
	tool.degrade(20.0)
	assert_ok(inventory.add(tool))
	assert_ok(bush.harvest(survivor))
	assert_ok(bush.harvest(survivor))
	crafting.set_station(_campfire())
	assert_err(crafting.craft(jam_recipe), &"craft.missing_ingredient")
	assert_eq(inventory.count(&"item.berries"), 6)


func test_the_bush_runs_out_and_comes_back() -> void:
	var bush := _bush(2)
	bush.get_node_definition().respawn_time = 30.0
	assert_ok(bush.harvest(survivor))
	assert_ok(bush.harvest(survivor))
	assert_err(bush.harvest(survivor), &"node.depleted")
	bush.tick(30.0)
	assert_ok(bush.harvest(survivor))
	assert_eq(inventory.count(&"item.berries"), 9)


# --- Save and load ---------------------------------------------------------

func test_the_whole_survivor_survives_a_save() -> void:
	# The other half of the exit gate. Meters, bag and world node all round
	# trip through the same capture/restore pair every persistent component
	# implements -- Survival adds no serialisation of its own.
	var bush := _bush(3)
	assert_ok(inventory.add(ItemInstance.create(knife, 1)))
	assert_ok(bush.harvest(survivor))
	needs.tick(55.0)

	var saved_needs := needs.capture_state()
	var saved_bag := inventory.capture_state()
	var saved_bush := bush.capture_state()

	var loaded := SurvivalFixtures.survivor("Loaded", [hunger])
	add_test_node(loaded)
	SurvivalFixtures.assemble(loaded, core)
	var loaded_needs := SurvivalFixtures.find(loaded, NeedsComponent) as NeedsComponent
	var loaded_bag := (
		SurvivalFixtures.find(loaded, InventoryComponent) as InventoryComponent
	)
	loaded_needs.restore_state(saved_needs)
	loaded_bag.restore_state(saved_bag)

	var other_bush := _bush(3)
	other_bush.restore_state(saved_bush)

	assert_almost_eq(loaded_needs.get_value(&"need.hunger"), 45.0)
	assert_eq(loaded_bag.count(&"item.berries"), 3)
	assert_eq(loaded_bag.count(&"item.knife"), 1)
	assert_eq(other_bush.get_charges(), 2)


func test_a_reloaded_survivor_is_still_hungry() -> void:
	# The failure this guards is the one that would make a survival game
	# unlosable: a save that reset every meter to full.
	needs.set_value(&"need.hunger", 8.0)
	var saved := needs.capture_state()

	var loaded := SurvivalFixtures.survivor("Loaded", [hunger])
	add_test_node(loaded)
	SurvivalFixtures.assemble(loaded, core)
	var loaded_needs := SurvivalFixtures.find(loaded, NeedsComponent) as NeedsComponent
	loaded_needs.restore_state(saved)

	assert_almost_eq(loaded_needs.get_value(&"need.hunger"), 8.0)
	assert_true(loaded_needs.is_critical(&"need.hunger"))
	var state := SurvivalFixtures.find(loaded, SemanticState) as SemanticState
	assert_true(state.has_state(hunger.critical_state))


# --- Removability ----------------------------------------------------------

func test_gathering_and_crafting_work_with_no_needs_at_all() -> void:
	# Rule 10: Survival is deletable. An entity with a bag and a bench can
	# gather and craft with no meters anywhere.
	var maker := Node3D.new()
	maker.name = "Maker"
	var bag := InventoryComponent.new()
	bag.name = "InventoryComponent"
	bag.profile_override = ItemFixtures.container(20)
	maker.add_child(bag)
	var bench := CraftingComponent.new()
	bench.name = "CraftingComponent"
	bench.auto_tick = false
	maker.add_child(bench)
	add_test_node(maker)
	SurvivalFixtures.assemble(maker, core)

	var bush := _bush()
	assert_ok(bag.add(ItemInstance.create(knife, 1)))
	assert_ok(bush.harvest(maker))
	assert_ok(bush.harvest(maker))
	bench.set_station(_campfire())
	assert_ok(bench.craft(jam_recipe))
	bench.tick(2.0)
	assert_eq(bag.count(&"item.jam"), 1)


func test_needs_drain_with_no_crafting_or_gathering_anywhere() -> void:
	var creature := Node3D.new()
	creature.name = "Creature"
	creature.add_child(SurvivalFixtures.needs_component([hunger]))
	add_test_node(creature)
	SurvivalFixtures.assemble(creature, core)

	var meters := SurvivalFixtures.find(creature, NeedsComponent) as NeedsComponent
	meters.tick(30.0)
	assert_almost_eq(meters.get_value(&"need.hunger"), 70.0)
