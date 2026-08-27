class_name LootEntry
extends Resource
## One thing that might drop.
##
## Named by item id rather than holding an [ItemDefinition], so a loot table
## and everything it can drop do not have to load each other (rule 32).

## What drops.
@export var item_id: StringName = &""

@export_range(1, 9999) var minimum: int = 1

@export_range(1, 9999) var maximum: int = 1

## Relative likelihood among the weighted picks. Twice the weight is twice as
## likely; zero excludes it from the picks entirely.
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight: float = 1.0

## Drops every time rather than competing for a pick. The quest item, the
## bandit's dagger.
@export var guaranteed: bool = false

## Chance a guaranteed entry actually drops, in 0..1. One always drops; below
## one is "usually, but not always", which is what most named drops want.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0


## How many of this entry drop, using [param rng] so a roll is reproducible.
func roll_quantity(rng: RandomNumberGenerator) -> int:
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	if low == high or rng == null:
		return low
	return rng.randi_range(low, high)


## Whether a guaranteed entry passes its chance this time.
func passes_chance(rng: RandomNumberGenerator) -> bool:
	if chance >= 1.0:
		return true
	if chance <= 0.0 or rng == null:
		return false
	return rng.randf() < chance


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"loot_entry.no_item",
			"A loot entry with no item id drops nothing.",
			resource_path,
			"item_id"
		)
	if minimum > maximum:
		result.add_warning(
			&"loot_entry.inverted_range",
			(
				"'%s' has a minimum above its maximum; the two are swapped at "
				+ "roll time, but the content reads wrong."
			) % item_id,
			resource_path,
			"maximum"
		)
	if not guaranteed and weight <= 0.0:
		result.add_warning(
			&"loot_entry.unreachable",
			"'%s' has no weight and is not guaranteed, so it can never drop." % item_id,
			resource_path,
			"weight"
		)
	if guaranteed and chance <= 0.0:
		result.add_warning(
			&"loot_entry.never_drops",
			"'%s' is guaranteed with a zero chance, so it never drops." % item_id,
			resource_path,
			"chance"
		)
	return result
