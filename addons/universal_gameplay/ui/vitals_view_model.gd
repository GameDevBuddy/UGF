class_name VitalsViewModel
extends ViewModel
## Everything a health bar and a needs panel draw.
##
## One model rather than two, because a HUD showing health and hunger updates
## both at once and a widget handed two snapshots taken a frame apart draws a
## contradiction. Combining them is what makes the pair consistent by
## construction.

var health: float = 0.0
var maximum_health: float = 0.0
var health_fraction: float = 0.0
var alive: bool = true

## Whether this entity has health at all. A crate with no [HealthComponent] is
## a valid subject; the bar is simply hidden.
var has_health: bool = false

## Need id to its current fraction, 0..1. Fractions rather than raw values,
## because a bar is drawn from a fraction and a widget should not have to know
## what "full" is for hunger.
var need_fractions: Dictionary = {}

## Needs currently in their critical band. What a HUD flashes.
var critical_needs: Array[StringName] = []

## Effect ids currently applied, so a status row can draw icons without
## asking the component.
var effects: Array[StringName] = []


func has_needs() -> bool:
	return not need_fractions.is_empty()


func get_need_fraction(need: StringName) -> float:
	return need_fractions.get(need, 0.0)


func is_critical(need: StringName) -> bool:
	return critical_needs.has(need)


func has_effect(effect_id: StringName) -> bool:
	return effects.has(effect_id)


func to_dictionary() -> Dictionary:
	var data := super()
	data.merge({
		"has_health": has_health,
		"health": health,
		"maximum_health": maximum_health,
		"health_fraction": health_fraction,
		"alive": alive,
		"need_fractions": need_fractions.duplicate(),
		"critical_needs": critical_needs.duplicate(),
		"effects": effects.duplicate(),
	})
	return data
