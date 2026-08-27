class_name StatsProfile
extends Resource
## The set of stats one kind of entity has, and what its bases are.
##
## The profile pattern again (rule 14): one
## [code]stats_guard_standard.tres[/code] shared by every guard in a project,
## with a heavier variant as a second resource rather than a second class. A
## definition says what a stat [i]is[/i]; a profile says which of them this
## entity carries and where its numbers start.

## Stats this entity has. An entity with no entry for a stat does not have that
## stat, and asking for it returns the fallback rather than inventing one.
@export var stats: Array[StatDefinition] = []

## Per-profile base overrides, keyed by stat id. Lets one definition of
## [code]stat.strength[/code] serve a civilian and an ogre.
@export var base_overrides: Dictionary[StringName, float] = {}

## Modifiers this profile always applies, e.g. a species-wide resistance.
## Removable by source like any other, though nothing normally removes them.
@export var innate_modifiers: Array[StatModifier] = []


func has_stat(id: StringName) -> bool:
	return get_definition(id) != null


func get_definition(id: StringName) -> StatDefinition:
	for definition in stats:
		if definition != null and definition.id == id:
			return definition
	return null


## Starting base for a stat: the override if there is one, else the
## definition's default.
func get_base(id: StringName, fallback: float = 0.0) -> float:
	if base_overrides.has(id):
		return base_overrides[id]
	var definition := get_definition(id)
	return definition.default_base if definition != null else fallback


func get_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in stats:
		if definition != null and definition.id != &"":
			ids.append(definition.id)
	return ids


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	var seen: Dictionary[StringName, bool] = {}
	for definition in stats:
		if definition == null:
			result.add_warning(
				&"stats_profile.null_stat",
				"The stats array has an empty slot.",
				resource_path,
				"stats"
			)
			continue
		if seen.has(definition.id):
			result.add_error(
				&"stats_profile.duplicate_stat",
				(
					"Stat '%s' appears twice; which base wins would be arbitrary."
					% definition.id
				),
				resource_path,
				"stats"
			)
		seen[definition.id] = true
		result.merge(definition.validate())
		if definition.derivation != null and not definition.derivation.is_empty():
			result.merge(definition.derivation.validate(definition.id, resource_path))

	result.merge(_check_derivation_sources(seen))
	result.merge(_check_derivation_cycles())

	for id in base_overrides:
		if not seen.has(id):
			result.add_warning(
				&"stats_profile.override_without_stat",
				(
					"Base override for '%s' but this profile has no such stat, so it "
					+ "is ignored."
				) % id,
				resource_path,
				"base_overrides"
			)

	for modifier in innate_modifiers:
		if modifier == null:
			continue
		result.merge(modifier.validate())
		if modifier.stat != &"" and not seen.has(modifier.stat):
			result.add_warning(
				&"stats_profile.modifier_without_stat",
				(
					"Innate modifier targets '%s' but this profile has no such stat."
					% modifier.stat
				),
				resource_path,
				"innate_modifiers"
			)
	return result


## Derivations reading a stat this profile does not carry.
##
## Not an error: a source the entity lacks contributes nothing, which is the
## right behaviour for a crate with no strength. But it is almost always a
## typo, and a derived stat quietly equal to its constant is the kind of wrong
## number nobody notices for months.
func _check_derivation_sources(known: Dictionary[StringName, bool]) -> ValidationResult:
	var result := ValidationResult.new()
	for definition in stats:
		if definition == null or definition.derivation == null:
			continue
		for source in definition.derivation.sources:
			if source != &"" and not known.has(source):
				result.add_warning(
					&"stats_profile.unknown_derivation_source",
					(
						"'%s' derives from '%s', which this profile does not "
						+ "carry, so that term contributes nothing."
					) % [definition.id, source],
					resource_path,
					"stats"
				)
	return result


## Derivations that read each other, directly or through others.
##
## The runtime survives one -- it breaks the loop and returns the authored
## base -- but the value it returns is meaningless, so the author has to be
## told rather than left with a number that looks computed.
func _check_derivation_cycles() -> ValidationResult:
	var result := ValidationResult.new()
	var edges: Dictionary[StringName, Array] = {}
	for definition in stats:
		if definition == null or definition.derivation == null:
			continue
		var sources: Array[StringName] = []
		for source in definition.derivation.sources:
			if source != &"":
				sources.append(source)
		if not sources.is_empty():
			edges[definition.id] = sources

	for cycle in DefinitionValidator.find_cycles(edges):
		var names: Array[String] = []
		for id in cycle:
			names.append(str(id))
		result.add_error(
			&"stats_profile.derivation_cycle",
			(
				"These stats derive from each other, so none of them has a "
				+ "value to compute: %s."
			) % " -> ".join(names),
			resource_path,
			"stats"
		)
	return result
