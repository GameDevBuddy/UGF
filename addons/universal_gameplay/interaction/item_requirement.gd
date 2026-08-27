class_name ItemRequirement
extends InteractionRequirement
## Requires the interactor to be carrying something. The keycard, the crowbar,
## the coin in the slot.
##
## [member consume] is the difference between a key and a fee. A key is checked
## and kept; a fee is checked and taken. Both are this resource, which is the
## reuse rule 23 asks for before an abstraction earns its place.
##
## Named by [member item_id] rather than by a [ItemDefinition] reference, so a
## door in one scene and the key in another do not have to load each other
## (rule 32 -- semantic ids, not paths).

## Item the interactor must be carrying.
@export var item_id: StringName = &""

@export_range(1, 9999) var quantity: int = 1

## Take the items when the interaction succeeds.
@export var consume: bool = false

## Shown when the requirement is not met. Blank falls back to a generic line.
@export var unmet_text: String = ""


func check(context: InteractionContext) -> FrameworkResult:
	if item_id == &"":
		return FrameworkResult.fail(
			&"requirement.no_item_id", "This item requirement names no item."
		)
	var inventory := _get_inventory(context)
	if inventory == null:
		# No bag at all is a legitimate state, not a broken one: the
		# requirement is simply unmet (rule 31).
		# A distinct code, because "no bag at all" is worth telling apart when
		# debugging -- but the same message, because to a player not having a
		# bag and not having the key are the same sentence.
		return FrameworkResult.fail(&"requirement.no_inventory", describe())
	if not inventory.has(item_id, quantity):
		return FrameworkResult.fail(&"requirement.missing_item", describe())
	return FrameworkResult.ok(null)


func commit(context: InteractionContext) -> FrameworkResult:
	if not consume:
		return FrameworkResult.ok(null)
	var inventory := _get_inventory(context)
	if inventory == null:
		return FrameworkResult.fail(
			&"requirement.no_inventory",
			"The interactor has no inventory to take from."
		)
	return inventory.remove(item_id, quantity)


func describe() -> String:
	if not unmet_text.is_empty():
		return unmet_text
	if quantity > 1:
		return "Requires %d x %s" % [quantity, item_id]
	return "Requires %s" % item_id


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"item_requirement.no_item_id",
			"An item requirement with no item id can never be met.",
			resource_path,
			"item_id"
		)
	if quantity < 1:
		result.add_error(
			&"item_requirement.bad_quantity",
			"An item requirement for fewer than one item is meaningless.",
			resource_path,
			"quantity"
		)
	return result


func _get_inventory(context: InteractionContext) -> InventoryComponent:
	return context.get_interactor_inventory() if context != null else null
