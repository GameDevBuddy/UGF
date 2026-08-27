class_name StatModifier
extends Resource
## One change to one stat, and where it came from.
##
## A Resource rather than a plain object so a status effect or a piece of
## equipment can carry its modifiers as authored data (rule 11). Adding
## "+15% fire resistance while buffed" should be a [code].tres[/code] edit, not
## a new class.
##
## [b]Source tracking is not optional.[/b] Every modifier records who applied
## it, because removal is by source: a buff expiring has to take away exactly
## what it added, and a stat that cannot say which of its modifiers belongs to
## which effect will drift every time two effects overlap. That drift is
## invisible until a save is reloaded and the numbers have moved.

enum Mode {
	## Added to the base before any percentage applies. Stacks by sum.
	FLAT,
	## Fraction added to a single multiplier shared by all additive percentages,
	## so +10% and +10% make +20%, not +21%.
	PERCENT_ADD,
	## Fraction applied as its own multiplier, so two +10% make +21%. Use for
	## effects that should compound.
	PERCENT_MULTIPLY,
}

## Stat this modifies, e.g. [code]stat.health.max[/code].
@export var stat: StringName = &""

@export var mode: Mode = Mode.FLAT

## Amount. For the percentage modes this is a fraction: 0.1 is +10%.
@export var value: float = 0.0

## What applied this. Removal is by source, so two effects must not share one
## unless they are genuinely meant to be removed together.
@export var source: StringName = &""

## Ordering within a mode, low to high. Only matters for PERCENT_MULTIPLY,
## where multiplication is commutative anyway -- it exists so a project with a
## house rule about application order has somewhere to express it.
@export var priority: int = 0


static func create(
	p_stat: StringName,
	p_mode: Mode,
	p_value: float,
	p_source: StringName = &""
) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = p_stat
	modifier.mode = p_mode
	modifier.value = p_value
	modifier.source = p_source
	return modifier


static func flat(p_stat: StringName, p_value: float, p_source: StringName = &"") -> StatModifier:
	return create(p_stat, Mode.FLAT, p_value, p_source)


static func percent(p_stat: StringName, p_value: float, p_source: StringName = &"") -> StatModifier:
	return create(p_stat, Mode.PERCENT_ADD, p_value, p_source)


static func multiplier(
	p_stat: StringName, p_value: float, p_source: StringName = &""
) -> StatModifier:
	return create(p_stat, Mode.PERCENT_MULTIPLY, p_value, p_source)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if stat == &"":
		result.add_error(
			&"stat_modifier.missing_stat",
			"A modifier with no stat changes nothing.",
			resource_path,
			"stat"
		)
	if source == &"":
		result.add_warning(
			&"stat_modifier.missing_source",
			(
				"Modifier on '%s' has no source, so nothing can remove it by source."
				% stat
			),
			resource_path,
			"source"
		)
	if mode == Mode.PERCENT_MULTIPLY and is_equal_approx(value, -1.0):
		result.add_warning(
			&"stat_modifier.zeroing_multiplier",
			"A -100%% compounding modifier on '%s' zeroes the stat outright." % stat,
			resource_path,
			"value"
		)
	return result


func _to_string() -> String:
	match mode:
		Mode.FLAT:
			return "%s %+.2f (%s)" % [stat, value, source]
		Mode.PERCENT_ADD:
			return "%s %+.0f%% add (%s)" % [stat, value * 100.0, source]
		_:
			return "%s x%.2f (%s)" % [stat, 1.0 + value, source]
