class_name LootEntry
extends Resource
## One thing that might drop.
##
## Named by item id rather than holding an [ItemDefinition], so a loot table
## and everything it can drop do not have to load each other (rule 32).

## What drops. Leave empty and set [member currency_id] for a money drop.
@export var item_id: StringName = &""

## Currency that drops instead of an item.
##
## [b]One entry type, not two.[/b] A coin drop wants everything an item drop
## wants -- a quantity range, a weight, a guarantee, a chance, conditions --
## and a separate CurrencyLootEntry class would inherit all of it to add one
## field (rule 23). An entry names an item or a currency; naming both is a
## content error and validation says so.
@export var currency_id: StringName = &""

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

@export_group("Conditions")
## Narrative flags that must all be set for this entry to be eligible.
##
## [b]Flags rather than a condition class hierarchy.[/b] [RecipeDefinition] and
## [MissionDefinition] already gate on exactly these two arrays against exactly
## this store, and a third mechanism asking the same question a third way is
## the duplication rule 23 forbids. An entry gated on something narrative state
## cannot express belongs in a sub-table the caller chooses instead.
@export var required_flags: Array[StringName] = []

## Flags that must all be unset. The drop that stops appearing once the player
## has already found one.
@export var forbidden_flags: Array[StringName] = []


## Whether this entry is eligible at all, before any dice are rolled.
##
## [param narrative] null means no flag store, and an entry with flag
## requirements is then ineligible rather than free: a condition that cannot be
## evaluated has not been met.
func is_eligible(narrative: Object) -> bool:
	if required_flags.is_empty() and forbidden_flags.is_empty():
		return true
	if narrative == null or not narrative.has_method("get_flag"):
		return false
	for flag in required_flags:
		if not narrative.call("get_flag", flag):
			return false
	for flag in forbidden_flags:
		if narrative.call("get_flag", flag):
			return false
	return true


## True when this entry drops money rather than an object.
func is_currency() -> bool:
	return currency_id != &"" and item_id == &""


func get_drop_id() -> StringName:
	return currency_id if is_currency() else item_id


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
	if item_id == &"" and currency_id == &"":
		result.add_error(
			&"loot_entry.no_item",
			"A loot entry naming neither an item nor a currency drops nothing.",
			resource_path,
			"item_id"
		)
	elif item_id != &"" and currency_id != &"":
		result.add_error(
			&"loot_entry.drops_both",
			(
				"Entry '%s' names both an item and the currency '%s'. Which one "
				+ "drops would be arbitrary."
			) % [item_id, currency_id],
			resource_path,
			"currency_id"
		)
	for flag in required_flags:
		if forbidden_flags.has(flag):
			result.add_error(
				&"loot_entry.contradictory_flags",
				(
					"Entry '%s' requires and forbids the flag '%s', so it can "
					+ "never drop."
				) % [get_drop_id(), flag],
				resource_path,
				"forbidden_flags"
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
