class_name InventoryPresenter
extends Presenter
## Publishes a bag as rows of plain data.
##
## The copying is the point. [method build] reads each [ItemInstance] and
## writes out numbers; nothing that reaches a widget can be used to change what
## is in the bag.

## The container to show. Found among this entity's own components when not
## wired — but frequently set explicitly, because the bag a panel shows is
## often a chest or a vendor's shelf rather than the player's own.
@export var inventory: InventoryComponent

## Whether to include condition on each row. Off saves a little work for a
## project whose items never wear.
@export var include_condition: bool = true


func observe() -> void:
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent
	_watch(inventory, &"contents_changed", _on_changed)


func stop_observing() -> void:
	_unwatch(inventory, &"contents_changed", _on_changed)


## Points this panel at a different container. What opening a chest calls.
func show_container(container: InventoryComponent) -> void:
	stop_observing()
	inventory = container
	observe()
	refresh()


func build() -> ViewModel:
	var model := InventoryViewModel.new()
	if inventory == null:
		return model
	model.present = true

	var profile := inventory.get_profile()
	model.used_slots = inventory.get_used_slots()
	model.free_slots = inventory.get_free_slots()
	model.total_weight = inventory.get_total_weight()
	model.maximum_weight = profile.max_weight if profile != null else 0.0
	model.total_value = inventory.get_total_value()

	for instance in inventory.get_items():
		if instance == null or instance.definition == null:
			continue
		var row: Dictionary = {
			"item_id": instance.get_definition_id(),
			"display_name": instance.get_display_name(),
			"quantity": instance.quantity,
			"category": instance.definition.category,
			"weight": instance.get_total_weight(),
			"value": instance.get_total_value(),
		}
		if include_condition and instance.has_durability():
			row["condition"] = instance.get_condition()
			row["broken"] = instance.is_broken()
		model.rows.append(row)
	return model


func _on_changed() -> void:
	refresh()
