class_name LoadoutProfile
extends Resource
## Which slots an entity has, and what it starts wearing.
##
## A guard's rifle loadout and a civilian's empty one are two resources, not
## two classes (rule 11, rule 15). Implementation Plan 37 authors exactly this:
## [code]loadout_guard_rifle.tres[/code] hanging off a character definition.

## Slots this entity has. An entity with no entry for a slot does not have that
## slot, and equipping to it fails rather than inventing one.
@export var slots: Array[EquipmentSlotDefinition] = []

## Items worn from the start, keyed by slot id. Resolved and equipped on
## initialisation, skipping anything that does not fit or is not allowed.
@export var starting_items: Dictionary[StringName, ItemDefinition] = {}


func has_slot(id: StringName) -> bool:
	return get_slot(id) != null


func get_slot(id: StringName) -> EquipmentSlotDefinition:
	for slot in slots:
		if slot != null and slot.id == id:
			return slot
	return null


func get_slot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for slot in slots:
		if slot != null and slot.id != &"":
			ids.append(slot.id)
	return ids


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	var seen: Dictionary[StringName, bool] = {}
	for slot in slots:
		if slot == null:
			result.add_warning(
				&"loadout.null_slot",
				"The slots array has an empty entry.",
				resource_path,
				"slots"
			)
			continue
		if seen.has(slot.id):
			result.add_error(
				&"loadout.duplicate_slot",
				"Slot '%s' appears twice." % slot.id,
				resource_path,
				"slots"
			)
		seen[slot.id] = true
		result.merge(slot.validate())

	for slot_id in starting_items:
		var item: ItemDefinition = starting_items[slot_id]
		if not seen.has(slot_id):
			result.add_warning(
				&"loadout.starting_item_without_slot",
				(
					"A starting item is assigned to '%s', but this loadout has no "
					+ "such slot, so it will never be equipped."
				) % slot_id,
				resource_path,
				"starting_items"
			)
		elif item == null:
			result.add_warning(
				&"loadout.null_starting_item",
				"Slot '%s' has an empty starting item." % slot_id,
				resource_path,
				"starting_items"
			)
		elif not item.is_equippable():
			result.add_error(
				&"loadout.unequippable_starting_item",
				(
					"'%s' is assigned to slot '%s' but has no equipment profile."
					% [item.get_debug_name(), slot_id]
				),
				resource_path,
				"starting_items"
			)
		elif not item.equipment.fits_slot(slot_id):
			result.add_error(
				&"loadout.starting_item_wrong_slot",
				(
					"'%s' is assigned to slot '%s' but does not fit there."
					% [item.get_debug_name(), slot_id]
				),
				resource_path,
				"starting_items"
			)
	return result
