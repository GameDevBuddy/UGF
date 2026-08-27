extends FrameworkTestCase
## Covers RecipeDefinition, RecipeIngredient, CraftingStation and
## CraftingComponent: what can be made from what, where, how long it takes and
## what a cancelled craft costs.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var entity: Node3D = null
var crafting: CraftingComponent = null
var inventory: InventoryComponent = null
var wood: ItemDefinition = null
var plank: ItemDefinition = null
var axe: ItemDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	wood = ItemFixtures.stackable(&"item.wood", 99, 1.0)
	plank = ItemFixtures.stackable(&"item.plank", 99, 0.5)
	axe = SurvivalFixtures.tool_item(&"item.axe", &"tool.axe", 100.0)
	for definition in [wood, plank, axe]:
		core.get_definition_registry().register(definition)

	entity = SurvivalFixtures.survivor("Crafter")
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	crafting = SurvivalFixtures.find(entity, CraftingComponent) as CraftingComponent
	inventory = SurvivalFixtures.find(entity, InventoryComponent) as InventoryComponent


func _carry(definition: ItemDefinition, quantity: int = 1) -> ItemInstance:
	assert_ok(inventory.add(ItemInstance.create(definition, quantity)))
	return inventory.find(definition.id)


func _planks(craft_time: float = 0.0) -> RecipeDefinition:
	return SurvivalFixtures.recipe(
		&"recipe.plank",
		[SurvivalFixtures.ingredient(&"item.wood", 2)],
		&"item.plank",
		4,
		craft_time
	)


# --- Definitions -----------------------------------------------------------

func test_a_recipe_separates_what_is_spent_from_what_is_held() -> void:
	var recipe := SurvivalFixtures.recipe(
		&"recipe.plank",
		[
			SurvivalFixtures.ingredient(&"item.wood", 2),
			SurvivalFixtures.tool_ingredient(&"tool.axe"),
		]
	)
	assert_size(recipe.get_consumed(), 1)
	assert_size(recipe.get_tools(), 1)


func test_a_recipe_with_no_output_is_an_error() -> void:
	var recipe := SurvivalFixtures.recipe(&"recipe.nothing", [], &"")
	assert_true(recipe.validate().has_errors())


func test_a_recipe_that_consumes_its_own_output_is_a_warning() -> void:
	var recipe := SurvivalFixtures.recipe(
		&"recipe.loop", [SurvivalFixtures.ingredient(&"item.plank", 1)], &"item.plank"
	)
	assert_true(recipe.validate().has_warnings())


func test_wear_on_a_consumed_ingredient_is_a_warning() -> void:
	var entry := SurvivalFixtures.ingredient(&"item.wood", 1)
	entry.durability_cost = 5.0
	assert_true(entry.validate().has_warnings())


func test_an_ingredient_naming_nothing_is_an_error() -> void:
	assert_true(RecipeIngredient.new().validate().has_errors())


func test_a_tag_ingredient_matches_any_item_carrying_it() -> void:
	var entry := SurvivalFixtures.tool_ingredient(&"tool.axe")
	assert_true(entry.matches(axe))
	assert_false(entry.matches(wood))


func test_extra_outputs_come_out_alongside_the_main_one() -> void:
	var recipe := _planks()
	var extras: Array[StringName] = [&"item.wood"]
	var quantities: Array[int] = [1]
	recipe.extra_outputs = extras
	recipe.extra_quantities = quantities
	assert_size(recipe.get_outputs(), 2)


func test_mismatched_extra_arrays_are_an_error() -> void:
	var recipe := _planks()
	var extras: Array[StringName] = [&"item.wood", &"item.plank"]
	var quantities: Array[int] = [1]
	recipe.extra_outputs = extras
	recipe.extra_quantities = quantities
	assert_true(recipe.validate().has_errors())


# --- Instant crafting ------------------------------------------------------

func test_crafting_consumes_the_ingredients_and_produces_the_output() -> void:
	_carry(wood, 5)
	assert_ok(crafting.craft(_planks()))
	assert_eq(inventory.count(&"item.wood"), 3)
	assert_eq(inventory.count(&"item.plank"), 4)


func test_crafting_without_the_materials_is_refused() -> void:
	_carry(wood, 1)
	assert_err(crafting.craft(_planks()), &"craft.missing_ingredient")


func test_a_refusal_costs_nothing() -> void:
	_carry(wood, 1)
	assert_err(crafting.craft(_planks()), &"craft.missing_ingredient")
	assert_eq(inventory.count(&"item.wood"), 1)
	assert_eq(inventory.count(&"item.plank"), 0)


func test_crafting_is_announced_with_what_came_out() -> void:
	var produced: Array = []
	crafting.crafted.connect(
		func(_r: RecipeDefinition, outputs: Array[ItemInstance]) -> void:
			for instance in outputs:
				produced.append([instance.get_definition_id(), instance.quantity])
	)
	_carry(wood, 2)
	assert_ok(crafting.craft(_planks()))
	assert_eq(produced, [[&"item.plank", 4]])


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array = []
	crafting.craft_failed.connect(
		func(_r: RecipeDefinition, reason: StringName) -> void: refusals.append(reason)
	)
	assert_err(crafting.craft(_planks()), &"craft.missing_ingredient")
	assert_eq(refusals, [&"craft.missing_ingredient"])


func test_an_unregistered_output_is_refused_rather_than_silently_lost() -> void:
	_carry(wood, 5)
	var recipe := SurvivalFixtures.recipe(
		&"recipe.ghost", [SurvivalFixtures.ingredient(&"item.wood", 2)], &"item.ghost"
	)
	assert_err(crafting.craft(recipe), &"craft.unknown_output")
	assert_eq(inventory.count(&"item.wood"), 5)


func test_a_full_bag_refuses_the_craft_before_anything_is_consumed() -> void:
	# Checking room after consuming is the bug commerce spent a milestone on:
	# the wood would be gone and the planks would be nowhere.
	var tight := SurvivalFixtures.survivor("Tight")
	var bag := SurvivalFixtures.find(tight, InventoryComponent) as InventoryComponent
	bag.profile_override = ItemFixtures.container(1)
	add_test_node(tight)
	SurvivalFixtures.assemble(tight, core)

	assert_ok(bag.add(ItemInstance.create(wood, 10)))
	var maker := SurvivalFixtures.find(tight, CraftingComponent) as CraftingComponent
	assert_true(maker.craft(_planks()).is_err())
	assert_eq(bag.count(&"item.wood"), 10)


# --- Tools -----------------------------------------------------------------

func test_a_tool_is_required_but_not_spent() -> void:
	_carry(wood, 4)
	_carry(axe)
	var recipe := SurvivalFixtures.recipe(
		&"recipe.plank",
		[
			SurvivalFixtures.ingredient(&"item.wood", 2),
			SurvivalFixtures.tool_ingredient(&"tool.axe", 0.0),
		]
	)
	assert_ok(crafting.craft(recipe))
	assert_eq(inventory.count(&"item.axe"), 1, "the axe stays")
	assert_eq(inventory.count(&"item.wood"), 2)


func test_a_missing_tool_refuses_the_craft() -> void:
	_carry(wood, 4)
	var recipe := SurvivalFixtures.recipe(
		&"recipe.plank",
		[
			SurvivalFixtures.ingredient(&"item.wood", 2),
			SurvivalFixtures.tool_ingredient(&"tool.axe"),
		]
	)
	assert_err(crafting.craft(recipe), &"craft.missing_ingredient")


func test_a_tool_wears_with_use() -> void:
	_carry(wood, 10)
	var tool := _carry(axe)
	var recipe := SurvivalFixtures.recipe(
		&"recipe.plank",
		[
			SurvivalFixtures.ingredient(&"item.wood", 2),
			SurvivalFixtures.tool_ingredient(&"tool.axe", 20.0),
		]
	)
	assert_ok(crafting.craft(recipe))
	assert_almost_eq(tool.durability, 80.0)
	assert_ok(crafting.craft(recipe))
	assert_almost_eq(tool.durability, 60.0)


func test_a_broken_tool_is_not_a_tool() -> void:
	_carry(wood, 4)
	var tool := _carry(axe)
	tool.degrade(100.0)
	var recipe := SurvivalFixtures.recipe(
		&"recipe.plank",
		[
			SurvivalFixtures.ingredient(&"item.wood", 2),
			SurvivalFixtures.tool_ingredient(&"tool.axe"),
		]
	)
	assert_true(tool.is_broken())
	assert_err(crafting.craft(recipe), &"craft.missing_ingredient")


# --- Stations --------------------------------------------------------------

func test_a_recipe_needing_a_station_is_refused_without_one() -> void:
	_carry(wood, 4)
	var recipe := _planks()
	var tags: Array[StringName] = [&"station.sawmill"]
	recipe.required_station_tags = tags
	assert_err(crafting.craft(recipe), &"craft.wrong_station")


func test_the_wrong_station_is_still_the_wrong_station() -> void:
	_carry(wood, 4)
	var recipe := _planks()
	var tags: Array[StringName] = [&"station.sawmill"]
	recipe.required_station_tags = tags

	var forge := SurvivalFixtures.station([&"station.forge"])
	add_test_node(forge)
	crafting.set_station(forge)
	assert_err(crafting.craft(recipe), &"craft.wrong_station")


func test_the_right_station_allows_it() -> void:
	_carry(wood, 4)
	var recipe := _planks()
	var tags: Array[StringName] = [&"station.sawmill"]
	recipe.required_station_tags = tags

	var mill := SurvivalFixtures.station([&"station.sawmill", &"station.workbench"])
	add_test_node(mill)
	crafting.set_station(mill)
	assert_ok(crafting.craft(recipe))


func test_a_disabled_station_supports_nothing() -> void:
	var mill := SurvivalFixtures.station([&"station.sawmill"])
	mill.enabled = false
	add_test_node(mill)
	var recipe := _planks()
	var tags: Array[StringName] = [&"station.sawmill"]
	recipe.required_station_tags = tags
	assert_false(mill.supports(recipe))


func test_a_station_speeds_up_or_slows_down_the_work() -> void:
	var recipe := _planks(10.0)
	assert_almost_eq(crafting.get_duration(recipe), 10.0)

	var good := SurvivalFixtures.station([&"station.workbench"], 0.5)
	add_test_node(good)
	crafting.set_station(good)
	assert_almost_eq(crafting.get_duration(recipe), 5.0)


func test_a_station_with_no_tags_is_a_warning() -> void:
	var bare := SurvivalFixtures.station([])
	add_test_node(bare)
	assert_true(bare.validate().has_warnings())


# --- Timed crafting --------------------------------------------------------

func test_a_timed_craft_does_not_finish_immediately() -> void:
	_carry(wood, 4)
	assert_ok(crafting.craft(_planks(4.0)))
	assert_true(crafting.is_crafting())
	assert_eq(inventory.count(&"item.plank"), 0, "not yet")
	assert_eq(inventory.count(&"item.wood"), 2, "but the wood is already spent")


func test_a_timed_craft_finishes_on_the_clock() -> void:
	_carry(wood, 4)
	assert_ok(crafting.craft(_planks(4.0)))
	crafting.tick(2.0)
	assert_almost_eq(crafting.get_progress(), 0.5)
	crafting.tick(2.0)
	assert_false(crafting.is_crafting())
	assert_eq(inventory.count(&"item.plank"), 4)


func test_progress_is_reported_as_it_goes() -> void:
	var steps: Array = []
	crafting.craft_progressed.connect(
		func(_r: RecipeDefinition, progress: float) -> void: steps.append(progress)
	)
	_carry(wood, 4)
	# Quarters, which are exactly representable: 0.2 + 0.1 is not 0.3, and a
	# boundary assertion built on tenths is floating-point luck.
	assert_ok(crafting.craft(_planks(4.0)))
	crafting.tick(1.0)
	crafting.tick(1.0)
	assert_size(steps, 2)
	assert_almost_eq(steps[0], 0.25)
	assert_almost_eq(steps[1], 0.5)


func test_a_second_craft_is_refused_while_one_is_running() -> void:
	_carry(wood, 8)
	assert_ok(crafting.craft(_planks(4.0)))
	assert_err(crafting.craft(_planks(4.0)), &"craft.busy")


func test_cancelling_costs_the_materials() -> void:
	# Cancelling a smelt does not un-melt the ore. Consuming up front is also
	# what stops the same planks being spent on two benches at once.
	_carry(wood, 4)
	assert_ok(crafting.craft(_planks(4.0)))
	crafting.cancel()
	assert_false(crafting.is_crafting())
	assert_eq(inventory.count(&"item.wood"), 2)
	assert_eq(inventory.count(&"item.plank"), 0)


func test_cancelling_is_announced() -> void:
	var reasons: Array = []
	crafting.craft_failed.connect(
		func(_r: RecipeDefinition, reason: StringName) -> void: reasons.append(reason)
	)
	_carry(wood, 4)
	assert_ok(crafting.craft(_planks(4.0)))
	crafting.cancel(&"interrupted")
	assert_eq(reasons, [&"interrupted"])


func test_cancelling_nothing_does_nothing() -> void:
	var reasons: Array = []
	crafting.craft_failed.connect(
		func(_r: RecipeDefinition, reason: StringName) -> void: reasons.append(reason)
	)
	crafting.cancel()
	assert_empty(reasons)


func test_starting_a_craft_is_announced() -> void:
	var started: Array = []
	crafting.craft_started.connect(
		func(recipe: RecipeDefinition) -> void: started.append(recipe.id)
	)
	_carry(wood, 4)
	assert_ok(crafting.craft(_planks(4.0)))
	assert_eq(started, [&"recipe.plank"])


# --- Availability ----------------------------------------------------------

func test_a_recipe_with_no_required_flags_is_known() -> void:
	assert_true(crafting.is_known(_planks()))


func test_a_gated_recipe_is_unknown_until_the_flag_is_raised() -> void:
	var narrative := NarrativeStateService.new()
	add_test_node(narrative)
	crafting.narrative = narrative

	var recipe := _planks()
	var flags: Array[StringName] = [&"flag.learned_carpentry"]
	recipe.required_flags = flags
	assert_false(crafting.is_known(recipe))

	narrative.set_flag(&"flag.learned_carpentry", true)
	assert_true(crafting.is_known(recipe))


func test_a_gated_recipe_without_narrative_is_simply_unknown() -> void:
	# Rule 31: a missing optional module makes the recipe unavailable, not the
	# component broken.
	_carry(wood, 4)
	var recipe := _planks()
	var flags: Array[StringName] = [&"flag.learned_carpentry"]
	recipe.required_flags = flags
	assert_err(crafting.craft(recipe), &"craft.unknown_recipe")


func test_can_craft_answers_without_changing_anything() -> void:
	# A crafting UI greys out a line rather than letting the player click it
	# and be told no, so this has to be side-effect free.
	_carry(wood, 4)
	var recipe := _planks()
	assert_ok(crafting.can_craft(recipe))
	assert_ok(crafting.can_craft(recipe))
	assert_eq(inventory.count(&"item.wood"), 4)


func test_crafting_nothing_is_refused() -> void:
	assert_err(crafting.craft(null), &"craft.no_recipe")
