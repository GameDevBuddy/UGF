class_name InventoryAuthorityAdapter
extends Node
## Puts the server in front of the bag.
##
## [b]Inventory did not change for this.[/b] It already had a mutation API —
## [method InventoryComponent.add], [method InventoryComponent.remove],
## [method InventoryComponent.transfer_to] — and this registers handlers that
## call exactly those. That is what Implementation Plan 27 means by "define
## mutation APIs so an authority adapter can sit in front of them", and it is
## why [code]inventory/[/code] contains no mention of a peer.
##
## Deletable. Without it, inventory verbs have no handler and a project calls
## the component directly, exactly as every milestone before M18 did (rule 10).

signal transfer_validated(intent: NetworkIntent)

## Where handlers are registered. Resolved from the core when not wired.
@export var authority: NetworkAuthority

## Where item definitions are resolved from. Any object with
## [code]get_definition(id)[/code]; in practice the core.
##
## Not exported: [Object] is not an exportable type in Godot, and narrowing it
## to [Node] would rule out a plain [RefCounted] registry for no gain. Wired in
## code, like [NetworkAuthority]'s own.
var registry: Object = null

## Most of one item a single request may move. The cheapest anti-cheat there
## is: a client asking to transfer two billion planks is refused by a number
## rather than by an integer overflow.
@export_range(1, 100000) var maximum_quantity: int = 1000

var _registered: Array[StringName] = []


func _ready() -> void:
	install()


func _exit_tree() -> void:
	uninstall()


## Registers the inventory verbs. Public so a project swapping services at
## runtime can re-apply them.
func install() -> void:
	if authority == null:
		return
	_register(&"inventory.add", _add)
	_register(&"inventory.remove", _remove)
	_register(&"inventory.transfer", _transfer)
	authority.register_validator(&"inventory.transfer", _validate_transfer)
	authority.register_validator(&"inventory.add", _validate_quantity)
	authority.register_validator(&"inventory.remove", _validate_quantity)


func uninstall() -> void:
	if authority == null:
		return
	for verb in _registered:
		authority.unregister_handler(verb)
	_registered.clear()


func get_registered_verbs() -> Array[StringName]:
	return _registered.duplicate()


# --- Handlers -------------------------------------------------------------
#
# Each of these does exactly what the component's own method does, and nothing
# else. An adapter that added rules would be a second place inventory
# behaviour lives, and the two would drift.

func _add(intent: NetworkIntent) -> FrameworkResult:
	var bag := _inventory_of(authority.find_entity(intent.actor_id))
	if bag == null:
		return FrameworkResult.fail(&"inventory.no_bag", "There is no bag.")
	var definition := _item(intent.get_string(&"item_id"))
	if definition == null:
		return FrameworkResult.fail(
			&"inventory.unknown_item", "No item is registered as '%s'." % intent.get_string(&"item_id")
		)
	return bag.add(ItemInstance.create(definition, intent.get_int(&"quantity", 1)))


func _remove(intent: NetworkIntent) -> FrameworkResult:
	var bag := _inventory_of(authority.find_entity(intent.actor_id))
	if bag == null:
		return FrameworkResult.fail(&"inventory.no_bag", "There is no bag.")
	return bag.remove(intent.get_string(&"item_id"), intent.get_int(&"quantity", 1))


func _transfer(intent: NetworkIntent) -> FrameworkResult:
	var from := _inventory_of(authority.find_entity(intent.actor_id))
	var to := _inventory_of(authority.find_entity(intent.target_id))
	if from == null or to == null:
		return FrameworkResult.fail(
			&"inventory.no_bag", "Both ends of a transfer need a container."
		)
	return from.transfer_to(to, intent.get_string(&"item_id"), intent.get_int(&"quantity", 1))


# --- Validation -----------------------------------------------------------
#
# Server-side, because a client can be modified and a check that ran there is
# a suggestion.

func _validate_quantity(intent: NetworkIntent) -> FrameworkResult:
	var quantity := intent.get_int(&"quantity", 1)
	if quantity < 1:
		return FrameworkResult.fail(
			&"inventory.bad_quantity", "A quantity of %d is not a quantity." % quantity
		)
	if quantity > maximum_quantity:
		return FrameworkResult.fail(
			&"inventory.too_many",
			"%d is more than one request may move." % quantity
		)
	return FrameworkResult.ok(intent)


func _validate_transfer(intent: NetworkIntent) -> FrameworkResult:
	var checked := _validate_quantity(intent)
	if checked.is_err():
		return checked
	if intent.target_id == &"":
		return FrameworkResult.fail(
			&"inventory.no_target", "A transfer needs somewhere to go."
		)
	if intent.target_id == intent.actor_id:
		return FrameworkResult.fail(
			&"inventory.self_transfer", "Moving something to itself is not a transfer."
		)
	transfer_validated.emit(intent)
	return FrameworkResult.ok(intent)


# --- Internals ------------------------------------------------------------

func _register(verb: StringName, handler: Callable) -> void:
	if authority.register_handler(verb, handler).is_ok():
		_registered.append(verb)


func _inventory_of(entity: Node) -> InventoryComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _item(item_id: StringName) -> ItemDefinition:
	if registry == null or not registry.has_method("get_definition"):
		return null
	return registry.call("get_definition", item_id) as ItemDefinition
