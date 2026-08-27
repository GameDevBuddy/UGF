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
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var dropped: Array[Dictionary] = []
	for entry in get_guaranteed():
		if entry.passes_chance(rng):
			_add(dropped, entry, rng)

	var pool := get_weighted()
	for pick in rolls:
		if pool.is_empty():
			break
		var entry := _pick(pool, rng)
		if entry == null:
			continue
		_add(dropped, entry, rng)
		if not allows_duplicates:
			pool.erase(entry)
	return dropped


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
	dropped.append({"item_id": entry.item_id, "quantity": quantity})


func _pick(pool: Array, rng: RandomNumberGenerator) -> LootEntry:
	var total := 0.0
	for entry in pool:
		total += (entry as LootEntry).weight
	if total <= 0.0:
		return null
	var target := (rng.randf() if rng != null else 0.0) * total
	var running := 0.0
	for entry in pool:
		running += (entry as LootEntry).weight
		if target < running:
			return entry as LootEntry
	return pool.back() as LootEntry
