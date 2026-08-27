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

## The recipe's category, for an objective matching "craft any weapon".
var category: StringName = &""

## Who made it.
var crafter: Node = null


static func create(
	p_crafter: Node, p_recipe: RecipeDefinition, p_quantity: int
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
		event.category = p_recipe.category
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_ITEM_CRAFTED


func describe() -> String:
	return "item_crafted: %d x %s from %s" % [quantity, item_id, recipe_id]
