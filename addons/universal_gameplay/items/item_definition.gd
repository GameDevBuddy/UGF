class_name ItemDefinition
extends EntityDefinition
## What an item is. Shared, immutable, and pointed at by every instance of it.
##
## An [EntityDefinition] because an item can exist in the world as a pickup, so
## it needs a scene. Its [member EntityDefinition.scene] is that world form.
##
## [b]This is half of the split rule 16 insists on.[/b] A thousand arrows in a
## thousand quivers point at one [code]item_arrow.tres[/code]; the count, the
## durability and the modifiers on any particular stack live in
## [ItemInstance]. Putting quantity here instead is the bug that makes every
## arrow in the game share one count.
##
## [b]It is deliberately incomplete.[/b] Ontology Rulebook 9 also lists weapon,
## consumable and crafting profiles. Those belong to M6, M12 and M12; declaring
## them now would put a WeaponProfile type inside a definition every project
## must load and break Items in a build without Combat (rules 1 and 10). Each
## milestone adds its own field.

## Broad classification: [code]item.weapon[/code], [code]item.consumable[/code].
## Containers filter on this; it is coarser than [member tags] on purpose.
@export var category: StringName = &""

@export_group("Stacking")
## How many fit in one stack. One means it never stacks.
@export_range(1, 9999) var max_stack: int = 1

@export_group("Inventory")
## Weight of a single unit. Containers with a weight limit sum this.
@export var weight: float = 0.0

## Base worth before any pricing policy. A plain number rather than a currency
## type, so Items does not depend on Commerce (M11) to say what a sword is
## roughly worth.
@export var base_value: float = 0.0

@export_group("Durability")
## Condition a fresh instance starts at. Zero means this item has no durability
## and never degrades.
@export var max_durability: float = 0.0

## Whether the item is destroyed when durability reaches zero, rather than
## merely becoming unusable.
@export var breaks_when_worn_out: bool = false

@export_group("Interaction")
## What can be done to this item while it is lying in the world: take it,
## examine it, hotwire it. Empty is the usual case -- a pickup is normally
## collected by touch or by a project's own take interaction rather than by an
## authored list.
@export var interactions: Array[InteractionDefinition] = []

@export_group("Equipment")
## Where this can be equipped and what it grants. Null means it is not
## equippable, which is the normal case for most items.
@export var equipment: EquipmentProfile


func is_stackable() -> bool:
	return max_stack > 1


func has_durability() -> bool:
	return max_durability > 0.0


func is_equippable() -> bool:
	return equipment != null


func validate() -> ValidationResult:
	# EntityDefinition requires a scene so the item can exist as a pickup. That
	# is the right default: an item that can never be dropped is unusual.
	var result := super()
	if category == &"":
		result.add_warning(
			&"item.missing_category",
			(
				"%s has no category, so containers that filter by category will "
				+ "never accept it."
			) % get_debug_name(),
			resource_path,
			"category"
		)
	if weight < 0.0:
		result.add_error(
			&"item.negative_weight",
			"%s has a negative weight, which would make a container lighter." % get_debug_name(),
			resource_path,
			"weight"
		)
	if is_stackable() and has_durability():
		result.add_error(
			&"item.stackable_with_durability",
			(
				"%s stacks and has durability. Two units at different conditions "
				+ "cannot share one number, so one of the two would be silently lost."
			) % get_debug_name(),
			resource_path,
			"max_stack"
		)
	if is_stackable() and is_equippable():
		result.add_warning(
			&"item.stackable_equipment",
			(
				"%s stacks and is equippable; equipping one unit of a stack is "
				+ "ambiguous."
			) % get_debug_name(),
			resource_path,
			"max_stack"
		)
	if breaks_when_worn_out and not has_durability():
		result.add_warning(
			&"item.breaks_without_durability",
			"%s breaks when worn out but has no durability to wear." % get_debug_name(),
			resource_path,
			"breaks_when_worn_out"
		)
	if equipment != null:
		result.merge(equipment.validate())
	for offered in interactions:
		if offered != null:
			result.merge(offered.validate())
	return result
