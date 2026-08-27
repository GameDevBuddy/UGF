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
