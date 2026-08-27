extends FrameworkEvent
## Something changed hands.
##
## One event class for buying and selling, named apart on the bus so a
## subscriber matches on direction without reading a field. Missions count
## purchases; crime counts sales of stolen goods; a tutorial counts the first
## of either.
##
## No class_name: events are constructed by the service that publishes them
## and matched by name on the bus.

var name_override: StringName = &""
var customer: Node = null
var vendor: Node = null
var item_id: StringName = &""
var quantity: int = 0
var currency: StringName = &""
var total: float = 0.0
var tags: Array[StringName] = []


static func create(context: TradeContext) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/commerce/commerce_event.gd"
	) as GDScript).new()
	event.name_override = (
		GameplayNames.EVENT_ITEM_PURCHASED if context.is_buy()
		else GameplayNames.EVENT_ITEM_SOLD
	)
	event.customer = context.customer
	event.vendor = context.vendor
	event.source = context.customer
	event.item_id = context.item_id
	event.quantity = context.quantity
	event.currency = context.currency
	event.total = context.total
	for instance in context.moved:
		if instance != null and instance.definition != null:
			event.tags = instance.definition.tags.duplicate()
			break
	return event


func get_event_name() -> StringName:
	return name_override


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func describe() -> String:
	return "%s: %d x %s for %.2f" % [name_override, quantity, item_id, total]
