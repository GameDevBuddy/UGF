extends FrameworkEvent
## Something was put in a container.
##
## Published so Missions, Crafting and Commerce can react to acquisition
## without any of them holding an [InventoryComponent] (rule 9). Carries the
## item's id rather than its definition, so a save record and an objective
## matcher are both plain strings (rule 32).
##
## No class_name: events are constructed by the adapter that publishes them
## and matched by name on the bus.

## The container it went into.
var inventory: Node = null

## Definition id of what was acquired.
var item_id: StringName = &""

## Broad classification, so an objective can ask for "any weapon".
var category: StringName = &""

## How many arrived in this one acquisition.
var quantity: int = 0

## Tags from the item's definition, for an objective matching on
## [code]item.quest[/code] rather than on one specific id.
var tags: Array[StringName] = []


static func create(
	p_inventory: Node, p_instance: ItemInstance, p_quantity: int
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/inventory/item_acquired_event.gd"
	) as GDScript).new()
	event.inventory = p_inventory
	event.source = p_inventory
	event.quantity = p_quantity
	if p_instance != null and p_instance.definition != null:
		event.item_id = p_instance.definition.id
		event.category = p_instance.definition.category
		event.tags = p_instance.definition.tags.duplicate()
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_ITEM_ACQUIRED


## The entity holding the container, for an objective asking whether it was
## the player who picked it up.
func get_owner_entity() -> Node:
	if inventory == null:
		return null
	if inventory is FrameworkComponent:
		return (inventory as FrameworkComponent).get_entity()
	return inventory


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func describe() -> String:
	return "item_acquired: %d x %s" % [quantity, item_id]
