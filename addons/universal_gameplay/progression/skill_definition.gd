class_name SkillDefinition
extends FrameworkDefinition
## Something a character can unlock by spending points.
##
## Perk, skill, talent, trait: the plan's "perk/skill unlock hooks" is one
## shape with several names, so it is one class (rule 23). What a skill *does*
## is carried as [StatModifier]s and semantic states rather than as behaviour,
## which is what keeps Progression from needing to know about Combat, Survival
## or anything else it might buff.
##
## [b]A skill grants; it never acts.[/b] A perk that says "gain a double jump"
## is authored as a state tag Locomotion already reads, not as code here. The
## moment this class could run something, Progression would need every module
## it could run something in, and rule 10 would be gone.

## Track this belongs to. Its level gates the unlock.
@export var track_id: StringName = &""

## Level on that track before this can be taken.
@export_range(1, 999) var required_level: int = 1

## Points it costs. Zero is legal: a skill granted automatically at a level.
@export_range(0, 99) var cost: int = 1

@export_group("Prerequisites")
## Other skills that must already be unlocked.
@export var requires_skills: Array[StringName] = []

## Skills that cannot be held at the same time as this one, for branch-choice
## trees. Checked in both directions, so only one side needs to declare it.
@export var conflicts_with: Array[StringName] = []

## Narrative flags that must be set. The store is [NarrativeStateService]'s,
## because a second flag store is the thing rule 23 exists to prevent.
@export var required_flags: Array[StringName] = []

@export_group("Effects")
## Applied to the character's [StatsComponent] on unlock, and removed if the
## skill is ever refunded. Sourced to this skill's id, so removal takes back
## exactly what it gave.
@export var modifiers: Array[StatModifier] = []

## Semantic states set while this skill is held, for the modules that read
## state rather than stats.
@export var grants_states: Array[StringName] = []

@export_group("Presentation")
@export_multiline var description: String = ""

## Ordering hint for a skill tree drawing itself. Not used by the runtime.
@export_range(0, 99) var tier: int = 0


func get_source_id() -> StringName:
	return id


func validate() -> ValidationResult:
	var result := super()
	if track_id == &"":
		result.add_error(
			&"skill.no_track",
			(
				"%s belongs to no track, so nothing can say whether its level "
				+ "requirement is met."
			) % get_debug_name(),
			resource_path,
			"track_id"
		)
	if requires_skills.has(id):
		result.add_error(
			&"skill.self_prerequisite",
			"%s requires itself, which nothing can ever satisfy." % get_debug_name(),
			resource_path,
			"requires_skills"
		)
	if conflicts_with.has(id):
		result.add_error(
			&"skill.self_conflict",
			"%s conflicts with itself, so it could never be unlocked." % get_debug_name(),
			resource_path,
			"conflicts_with"
		)
	for skill in requires_skills:
		if conflicts_with.has(skill):
			result.add_error(
				&"skill.contradictory_prerequisite",
				(
					"%s both requires and conflicts with '%s'. No character can "
					+ "ever hold it."
				) % [get_debug_name(), skill],
				resource_path,
				"conflicts_with"
			)
	for modifier in modifiers:
		if modifier != null and modifier.stat == &"":
			result.add_warning(
				&"skill.unnamed_modifier",
				"%s carries a modifier that names no stat." % get_debug_name(),
				resource_path,
				"modifiers"
			)
	return result
