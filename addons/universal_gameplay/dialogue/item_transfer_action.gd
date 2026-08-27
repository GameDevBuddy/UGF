class_name ItemTransferAction
extends DialogueAction
## Hands something over, or takes it away.
##
## The first shipped [DialogueAction] that commands a feature rather than
## writing narrative state. Implementation Plan 18 asks for dialogue actions
## that issue explicit feature commands; before this, every shipped action set
## a flag and left "and give them the key" as an exercise.
##
## [b]It commands; it does not reimplement.[/b] The action calls
## [method InventoryComponent.add] and [method InventoryComponent.remove] and
## adds nothing of its own -- no capacity rule, no stacking, no ownership. That
## is what makes it safe for Dialogue to carry: it is a verb, and Inventory
## remains the only thing that knows what happens when you say it.

enum Direction {
	## Speaker to listener. The quest giver handing over a key.
	TO_LISTENER,
	## Listener to speaker. Paying a toll, handing in a delivery.
	TO_SPEAKER,
}

@export var direction: Direction = Direction.TO_LISTENER

@export var item_id: StringName = &""

@export_range(1, 9999) var quantity: int = 1

## Takes the item out of the giver's bag as well as putting it in the
## receiver's.
##
## [b]Off by default, and that is deliberate.[/b] A quest giver handing out a
## key almost never has one in a bag -- the key exists because the conversation
## says so. Turning this on makes the action a real transfer, which is what a
## trade or a delivery wants, and it then fails when the giver has nothing.
@export var from_giver_inventory: bool = false


func execute(context: DialogueContext) -> FrameworkResult:
	if context == null or item_id == &"":
		return FrameworkResult.fail(&"dialogue.no_item", "This action names no item.")

	var receiver := _receiver(context)
	if receiver == null:
		return FrameworkResult.fail(
			&"dialogue.no_inventory", "The receiving side has no inventory."
		)

	var definition := _resolve(context)
	if definition == null:
		return FrameworkResult.fail(
			&"dialogue.unknown_item",
			"No item definition '%s' is registered." % item_id
		)

	if from_giver_inventory:
		var giver := _giver(context)
		if giver == null:
			return FrameworkResult.fail(
				&"dialogue.no_inventory", "The giving side has no inventory."
			)
		# Taken before it is given, so a failure leaves both bags untouched
		# rather than duplicating the item (rule 17).
		var taken := giver.remove(item_id, quantity)
		if taken.is_err():
			return taken

	return receiver.add(ItemInstance.create(definition, quantity))


func describe() -> String:
	var verb := "gives" if direction == Direction.TO_LISTENER else "takes"
	return "%s %d x %s" % [verb, quantity, item_id]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"dialogue.action_no_item",
			"An item transfer action names no item.",
			resource_path,
			"item_id"
		)
	return result


func _receiver(context: DialogueContext) -> InventoryComponent:
	if direction == Direction.TO_LISTENER:
		return context.get_listener_inventory()
	return context.get_speaker_inventory()


func _giver(context: DialogueContext) -> InventoryComponent:
	if direction == Direction.TO_LISTENER:
		return context.get_speaker_inventory()
	return context.get_listener_inventory()


## Resolves the definition through the registry rather than holding one.
##
## A conversation and every item it can hand over should not have to load each
## other, and an id in a save file survives a resource being moved (rule 32).
func _resolve(context: DialogueContext) -> ItemDefinition:
	var core := context.extras.get("core")
	if core == null and context.listener != null:
		core = context.listener.get_tree().root.get_node_or_null("FrameworkCore")
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", item_id) as ItemDefinition
