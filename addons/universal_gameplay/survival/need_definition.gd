class_name NeedDefinition
extends FrameworkDefinition
## A meter that drains: hunger, thirst, fatigue, oxygen, warmth, sanity.
##
## [b]One definition for all of them.[/b] Implementation Plan 15 calls needs
## "generic meters driven by NeedDefinition" and means it: hunger and body
## temperature differ in their numbers and in which states they set, not in
## code. Temperature is the interesting case -- it drains towards a comfortable
## middle rather than towards empty -- and that is
## [member drains_towards], not a second class (rule 11, rule 23).

## Full value. A need is measured 0..[member maximum].
@export_range(1.0, 10000.0, 0.1, "or_greater") var maximum: float = 100.0

## Where it starts. Above the maximum is clamped.
@export_range(0.0, 10000.0, 0.1, "or_greater") var starting_value: float = 100.0

## Units lost per second. Negative fills instead, which is what a need that
## recovers on its own looks like.
@export_range(-100.0, 100.0, 0.001, "or_greater") var decay_per_second: float = 0.1

## The value decay pulls towards. Zero is the usual case -- hunger drains to
## empty. A body-temperature need sets this to its comfortable middle, so it
## falls when hot and rises when cold without a second mechanism.
@export_range(0.0, 10000.0, 0.1, "or_greater") var drains_towards: float = 0.0

@export_group("Thresholds")
## Fraction at or below which the need is "low": hungry, tired, chilly.
@export_range(0.0, 1.0, 0.01) var low_fraction: float = 0.3

## Fraction at or below which it is "critical": starving, freezing.
@export_range(0.0, 1.0, 0.01) var critical_fraction: float = 0.1

## Semantic state set while the need is low. Blank sets none.
@export var low_state: StringName = &""

## Semantic state set while it is critical.
@export var critical_state: StringName = &""

@export_group("Consequences")
## Health lost per second while the need is empty. Zero never kills, which is
## right for a comfort meter and wrong for oxygen.
@export_range(0.0, 1000.0, 0.1, "or_greater") var damage_per_second: float = 0.0

## Damage tags used for that damage, so armour and immunity can apply.
@export var damage_tags: Array[StringName] = []

## Status effect applied while critical, by id. Blank applies none. An id
## rather than a resource so Survival does not have to load the effects it
## names (rule 32).
@export var critical_effect: StringName = &""


func get_fraction(value: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(value / maximum, 0.0, 1.0)


func is_low(value: float) -> bool:
	return get_fraction(value) <= low_fraction


func is_critical(value: float) -> bool:
	return get_fraction(value) <= critical_fraction


func is_empty(value: float) -> bool:
	return value <= 0.0


func clamp_value(value: float) -> float:
	return clampf(value, 0.0, maximum)


## Where the need sits after [param delta] seconds of nothing happening.
##
## Decay moves towards [member drains_towards] rather than always downwards, so
## a temperature need warms as readily as it cools and never overshoots the
## middle in one long frame.
func decay(value: float, delta: float, rate_scale: float = 1.0) -> float:
	if delta <= 0.0 or is_equal_approx(decay_per_second, 0.0):
		return value
	var step := decay_per_second * delta * rate_scale
	if value > drains_towards:
		return clamp_value(maxf(drains_towards, value - step))
	if value < drains_towards:
		return clamp_value(minf(drains_towards, value + step))
	return value


func validate() -> ValidationResult:
	var result := super()
	if starting_value > maximum:
		result.add_warning(
			&"need.starts_above_maximum",
			"%s starts above its maximum and will be clamped." % get_debug_name(),
			resource_path,
			"starting_value"
		)
	if critical_fraction > low_fraction:
		result.add_error(
			&"need.inverted_thresholds",
			(
				"%s is critical before it is low, so it would never pass "
				+ "through the warning band."
			) % get_debug_name(),
			resource_path,
			"critical_fraction"
		)
	if damage_per_second > 0.0 and damage_tags.is_empty():
		result.add_warning(
			&"need.untagged_damage",
			(
				"%s deals damage with no tags, so no resistance or immunity "
				+ "can ever apply to it."
			) % get_debug_name(),
			resource_path,
			"damage_tags"
		)
	if is_equal_approx(decay_per_second, 0.0) and damage_per_second > 0.0:
		result.add_info(
			&"need.never_decays",
			(
				"%s never decays on its own, so its damage only applies if "
				+ "something else empties it."
			) % get_debug_name(),
			resource_path,
			"decay_per_second"
		)
	return result
