extends FrameworkEvent
## Somebody made something.
##
## Distinct from [code]item_acquired[/code] on purpose. Both fire when a torch
## appears in a bag, but "craft three torches" and "collect three torches" are
## different objectives, and a game where buying one counts towards the
## crafting quest is a game with a bug in it.
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

## Recipe that was completed.
var recipe_id: StringName = &""

## What came out, by definition id, and how many.
var item_id: StringName = &""

var quantity: int = 0

## The produced item's category, for an objective matching "craft any
## consumable".
##
## The item's category rather than the recipe's: an objective asking for "any
## weapon" is asking about the thing that came out, and a recipe's own category
## is an authoring convenience for grouping a crafting menu.
var category: StringName = &""

## Tags from the produced item's definition, for an objective matching a
## vocabulary rather than one id.
var tags: Array[StringName] = []

## Who made it.
var crafter: Node = null


static func create(
	p_crafter: Node,
	p_recipe: RecipeDefinition,
	p_quantity: int,
	p_definition: ItemDefinition = null
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/crafting/craft_event.gd"
	) as GDScript).new()
	event.crafter = p_crafter
	event.source = p_crafter
	event.quantity = p_quantity
	if p_recipe != null:
		event.recipe_id = p_recipe.id
		event.item_id = p_recipe.output_id
	if p_definition != null:
		event.category = p_definition.category
		event.tags = p_definition.tags.duplicate()
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_ITEM_CRAFTED


func describe() -> String:
	return "item_crafted: %d x %s from %s" % [quantity, item_id, recipe_id]
