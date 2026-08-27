class_name EquipmentProfile
extends Resource
## What an item does once it is worn: where it goes, what it grants, who can
## use it.
##
## Lives on [ItemDefinition] rather than being a separate definition type,
## because "equippable" is a property some items have rather than a kind of
## thing (rule 11). A sword and a potion are both items; one has this and one
## does not.

## Slot ids this fits, e.g. [code]slot.main_hand[/code]. More than one means
## the item can go in either — a dagger in main or off hand.
@export var slots: Array[StringName] = []

## Extra slots this occupies while equipped, beyond the one it went into. A
## two-handed weapon blocks the off hand; a full helm blocks the face slot.
@export var blocks_slots: Array[StringName] = []

@export_group("Effect")
## Modifiers granted while equipped. Their source is overwritten with the
## wearing instance's id, so two identical rings unequip independently.
@export var modifiers: Array[StatModifier] = []

## Semantic state tags applied to the wearer while equipped.
@export var applied_states: Array[StringName] = []

@export_group("Requirements")
## Minimum stat values needed to equip, keyed by stat id. An entity that does
## not have the stat at all fails the requirement rather than skipping it — a
## crate cannot wear plate armour by virtue of having no strength.
@export var stat_requirements: Dictionary[StringName, float] = {}

## Tags the wearer must have. Class restrictions, faction gear, size.
@export var required_tags: Array[StringName] = []


func fits_slot(slot: StringName) -> bool:
	return slots.has(slot)


func get_primary_slot() -> StringName:
	return slots[0] if not slots.is_empty() else &""


## Modifiers with their source rewritten to [param source].
##
## Stamped rather than authored, for the same reason status effects stamp
## theirs: removal is by source, and two copies of the same item sharing one
## source would mean taking off the first removes the second's bonus too.
func build_modifiers(source: StringName) -> Array[StatModifier]:
	var built: Array[StatModifier] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		var copy := modifier.duplicate() as StatModifier
		copy.source = source
		built.append(copy)
	return built


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if slots.is_empty():
		result.add_error(
			&"equipment_profile.no_slots",
			"An equipment profile with no slots can never be equipped.",
			resource_path,
			"slots"
		)
	for slot in blocks_slots:
		if slots.has(slot):
			result.add_warning(
				&"equipment_profile.blocks_own_slot",
				(
					"'%s' is both a slot this fits and one it blocks, which would "
					+ "block the slot it is in."
				) % slot,
				resource_path,
				"blocks_slots"
			)
	for modifier in modifiers:
		if modifier == null:
			result.add_warning(
				&"equipment_profile.null_modifier",
				"The modifiers array has an empty slot.",
				resource_path,
				"modifiers"
			)
		elif modifier.stat == &"":
			result.add_error(
				&"equipment_profile.modifier_without_stat",
				"A granted modifier names no stat.",
				resource_path,
				"modifiers"
			)
	return result
