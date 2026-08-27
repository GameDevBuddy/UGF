class_name StatusEffectDefinition
extends FrameworkDefinition
## A buff, a debuff, a poison, a burning. All the same type, differing in data.
##
## Poison and a strength potion are not two classes: one has a periodic damage
## tick and a stacking policy, the other has a stat modifier and a duration
## (rule 11). Adding a new effect to a project is a [code].tres[/code].

enum Stacking {
	## A second application refreshes the first's duration. The common case.
	REFRESH,
	## Applications accumulate up to [member max_stacks], each adding its
	## modifiers again. Refreshing duration as well.
	STACK,
	## A second application is refused while the first is running. For effects
	## where re-triggering would be exploitable.
	IGNORE,
	## Each application is tracked separately with its own timer. For effects
	## from distinct sources that should expire independently.
	SEPARATE,
}

## Seconds the effect lasts. Zero or less is permanent until removed, which is
## what an equipment-granted effect wants.
@export var duration: float = 0.0

@export var stacking: Stacking = Stacking.REFRESH

## Cap for [constant Stacking.STACK]. Ignored by the other policies.
@export_range(1, 999) var max_stacks: int = 1

@export_group("Effects")
## Stat modifiers applied while active. Their source is overwritten with this
## effect's id on application, so removal takes back exactly these.
@export var modifiers: Array[StatModifier] = []

## Damage per second while active. Negative heals, which is how a regeneration
## effect is expressed without a second field.
@export var damage_per_second: float = 0.0

## Tags on the periodic damage, so resistances apply to a poison the same way
## they apply to a hit.
@export var damage_tags: Array[StringName] = []

## Seconds between periodic applications. Zero applies continuously, scaled by
## frame time; a positive value makes the tick discrete and predictable, which
## is what a damage-number popup needs.
@export var tick_interval: float = 1.0

@export_group("Semantics")
## Semantic state tags added to the entity while this is active.
@export var applied_states: Array[StringName] = []

## Effects this one removes on application, by id. A cleanse lists what it
## cures; a chill lists burning.
@export var removes: Array[StringName] = []

## Whether this effect survives a save. Off for effects a project would rather
## reapply from their source on load.
@export var persistent: bool = true


func is_permanent() -> bool:
	return duration <= 0.0


func is_periodic() -> bool:
	return not is_zero_approx(damage_per_second)


func stacks() -> bool:
	return stacking == Stacking.STACK


## Modifiers with their source rewritten to this effect's id.
##
## Authored modifiers usually leave source blank, and getting it wrong would
## mean an expiring effect either removes nothing or removes another effect's
## work. Stamping it here makes that impossible to get wrong by hand.
func build_modifiers() -> Array[StatModifier]:
	var built: Array[StatModifier] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		var copy := modifier.duplicate() as StatModifier
		copy.source = id
		built.append(copy)
	return built


func validate() -> ValidationResult:
	var result := super()
	if stacking == Stacking.STACK and max_stacks <= 1:
		result.add_warning(
			&"status_effect.stacking_without_stacks",
			(
				"%s stacks but allows only one stack, which behaves as REFRESH."
				% get_debug_name()
			),
			resource_path,
			"max_stacks"
		)
	if is_periodic() and tick_interval < 0.0:
		result.add_error(
			&"status_effect.negative_interval",
			"%s has a negative tick interval." % get_debug_name(),
			resource_path,
			"tick_interval"
		)
	if is_permanent() and is_periodic():
		result.add_warning(
			&"status_effect.permanent_periodic",
			(
				"%s is permanent and deals damage over time, so it will damage its "
				+ "target forever unless something removes it."
			) % get_debug_name(),
			resource_path,
			"duration"
		)
	if modifiers.is_empty() and not is_periodic() and applied_states.is_empty():
		result.add_warning(
			&"status_effect.does_nothing",
			(
				"%s has no modifiers, no periodic damage and no state tags, so it "
				+ "does nothing."
			) % get_debug_name(),
			resource_path,
			"modifiers"
		)
	if removes.has(id):
		result.add_warning(
			&"status_effect.removes_itself",
			"%s lists itself as an effect it removes." % get_debug_name(),
			resource_path,
			"removes"
		)
	# Deliberately not merging StatModifier.validate() here: it warns about a
	# blank source, and a blank source is *correct* on an authored effect --
	# build_modifiers() stamps this effect's id over it. Only the checks that
	# still apply are repeated.
	for modifier in modifiers:
		if modifier == null:
			result.add_warning(
				&"status_effect.null_modifier",
				"%s has an empty modifier slot." % get_debug_name(),
				resource_path,
				"modifiers"
			)
		elif modifier.stat == &"":
			result.add_error(
				&"status_effect.modifier_without_stat",
				"%s has a modifier that names no stat." % get_debug_name(),
				resource_path,
				"modifiers"
			)
	return result
