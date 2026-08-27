class_name InventoryProfile
extends Resource
## What one container can hold: how much, and what kind.
##
## The same profile serves a character's backpack, a vehicle's boot, a chest
## and a vendor's stock — they differ in numbers and filters, not in code
## (rule 6, rule 11). A vehicle's storage is this component with a different
## profile, which is what Implementation Plan 22 means by reusing Inventory for
## vehicles.

@export_group("Capacity")
## How many stacks fit. Zero or less is unlimited, which is what a vendor's
## stock or a debug container wants.
@export var slot_count: int = 20

## Total weight allowed. Zero or less is unlimited.
@export var max_weight: float = 0.0

@export_group("Filters")
## Categories this accepts. Empty accepts every category.
@export var accepted_categories: Array[StringName] = []

## Categories this refuses, checked after [member accepted_categories]. A
## rejection always wins, so a container can accept everything except one kind.
@export var rejected_categories: Array[StringName] = []

## Tags an item must have at least one of. Empty requires none.
@export var required_tags: Array[StringName] = []


func has_slot_limit() -> bool:
	return slot_count > 0


func has_weight_limit() -> bool:
	return max_weight > 0.0


## Whether this container would take that item at all, ignoring how full it is.
##
## Separate from capacity on purpose: "this bag does not take weapons" and
## "this bag is full" are different refusals, and a caller usually wants to say
## which one happened.
func accepts(definition: ItemDefinition) -> bool:
	if definition == null:
		return false
	if rejected_categories.has(definition.category):
		return false
	if not accepted_categories.is_empty() and not accepted_categories.has(definition.category):
		return false
	if not required_tags.is_empty() and not definition.has_any_tag(required_tags):
		return false
	return true


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if max_weight < 0.0:
		result.add_error(
			&"inventory_profile.negative_weight",
			"max_weight is negative. Use zero for unlimited.",
			resource_path,
			"max_weight"
		)
	for category in accepted_categories:
		if rejected_categories.has(category):
			result.add_error(
				&"inventory_profile.contradictory_filter",
				(
					"'%s' is both accepted and rejected, so nothing of that category "
					+ "can ever be stored."
				) % category,
				resource_path,
				"accepted_categories"
			)
	if not has_slot_limit() and not has_weight_limit():
		result.add_info(
			&"inventory_profile.unlimited",
			"This container has no slot or weight limit and will accept items forever.",
			resource_path
		)
	return result
