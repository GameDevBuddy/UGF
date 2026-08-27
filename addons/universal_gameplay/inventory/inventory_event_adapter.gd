class_name InventoryEventAdapter
extends FrameworkComponent
## Promotes "something went in the bag" to a cross-feature fact.
##
## The same seam [HealthEventAdapter] is. Inventory shipped in M4 without one
## because nothing was listening yet; M9's objectives are the first thing that
## needs to hear about acquisition, and the answer is an adapter rather than
## Inventory learning what a mission is (rule 10).
##
## [b]Only the player's bag usually needs one.[/b] Every crate, corpse and
## vendor stall in the world has an inventory, and publishing every restock to
## the whole game would be noise. That the promotion is a component is what
## makes "which containers are worth announcing" per-entity data.

## Emitted after publication, for debug tooling watching the promotion.
signal acquisition_published(event: FrameworkEvent)

## The container to observe, wired at composition time (rule 20).
@export var inventory: InventoryComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

@export var publish_acquisitions: bool = true

const AcquiredEvent := preload(
	"res://addons/universal_gameplay/inventory/item_acquired_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if inventory == null:
		inventory = _find_inventory()
	_bus = event_bus if event_bus != null else _find_bus()
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_ITEM_ACQUIRED)
	if inventory != null and not inventory.item_added.is_connected(_on_added):
		inventory.item_added.connect(_on_added)


func _exit_tree() -> void:
	if inventory != null and inventory.item_added.is_connected(_on_added):
		inventory.item_added.disconnect(_on_added)


func get_bus() -> Node:
	return _bus


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_ITEM_ACQUIRED)


func _on_added(instance: ItemInstance, quantity: int) -> void:
	if not publish_acquisitions or _bus == null or not _bus.has_method("publish"):
		return
	var event := AcquiredEvent.create(inventory, instance, quantity)
	_bus.call("publish", event)
	acquisition_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")


func _find_inventory() -> InventoryComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null
