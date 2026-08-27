class_name InventoryDebugCommands
extends DebugCommandPack
## The plan's "spawn item" cheat, living in the module it cheats at.
##
## Resolves the item through the definition registry rather than constructing
## one, so a typo in a console argument reports "no such item" instead of
## quietly creating an item that exists nowhere else in the game.

var _inventory: InventoryComponent = null
var _core: Node = null


func _init(inventory: InventoryComponent = null, core: Node = null) -> void:
	_inventory = inventory
	_core = core


func set_target(inventory: InventoryComponent) -> void:
	_inventory = inventory


func build_commands() -> Array[DebugCommand]:
	return [
		DebugCommand.create(
			&"give",
			_give,
			"Put an item in the target's inventory.",
			"<item_id> [count]",
			true
		),
		DebugCommand.create(
			&"take", _take, "Remove an item from the target's inventory.", "<item_id> [count]", true
		),
	] as Array[DebugCommand]


func _give(arguments: PackedStringArray) -> FrameworkResult:
	if _inventory == null:
		return refuse("No inventory target set.")
	if arguments.is_empty():
		return refuse("Usage: give <item_id> [count]")

	var item_id := StringName(arguments[0])
	var definition := _resolve(item_id)
	if definition == null:
		return refuse("No item definition '%s' is registered." % item_id)

	var count := 1
	if arguments.size() > 1:
		count = maxi(1, arguments[1].to_int())

	var result := _inventory.add(ItemInstance.create(definition, count))
	if result.is_err():
		return result
	return FrameworkResult.ok("Gave %d x %s." % [count, item_id])


func _take(arguments: PackedStringArray) -> FrameworkResult:
	if _inventory == null:
		return refuse("No inventory target set.")
	if arguments.is_empty():
		return refuse("Usage: take <item_id> [count]")

	var item_id := StringName(arguments[0])
	var count := 1
	if arguments.size() > 1:
		count = maxi(1, arguments[1].to_int())

	var result := _inventory.remove(item_id, count)
	if result.is_err():
		return result
	return FrameworkResult.ok("Took %d x %s." % [count, item_id])


func _resolve(item_id: StringName) -> ItemDefinition:
	if _core == null or not _core.has_method("get_definition"):
		return null
	return _core.call("get_definition", item_id) as ItemDefinition
