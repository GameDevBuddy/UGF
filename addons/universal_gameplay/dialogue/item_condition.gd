class_name ItemCondition
extends DialogueCondition
## Asks whether someone is carrying something. The quest item, the bribe, the
## severed head.
##
## The second condition implementation, and the one that earns the abstraction
## (rule 23): it reads a completely different store from [NarrativeCondition]
## and cannot be expressed as a comparison against narrative state.
##
## Named by item id rather than by a definition reference, so a conversation
## and the item it asks about do not have to load each other (rule 32).

enum Party {
	## The one being spoken to. Usually the player.
	LISTENER,
	## The one doing the talking.
	SPEAKER,
}

@export var party: Party = Party.LISTENER

@export var item_id: StringName = &""

@export_range(1, 9999) var quantity: int = 1

## Inverts the question: true when they do [i]not[/i] have it.
@export var negate: bool = false


func evaluate(context: DialogueContext) -> bool:
	if context == null or item_id == &"":
		return false
	var inventory := _get_inventory(context)
	# No bag at all is not an error, it is a "no" -- and a negated condition
	# should therefore say yes (rule 31).
	var carried := inventory != null and inventory.has(item_id, quantity)
	return not carried if negate else carried


func describe() -> String:
	var subject := "speaker" if party == Party.SPEAKER else "listener"
	var verb := "lacks" if negate else "has"
	return "%s %s %d x %s" % [subject, verb, quantity, item_id]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"item_condition.no_item_id",
			"An item condition with no item id can never be met.",
			resource_path,
			"item_id"
		)
	if quantity < 1:
		result.add_error(
			&"item_condition.bad_quantity",
			"An item condition for fewer than one item is meaningless.",
			resource_path,
			"quantity"
		)
	return result


func _get_inventory(context: DialogueContext) -> InventoryComponent:
	if party == Party.SPEAKER:
		return context.get_speaker_inventory()
	return context.get_listener_inventory()
