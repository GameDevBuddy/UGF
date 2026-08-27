class_name RecipeIngredient
extends Resource
## One thing a recipe needs.
##
## [b]Consumed and required are different.[/b] A plank is spent; a hammer is
## held. Modelling both as "an ingredient with a flag" rather than two lists is
## what lets a recipe say "two planks and a hammer" in one array, and what
## makes tool wear a property of the ingredient rather than a special case
## beside it.
##
## Named by item id rather than holding an [ItemDefinition], so a recipe and
## everything it uses do not have to load each other (rule 32).

@export var item_id: StringName = &""

@export_range(1, 9999) var quantity: int = 1

## Whether the ingredient is used up. Off makes it a tool: it must be present
## and it stays.
@export var consumed: bool = true

## Durability taken off a tool per craft. Zero never wears it. Ignored for a
## consumed ingredient, which is destroyed anyway.
@export_range(0.0, 1000.0, 0.1) var durability_cost: float = 0.0

## Match on a tag instead of an id, so "any hammer" is one ingredient rather
## than one per hammer in the game. Takes precedence over
## [member item_id] when set.
@export var required_tag: StringName = &""


func is_tool() -> bool:
	return not consumed


## Whether [param definition] satisfies this ingredient.
func matches(definition: ItemDefinition) -> bool:
	if definition == null:
		return false
	if required_tag != &"":
		return definition.has_tag(required_tag)
	return definition.id == item_id


func describe() -> String:
	var what := String(required_tag) if required_tag != &"" else String(item_id)
	if is_tool():
		return "%s (tool)" % what
	return "%d x %s" % [quantity, what] if quantity > 1 else what


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"" and required_tag == &"":
		result.add_error(
			&"ingredient.names_nothing",
			"An ingredient with neither an item id nor a tag can never be found.",
			resource_path,
			"item_id"
		)
	if consumed and durability_cost > 0.0:
		result.add_warning(
			&"ingredient.wear_on_consumed",
			(
				"'%s' is consumed, so its durability cost is never applied."
			) % describe(),
			resource_path,
			"durability_cost"
		)
	if is_tool() and quantity > 1:
		result.add_info(
			&"ingredient.multiple_tools",
			"'%s' is a tool; needing more than one is unusual." % describe(),
			resource_path,
			"quantity"
		)
	return result
