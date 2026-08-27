class_name SpawnEntry
extends Resource
## One thing a spawn pool can produce.
##
## Names its entity by definition id rather than holding the definition, so a
## pool and everything in it do not have to load each other (rule 32). The
## same shape [LootEntry] has, and for the same reason — but not the same
## class: a loot entry rolls a quantity into a bag, a spawn entry places an
## entity in a world. Sharing the implementation would mean one of them
## carrying the other's fields (rule 23).

## What to spawn, by definition id.
@export var definition_id: StringName = &""

## Relative likelihood within the pool. Zero never comes up.
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight: float = 1.0

## How many of this entry one spawn produces.
@export_range(1, 999) var minimum: int = 1

@export_range(1, 999) var maximum: int = 1

## Which population budget this counts against:
## [code]population.civilian[/code], [code]population.traffic[/code]. Blank
## falls back to the pool's category.
@export var category: StringName = &""

## Narrative flags that must be raised before this entry can come up. Empty is
## always available.
@export var required_flags: Array[StringName] = []

## Region tags this entry needs. A gondola entry tagged
## [code]region.canal[/code] never comes up in a desert.
@export var required_region_tags: Array[StringName] = []


func rolls_a_range() -> bool:
	return maximum > minimum


## How many to place, given an injected generator. Deterministic in a test and
## shareable across network clients, exactly as loot rolls are.
func roll_count(rng: RandomNumberGenerator) -> int:
	if not rolls_a_range():
		return maxi(1, minimum)
	return rng.randi_range(minimum, maxi(minimum, maximum))


func get_category(fallback: StringName = &"") -> StringName:
	return category if category != &"" else fallback


## Whether this entry may be used in a region, given the world's narrative.
## A null narrative means required flags are simply unmet, which is the same
## answer a missing Narrative module gives everywhere else (rule 31).
func is_available(
	region: RegionDefinition, narrative: NarrativeStateService
) -> bool:
	if not required_flags.is_empty():
		if narrative == null or not narrative.has_all_flags(required_flags):
			return false
	if required_region_tags.is_empty():
		return true
	return region != null and region.has_all_region_tags(required_region_tags)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if definition_id == &"":
		result.add_error(
			&"spawn_entry.no_definition",
			"A spawn entry that names no definition can never place anything.",
			resource_path,
			"definition_id"
		)
	if maximum < minimum:
		result.add_error(
			&"spawn_entry.inverted_range",
			(
				"'%s' has a maximum below its minimum, so its range is empty."
			) % definition_id,
			resource_path,
			"maximum"
		)
	if weight <= 0.0:
		result.add_warning(
			&"spawn_entry.never_chosen",
			"'%s' has no weight, so it never comes up." % definition_id,
			resource_path,
			"weight"
		)
	return result
