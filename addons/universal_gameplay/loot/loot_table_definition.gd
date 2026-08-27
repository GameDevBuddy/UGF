class_name LootTableDefinition
extends FrameworkDefinition
## What a corpse, a chest or a destroyed crate leaves behind.
##
## [b]Randomness arrives as an argument.[/b] [method roll] takes a
## [RandomNumberGenerator], so a test gets the same drop twice and a networked
## game can hand every client the same stream. The same decision
## [CombatSolver] made about spread, and for the same reasons.

## Everything that might drop.
@export var entries: Array[LootEntry] = []

## How many weighted picks to make. Guaranteed entries drop on top of these.
@export_range(0, 32) var rolls: int = 1

## Whether one entry can be picked more than once across the rolls. Off makes
## three rolls on a three-entry table drop each one exactly once.
@export var allows_duplicates: bool = true

## Other tables rolled as well, by id. What makes "a bandit drops bandit loot
## plus common loot" one line rather than a copied entry list (rule 32).
@export var sub_tables: Array[StringName] = []


func get_guaranteed() -> Array[LootEntry]:
	return entries.filter(
		func(entry: LootEntry) -> bool: return entry != null and entry.guaranteed
	)


func get_weighted() -> Array[LootEntry]:
	return entries.filter(
		func(entry: LootEntry) -> bool:
			return entry != null and not entry.guaranteed and entry.weight > 0.0
	)


func get_total_weight() -> float:
	var total := 0.0
	for entry in get_weighted():
		total += entry.weight
	return total


## Rolls the table. Returns pairs of item id and quantity, not instances,
## because building an [ItemInstance] needs a definition registry and a table
## should be rollable without one (rule 33).
func roll(
	rng: RandomNumberGenerator,
	narrative: Object = null,
	rarity_of: Callable = Callable()
) -> Array[Dictionary]:
	var dropped: Array[Dictionary] = []
	for entry in get_guaranteed():
		if entry.is_eligible(narrative) and entry.passes_chance(rng):
			_add(dropped, entry, rng)

	# Ineligible entries are removed from the pool rather than skipped when
	# picked. Skipping would make an excluded entry still consume a roll, so a
	# table would drop less the more conditions it carried -- which reads as
	# "the loot got worse" and is very hard to trace back to a flag.
	var pool: Array[LootEntry] = []
	for entry in get_weighted():
		if entry.is_eligible(narrative):
			pool.append(entry)

	for pick in rolls:
		if pool.is_empty():
			break
		var entry := _pick_weighted(pool, rng, rarity_of)
		if entry == null:
			continue
		_add(dropped, entry, rng)
		if not allows_duplicates:
			pool.erase(entry)
	return dropped


## Picks one entry, scaling each weight by its item's rarity.
##
## [param rarity_of] answers "how scarce is this item id?" and returns a
## multiplier. It is a [Callable] rather than a registry reference because a
## table must stay rollable with no registry at all (rule 33) -- pass nothing
## and rarity simply does not apply.
func _pick_weighted(
	pool: Array[LootEntry], rng: RandomNumberGenerator, rarity_of: Callable
) -> LootEntry:
	var weights: Array[float] = []
	var total := 0.0
	for entry in pool:
		var weight := entry.weight
		if rarity_of.is_valid():
			weight *= maxf(0.0, float(rarity_of.call(entry.get_drop_id())))
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return null
	var target := rng.randf() * total if rng != null else 0.0
	var running := 0.0
	for index in pool.size():
		running += weights[index]
		if target < running:
			return pool[index]
	return pool[pool.size() - 1]


func validate() -> ValidationResult:
	var result := super()
	if entries.is_empty():
		result.add_warning(
			&"loot.empty_table",
			"%s drops nothing." % get_debug_name(),
			resource_path,
			"entries"
		)
	if rolls > 0 and get_weighted().is_empty() and not entries.is_empty():
		result.add_warning(
			&"loot.no_weighted_entries",
			(
				"%s rolls %d times but every entry is guaranteed, so the rolls "
				+ "do nothing."
			) % [get_debug_name(), rolls],
			resource_path,
			"rolls"
		)
	if not allows_duplicates and rolls > get_weighted().size():
		result.add_warning(
			&"loot.more_rolls_than_entries",
			(
				"%s rolls %d times without duplicates but has only %d weighted "
				+ "entries, so the extra rolls drop nothing."
			) % [get_debug_name(), rolls, get_weighted().size()],
			resource_path,
			"rolls"
		)
	if sub_tables.has(id):
		result.add_error(
			&"loot.self_reference",
			"%s rolls itself, which would never terminate." % get_debug_name(),
			resource_path,
			"sub_tables"
		)
	for entry in entries:
		if entry == null:
			result.add_warning(
				&"loot.empty_slot",
				"%s has an empty entry slot." % get_debug_name(),
				resource_path,
				"entries"
			)
			continue
		result.merge(entry.validate())
	return result


# --- Internals ------------------------------------------------------------

func _add(
	dropped: Array[Dictionary], entry: LootEntry, rng: RandomNumberGenerator
) -> void:
	var quantity := entry.roll_quantity(rng)
	if quantity <= 0:
		return
	# Merged rather than appended, so a table that picks the same entry twice
	# yields one stack of six rather than two of three -- which is what an
	# inventory would end up with anyway.
	for existing in dropped:
		if existing["item_id"] == entry.item_id:
			existing["quantity"] += quantity
			return
	dropped.append({
		"item_id": entry.item_id,
		"currency_id": entry.currency_id,
		"quantity": quantity,
	})


## Every item and sub-table this pool can produce.
##
## The check that catches a corpse dropping nothing because the item it names
## was renamed three commits ago.
func get_referenced_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in entries:
		if entry == null:
			continue
		if entry.item_id != &"":
			ids.append(entry.item_id)
		if entry.currency_id != &"":
			ids.append(entry.currency_id)
	for table_id in sub_tables:
		if table_id != &"":
			ids.append(table_id)
	return ids


## Sub-tables are edges: a table rolling itself, directly or through another,
## recurses until the stack gives out.
func get_dependency_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for table_id in sub_tables:
		if table_id != &"":
			ids.append(table_id)
	return ids
