class_name StatCalculator
extends RefCounted
## Deterministic stat arithmetic. Static, node-free, and the whole reason
## "modifiers stack predictably" is a testable claim.
##
## [b]The order is fixed and it matters.[/b]
## [codeblock]
## (base + sum(FLAT)) * (1 + sum(PERCENT_ADD)) * product(1 + PERCENT_MULTIPLY)
## [/codeblock]
## then clamped. Two +10% additive modifiers give +20%; two +10% compounding
## modifiers give +21%. Both behaviours are wanted somewhere -- flat gear
## bonuses should add, rare compounding buffs should not -- and the only way a
## designer can rely on either is if the framework picks one order and never
## quietly changes it.
##
## Everything here takes its inputs as arguments and returns a number. No node,
## no component, no state (rule 33).


## The value of a stat after every modifier that applies to it.
##
## Modifiers for other stats are ignored rather than rejected, so a caller can
## hand over an entity's whole modifier list without filtering it first.
static func calculate(
	base: float,
	modifiers: Array,
	stat: StringName = &"",
	minimum: float = -INF,
	maximum: float = INF
) -> float:
	var flat := 0.0
	var percent_add := 0.0
	var compound := 1.0

	for entry in modifiers:
		var modifier := entry as StatModifier
		if modifier == null:
			continue
		if stat != &"" and modifier.stat != stat:
			continue
		match modifier.mode:
			StatModifier.Mode.FLAT:
				flat += modifier.value
			StatModifier.Mode.PERCENT_ADD:
				percent_add += modifier.value
			StatModifier.Mode.PERCENT_MULTIPLY:
				compound *= 1.0 + modifier.value

	var value := (base + flat) * (1.0 + percent_add) * compound
	return clampf(value, minimum, maximum)


## Modifiers from [param modifiers] that apply to [param stat], in the order
## they would be applied. For debug tooling and for explaining a number to a
## player who asks why it is what it is (rule 28).
static func collect_for(modifiers: Array, stat: StringName) -> Array[StatModifier]:
	var matching: Array[StatModifier] = []
	for entry in modifiers:
		var modifier := entry as StatModifier
		if modifier != null and modifier.stat == stat:
			matching.append(modifier)
	matching.sort_custom(
		func(a: StatModifier, b: StatModifier) -> bool:
			if a.mode != b.mode:
				return a.mode < b.mode
			return a.priority < b.priority
	)
	return matching


## Every distinct stat the modifiers touch.
static func affected_stats(modifiers: Array) -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	var stats: Array[StringName] = []
	for entry in modifiers:
		var modifier := entry as StatModifier
		if modifier == null or modifier.stat == &"" or seen.has(modifier.stat):
			continue
		seen[modifier.stat] = true
		stats.append(modifier.stat)
	return stats


## A human-readable breakdown of how a value was reached.
##
## Debugability is architecture (rule 28). "Why is my damage 47?" is a question
## the framework should be able to answer without a debugger attached.
static func explain(
	base: float,
	modifiers: Array,
	stat: StringName,
	minimum: float = -INF,
	maximum: float = INF
) -> String:
	var lines: Array[String] = ["%s: base %.2f" % [stat, base]]
	for modifier in collect_for(modifiers, stat):
		lines.append("  %s" % str(modifier))
	var value := calculate(base, modifiers, stat, minimum, maximum)
	var unclamped := calculate(base, modifiers, stat)
	if not is_equal_approx(value, unclamped):
		lines.append("  clamped from %.2f to [%.2f, %.2f]" % [unclamped, minimum, maximum])
	lines.append("  = %.2f" % value)
	return "\n".join(lines)
