class_name ItemReward
extends MissionReward
## Pays in items: the sword, the purse, the twelve arrows.
##
## Named by item id and resolved through the definition registry rather than
## holding an [ItemDefinition] reference, so a mission and the loot it pays do
## not have to load each other and a mission's save record stays a list of ids
## (rule 32).

@export var item_id: StringName = &""

@export_range(1, 9999) var quantity: int = 1


func grant(runtime: MissionRuntime) -> FrameworkResult:
	if item_id == &"":
		return FrameworkResult.fail(
			&"item_reward.no_item", "This reward names no item."
		)
	var inventory := runtime.get_subject_inventory() if runtime != null else null
	if inventory == null:
		return FrameworkResult.fail(
			&"item_reward.no_inventory", "There is nowhere to put it."
		)
	var definition := _resolve(runtime)
	if definition == null:
		return FrameworkResult.fail(
			&"item_reward.unknown_item",
			"No item definition is registered as '%s'." % item_id
		)
	return inventory.add(ItemInstance.create(definition, quantity))


func describe() -> String:
	if quantity > 1:
		return "%d x %s" % [quantity, item_id]
	return str(item_id)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"item_reward.no_item",
			"An item reward with no item id gives nothing.",
			resource_path,
			"item_id"
		)
	if quantity < 1:
		result.add_error(
			&"item_reward.bad_quantity",
			"An item reward of fewer than one item is meaningless.",
			resource_path,
			"quantity"
		)
	return result


func _resolve(runtime: MissionRuntime) -> ItemDefinition:
	var core := runtime.core
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", item_id) as ItemDefinition
