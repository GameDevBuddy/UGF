class_name RecipeDefinition
extends FrameworkDefinition
## What can be made from what.
##
## Adding a recipe to a game creates a [code].tres[/code] and no GDScript
## (rule 15). What it needs, what it makes, how long it takes and where it can
## be done are all data.

## What goes in. Tools are ingredients with [member RecipeIngredient.consumed]
## off.
@export var ingredients: Array[RecipeIngredient] = []

@export_group("Output")
## What comes out.
@export var output_id: StringName = &""

@export_range(1, 9999) var output_quantity: int = 1

## Extra outputs: offcuts, by-products, the bones left from butchering.
@export var extra_outputs: Array[StringName] = []

@export var extra_quantities: Array[int] = []

@export_group("Where and how long")
## Seconds it takes. Zero completes instantly, which is what pocket crafting
## is.
@export_range(0.0, 3600.0, 0.1, "or_greater") var craft_time: float = 0.0

## Station tags required: [code]station.forge[/code],
## [code]station.campfire[/code]. Empty can be made anywhere, which is the
## default and what most simple recipes want.
@export var required_station_tags: Array[StringName] = []

@export_group("Availability")
## Narrative flags that must be raised before this recipe is known. Empty is
## known from the start.
@export var required_flags: Array[StringName] = []

## Vocabulary a UI groups by: [code]recipe.cooking[/code].
@export var category: StringName = &""


func get_consumed() -> Array[RecipeIngredient]:
	return ingredients.filter(
		func(entry: RecipeIngredient) -> bool: return entry != null and entry.consumed
	)


func get_tools() -> Array[RecipeIngredient]:
	return ingredients.filter(
		func(entry: RecipeIngredient) -> bool: return entry != null and entry.is_tool()
	)


func needs_station() -> bool:
	return not required_station_tags.is_empty()


func is_timed() -> bool:
	return craft_time > 0.0


## Whether a station carrying [param tags] can make this.
func station_matches(tags: Array[StringName]) -> bool:
	for required in required_station_tags:
		if not tags.has(required):
			return false
	return true


## Every output as pairs of id and quantity, main output first.
func get_outputs() -> Array[Dictionary]:
	var outputs: Array[Dictionary] = []
	if output_id != &"":
		outputs.append({"item_id": output_id, "quantity": output_quantity})
	var count := mini(extra_outputs.size(), extra_quantities.size())
	for index in count:
		if extra_outputs[index] != &"":
			outputs.append(
				{"item_id": extra_outputs[index], "quantity": extra_quantities[index]}
			)
	return outputs


func describe() -> String:
	var parts := PackedStringArray()
	for entry in ingredients:
		if entry != null:
			parts.append(entry.describe())
	return "%s from %s" % [output_id, String(", ").join(parts)]


func validate() -> ValidationResult:
	var result := super()
	if output_id == &"":
		result.add_error(
			&"recipe.no_output",
			"%s produces nothing." % get_debug_name(),
			resource_path,
			"output_id"
		)
	if ingredients.is_empty():
		result.add_warning(
			&"recipe.no_ingredients",
			(
				"%s needs nothing, so it can be made endlessly from thin air."
			) % get_debug_name(),
			resource_path,
			"ingredients"
		)
	if extra_outputs.size() != extra_quantities.size():
		result.add_error(
			&"recipe.mismatched_extras",
			(
				"%s names %d extra outputs and %d quantities; the extras on one "
				+ "side are never produced."
			) % [get_debug_name(), extra_outputs.size(), extra_quantities.size()],
			resource_path,
			"extra_quantities"
		)
	for entry in ingredients:
		if entry == null:
			result.add_warning(
				&"recipe.empty_ingredient_slot",
				"%s has an empty ingredient slot." % get_debug_name(),
				resource_path,
				"ingredients"
			)
			continue
		if entry.consumed and entry.item_id == output_id and entry.required_tag == &"":
			result.add_warning(
				&"recipe.consumes_its_output",
				(
					"%s consumes what it produces, which is a loop unless the "
					+ "quantities differ deliberately."
				) % get_debug_name(),
				resource_path,
				"ingredients"
			)
		result.merge(entry.validate())
	return result
