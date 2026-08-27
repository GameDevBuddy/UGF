extends FrameworkTestCase
## Regression: what the crafted signal says came out.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


func test_crafting_onto_an_existing_stack_reports_what_came_out() -> void:
	# The bug this guards: InventoryComponent._store() takes ownership of the
	# instance it is handed, and when the whole stack merges into an existing
	# one it does `instance.quantity -= quantity`, leaving the caller holding
	# an object that says zero. CraftingComponent reported that object as what
	# came out, so the second batch of anything announced a quantity of zero
	# and a "craft two rations" objective never advanced.
	#
	# Invisible on the first batch, which is the only path the M12 suite ever
	# exercised.
	var plank := ItemDefinition.new()
	plank.id = &"item.plank"
	plank.display_name = "Plank"
	plank.category = &"item.material"
	plank.max_stack = 99
	core.register_definition(plank)

	var log_item := ItemDefinition.new()
	log_item.id = &"item.log"
	log_item.display_name = "Log"
	log_item.category = &"item.material"
	log_item.max_stack = 99
	core.register_definition(log_item)

	var ingredient := RecipeIngredient.new()
	ingredient.item_id = &"item.log"
	ingredient.quantity = 1

	var recipe := RecipeDefinition.new()
	recipe.id = &"recipe.plank"
	recipe.display_name = "Plank"
	var ingredients: Array[RecipeIngredient] = [ingredient]
	recipe.ingredients = ingredients
	recipe.output_id = &"item.plank"
	recipe.output_quantity = 2

	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Carpenter"
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var profile := InventoryProfile.new()
	profile.slot_count = 20
	inventory.profile_override = profile
	entity.add_child(inventory)

	var crafting := CraftingComponent.new()
	crafting.name = "CraftingComponent"
	crafting.inventory = inventory
	crafting.auto_tick = false
	entity.add_child(crafting)

	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)

	var reported: Array[int] = []
	crafting.crafted.connect(
		func(_recipe: RecipeDefinition, outputs: Array[ItemInstance]) -> void:
			var total := 0
			for instance in outputs:
				total += instance.quantity
			reported.append(total)
	)

	inventory.add(ItemInstance.create(log_item, 4))

	assert_ok(crafting.craft(recipe))
	assert_eq(reported[0], 2, "First batch, into an empty shelf")

	assert_ok(crafting.craft(recipe))
	assert_eq(reported[1], 2, "Second batch, merging onto the first")
