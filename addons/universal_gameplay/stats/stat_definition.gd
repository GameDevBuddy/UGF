class_name StatDefinition
extends FrameworkDefinition
## What one stat is: its range, whether it depletes, and how it comes back.
##
## Strength, max health, stamina, carry weight and fire resistance are all
## instances of this, differing only in data. A project adding "sanity" writes
## a [code].tres[/code] and nothing else (rule 11, rule 15).
##
## Two kinds of stat live here, and the distinction is the only structural one:
##
## [b]Attributes[/b] have a value that modifiers act on -- strength, armour,
## move speed. [b]Depletable[/b] stats additionally have a current value that
## drains and refills within that computed maximum -- stamina, mana, oxygen.
## Health is deliberately [i]not[/i] one of these: it has its own component
## because damage, death and mitigation are a pipeline, not a subtraction
## (rule 4 -- one owner, and for health that owner is [HealthComponent]).

## Starting value before modifiers. A per-entity override lives on the profile.
@export var default_base: float = 0.0

@export_group("Range")
@export var minimum: float = 0.0
## Upper clamp on the computed value. Leave at INF for an unbounded attribute.
@export var maximum: float = INF

@export_group("Depletion")
## Whether this stat has a current value that drains within its maximum.
@export var depletable: bool = false
## Units restored per second while regenerating.
@export var regen_per_second: float = 0.0
## Seconds after being spent before regeneration resumes. Stops a stamina bar
## refilling between two frames of sprinting.
@export var regen_delay: float = 0.0
## Whether a depletable stat starts full. Off starts it empty, which is what a
## charge-up resource wants.
@export var starts_full: bool = true


func get_minimum() -> float:
	return minimum


func get_maximum() -> float:
	return maximum


func regenerates() -> bool:
	return depletable and regen_per_second > 0.0


func validate() -> ValidationResult:
	var result := super()
	if minimum > maximum:
		result.add_error(
			&"stat_definition.inverted_range",
			"%s has a minimum above its maximum." % get_debug_name(),
			resource_path,
			"minimum"
		)
	if default_base < minimum or default_base > maximum:
		result.add_warning(
			&"stat_definition.base_outside_range",
			(
				"%s has a default base outside its own range; it will be clamped."
				% get_debug_name()
			),
			resource_path,
			"default_base"
		)
	if depletable and is_inf(maximum):
		result.add_error(
			&"stat_definition.unbounded_depletable",
			(
				"%s is depletable but unbounded, so it has no full to refill to."
				% get_debug_name()
			),
			resource_path,
			"maximum"
		)
	if regen_per_second > 0.0 and not depletable:
		result.add_warning(
			&"stat_definition.regen_without_depletion",
			(
				"%s regenerates but is not depletable, so regeneration does nothing."
				% get_debug_name()
			),
			resource_path,
			"regen_per_second"
		)
	if regen_delay < 0.0:
		result.add_error(
			&"stat_definition.negative_regen_delay",
			"%s has a negative regen delay." % get_debug_name(),
			resource_path,
			"regen_delay"
		)
	return result
