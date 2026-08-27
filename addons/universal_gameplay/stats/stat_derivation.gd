class_name StatDerivation
extends Resource
## A stat whose base is computed from other stats.
##
## Implementation Plan 12 lists derived stats alongside attributes and
## modifiers. Every modifier in this framework carries a literal authored
## number, so before this there was no way to say "carry weight is twice
## strength" -- the only cross-stat derivation anywhere was
## [HealthComponent]'s [code]maximum_stat[/code], a hand-wired special case in
## another module that content could not author.
##
## [b]A weighted sum, not a formula language.[/b] Nearly every derived stat in
## nearly every RPG is one: carry weight from strength, dodge from agility,
## mana from intelligence and wisdom. A general expression evaluator would be a
## parser nobody asked for, an interpreter to debug and a security surface, all
## for the rare case (rule 23). A project needing something genuinely nonlinear
## computes it and calls [method StatsComponent.set_base].
##
## [b]It replaces the base, not the value.[/b] A derived stat still takes
## modifiers on top, so "+10% carry weight while a mule" works exactly as it
## does on any other stat, and removal is still by source.

## Stats this reads. Parallel to [member coefficients].
@export var sources: Array[StringName] = []

## Multiplier for each source, in the same order. A source with no matching
## coefficient contributes nothing rather than defaulting to one: silently
## weighting a stat by 1.0 because somebody forgot a row is how a character
## ends up with carry weight equal to their intelligence.
@export var coefficients: Array[float] = []

## Added after the weighted sum. The flat floor most derived stats want, so a
## character with zero strength can still carry something.
@export var constant: float = 0.0

## Applied to the whole result. Left at zero and one, no rounding happens.
@export var minimum: float = 0.0

@export var maximum: float = 0.0

## Rounds the result down to a whole number. For a derived stat that counts
## things -- inventory slots, attacks per turn -- where 4.7 slots is not a
## number the rest of the game can use.
@export var whole_numbers: bool = false


## The derived base, given the current value of each source.
##
## Takes a plain dictionary rather than the component, so the arithmetic is
## testable with no entity, no scene and no stats component at all (rule 33).
## A source absent from [param values] contributes nothing -- which is the
## honest answer when the entity does not have that stat, and is why a crate
## with no strength gets the constant rather than an error.
func evaluate(values: Dictionary) -> float:
	var total := constant
	for index in sources.size():
		var source: StringName = sources[index]
		if not values.has(source):
			continue
		if index >= coefficients.size():
			continue
		total += float(values[source]) * coefficients[index]

	if maximum > minimum:
		total = clampf(total, minimum, maximum)
	elif minimum != 0.0:
		total = maxf(total, minimum)
	return floorf(total) if whole_numbers else total


func is_empty() -> bool:
	return sources.is_empty()


func validate(owner_id: StringName = &"", source_path: String = "") -> ValidationResult:
	var result := ValidationResult.new()
	if sources.size() != coefficients.size():
		result.add_error(
			&"derivation.mismatched_rows",
			(
				"%s derives from %d stat(s) but lists %d coefficient(s). The "
				+ "extra rows are silently ignored."
			) % [owner_id, sources.size(), coefficients.size()],
			source_path,
			"coefficients"
		)
	if sources.has(owner_id):
		result.add_error(
			&"derivation.self_reference",
			"%s derives from itself, which has no value to compute." % owner_id,
			source_path,
			"sources"
		)
	for source in sources:
		if source == &"":
			result.add_warning(
				&"derivation.empty_source",
				"%s derives from an unnamed stat." % owner_id,
				source_path,
				"sources"
			)
	if maximum != 0.0 and maximum < minimum:
		result.add_error(
			&"derivation.inverted_range",
			(
				"%s clamps to a maximum below its minimum, so every value "
				+ "collapses to one number."
			) % owner_id,
			source_path,
			"maximum"
		)
	return result
