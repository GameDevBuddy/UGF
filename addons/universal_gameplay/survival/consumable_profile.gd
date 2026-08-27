class_name ConsumableProfile
extends Resource
## What eating, drinking or injecting something does.
##
## Hangs off [member ItemDefinition.consumable], the way an equipment profile
## does: a ration is an item that can be carried, sold and eaten, not a Ration
## class (rule 13, rule 16).

## Needs restored, parallel to [member restore_amounts]. Exported as parallel
## arrays because Godot exports those and not typed dictionaries.
@export var restores_needs: Array[StringName] = []

@export var restore_amounts: Array[float] = []

@export_group("Health")
## Health restored on use. Negative hurts, which is what a bad mushroom is.
@export_range(-1000.0, 1000.0, 0.1) var health: float = 0.0

@export_group("Effects")
## Status effects applied on use, by id. Ids rather than resources so an item
## does not have to load the effects it applies (rule 32).
@export var effects: Array[StringName] = []

@export_group("Consumption")
## Units used per consumption.
@export_range(1, 99) var uses: int = 1

## Whether the item is removed when consumed. Off is a flask that empties into
## a container the project tracks itself.
@export var consumed: bool = true


func restores(need: StringName) -> float:
	var index := restores_needs.find(need)
	if index < 0 or index >= restore_amounts.size():
		return 0.0
	return restore_amounts[index]


func has_any_effect() -> bool:
	return (
		not restores_needs.is_empty()
		or not is_equal_approx(health, 0.0)
		or not effects.is_empty()
	)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if restores_needs.size() != restore_amounts.size():
		result.add_error(
			&"consumable.mismatched_restores",
			(
				"This consumable names %d needs and %d amounts; the extras on "
				+ "one side are never applied."
			) % [restores_needs.size(), restore_amounts.size()],
			resource_path,
			"restore_amounts"
		)
	if not has_any_effect():
		result.add_warning(
			&"consumable.does_nothing",
			"This consumable restores nothing and applies nothing.",
			resource_path,
			"restores_needs"
		)
	for need in restores_needs:
		if need == &"":
			result.add_warning(
				&"consumable.unnamed_need",
				"This consumable restores an unnamed need.",
				resource_path,
				"restores_needs"
			)
	return result
