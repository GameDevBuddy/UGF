class_name ItemPickup
extends FrameworkComponent
## An item lying in the world, waiting to be picked up.
##
## The world end of the round trip: a pickup holds an [ItemInstance], hands it
## to an inventory on request, and removes itself once empty. Dropping is the
## same thing backwards — [method spawn] builds one from an instance an
## inventory just gave up.
##
## [b]It takes what fits and leaves the rest.[/b] A pickup that refuses
## entirely because the bag is nearly full is worse than one that gives what it
## can: the player picks up nine of ten arrows and the tenth stays visible on
## the ground, which is legible. This is the one place the framework prefers a
## partial operation to an atomic one, and it is deliberate — nothing is
## destroyed either way, so rule 17's reason for existing does not apply.

## Emitted when some or all of the stack is taken.
signal collected(instance: ItemInstance, quantity: int)
## Emitted when the pickup empties and is about to remove itself.
signal exhausted

## What is lying here. Authored pickups set the definition and quantity below;
## dropped ones are handed a whole instance by [method spawn].
@export var item: ItemDefinition

@export_range(1, 9999) var quantity: int = 1

## Remove the entity once the stack is empty. Off for a respawning node that
## something else refills.
@export var free_when_empty: bool = true

var _instance: ItemInstance = null


func initialize(context: EntityContext) -> void:
	super(context)
	if _instance == null:
		var definition := item if item != null else get_definition() as ItemDefinition
		if definition != null:
			_instance = ItemInstance.create(definition, quantity)


## The stack lying here, or null for a pickup with nothing in it.
func get_instance() -> ItemInstance:
	return _instance


## Puts a specific instance in this pickup. How a dropped item keeps its
## durability, its enchantments and its stack size on the way to the ground.
func set_instance(instance: ItemInstance) -> void:
	_instance = instance
	if instance != null:
		item = instance.definition
		quantity = instance.quantity


func is_empty() -> bool:
	return _instance == null or _instance.quantity <= 0


## Moves as much as fits into [param inventory].
##
## Returns the number of units taken. Zero means the bag had no room or refused
## the kind, and the pickup is left exactly as it was.
func take_by(inventory: InventoryComponent) -> FrameworkResult:
	if inventory == null:
		return FrameworkResult.fail(
			&"pickup.no_inventory", "There is no inventory to pick up into."
		)
	if is_empty():
		return FrameworkResult.fail(&"pickup.empty", "There is nothing here to take.")

	var offered := _instance.quantity
	var taken := inventory.add_up_to(_instance)
	if taken <= 0:
		return FrameworkResult.fail(
			&"pickup.no_room",
			"No room for %s." % _instance.get_display_name()
		)

	var moved := _instance
	if taken >= offered:
		# The container took the whole stack -- and when the stack fits one
		# slot, it took this very object rather than a copy of it. Its quantity
		# is the container's business from here, so ownership is released
		# outright instead of being inferred from a number this pickup no
		# longer owns. Reading it back would leave the pickup convinced the
		# item was still lying there.
		_instance = null
		quantity = 0
	else:
		quantity = _instance.quantity

	collected.emit(moved, taken)
	if is_empty():
		exhausted.emit()
		if free_when_empty:
			var entity := get_entity()
			if entity != null:
				entity.queue_free()
	return FrameworkResult.ok(taken)


## Builds a pickup entity for [param instance] from its definition's scene.
##
## The reverse of [method take_by], and the second half of drop: an inventory
## hands over an instance, this puts it in the world. Returns null when the
## definition has no scene, which is a legitimate configuration for an item
## that is not meant to exist outside a container — a quest token, a currency.
static func spawn(instance: ItemInstance) -> Node:
	if instance == null or instance.definition == null:
		return null
	var scene := instance.definition.scene
	if scene == null:
		return null
	var entity := scene.instantiate()
	if entity == null:
		# An unloadable or empty scene is content that is wrong, not a reason to
		# crash the drop and lose the item the caller is holding.
		return null
	var pickup := _find_pickup(entity)
	if pickup != null:
		pickup.set_instance(instance)
	return entity


static func _find_pickup(node: Node) -> ItemPickup:
	for child in node.get_children():
		if child is ItemPickup:
			return child as ItemPickup
	return null


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	if _instance == null:
		return {}
	return {"item": _instance.capture_state()}


func restore_state(data: Dictionary) -> void:
	var saved: Dictionary = data.get("item", {})
	if saved.is_empty():
		return
	var context := get_context()
	var core := context.core if context != null else null
	var restored := ItemInstance.restore_state(saved, core)
	if restored != null:
		set_instance(restored)
