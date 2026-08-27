class_name CraftingStation
extends FrameworkComponent
## A workbench, a forge, a campfire.
##
## Carries the tags a recipe asks for and how fast work goes here. Deliberately
## almost empty: what a station [i]is[/i] is a set of tags, and giving it
## behaviour would make "can this recipe be made here?" a question with two
## answers (rule 4).

## What this station counts as: [code]station.forge[/code],
## [code]station.campfire[/code]. A station can carry several, so one bench is
## both a workbench and a tanning rack.
@export var station_tags: Array[StringName] = []

## Multiplier on craft time here. Below one is a better bench.
@export_range(0.05, 10.0, 0.01) var speed_multiplier: float = 1.0

## Whether it can be used at all right now: a forge with no fuel, a bench
## somebody else is at.
@export var enabled: bool = true


func has_tag(tag: StringName) -> bool:
	return station_tags.has(tag)


## Whether [param recipe] can be made here.
func supports(recipe: RecipeDefinition) -> bool:
	if recipe == null or not enabled:
		return false
	return recipe.station_matches(station_tags)


static func find_on(node: Node) -> CraftingStation:
	if node == null:
		return null
	if node is CraftingStation:
		return node as CraftingStation
	for component in DefinitionBinder.collect_components(node):
		if component is CraftingStation:
			return component as CraftingStation
	return null


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if station_tags.is_empty():
		result.add_warning(
			&"station.no_tags",
			(
				"A station with no tags satisfies only recipes that need no "
				+ "station, which need no station."
			),
			"",
			"station_tags"
		)
	return result
