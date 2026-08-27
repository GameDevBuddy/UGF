class_name ProgressionProfile
extends Resource
## The tracks and skills one kind of character can advance.
##
## A profile rather than a field on the character definition, so a project can
## share one progression scheme across a dozen character definitions and edit
## it in one place (rule 11).

## Tracks this character advances. A character with none has a
## [ProgressionComponent] that refuses every award, which is a valid state for
## an NPC that should not level.
@export var tracks: Array[ProgressionTrackDefinition] = []

## Skills reachable from those tracks. A skill naming a track absent from
## [member tracks] is unreachable, and validation says so.
@export var skills: Array[SkillDefinition] = []

## Skills every character with this profile starts holding, granted free of
## points and without checking their level requirement.
@export var starting_skills: Array[StringName] = []


func get_track(track_id: StringName) -> ProgressionTrackDefinition:
	for track in tracks:
		if track != null and track.id == track_id:
			return track
	return null


func get_skill(skill_id: StringName) -> SkillDefinition:
	for skill in skills:
		if skill != null and skill.id == skill_id:
			return skill
	return null


func get_track_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for track in tracks:
		if track != null and track.id != &"":
			ids.append(track.id)
	return ids


## Skills belonging to one track, in authored order.
func get_skills_for(track_id: StringName) -> Array[SkillDefinition]:
	var found: Array[SkillDefinition] = []
	for skill in skills:
		if skill != null and skill.track_id == track_id:
			found.append(skill)
	return found


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	var seen: Dictionary[StringName, bool] = {}
	for track in tracks:
		if track == null:
			result.add_warning(
				&"progression.null_track", "Profile has an empty track entry.", resource_path, "tracks"
			)
			continue
		if seen.has(track.id):
			result.add_error(
				&"progression.duplicate_track",
				(
					"Track '%s' appears twice. Two tracks with one id means two "
					+ "levels claiming the same name, and the second silently wins."
				) % track.id,
				resource_path,
				"tracks"
			)
		seen[track.id] = true
		result.merge(track.validate())

	var known_skills: Dictionary[StringName, bool] = {}
	for skill in skills:
		if skill == null:
			continue
		known_skills[skill.id] = true
		result.merge(skill.validate())
		if skill.track_id != &"" and not seen.has(skill.track_id):
			result.add_error(
				&"progression.orphan_skill",
				(
					"Skill '%s' belongs to track '%s', which this profile does "
					+ "not carry, so its level requirement can never be met."
				) % [skill.id, skill.track_id],
				resource_path,
				"skills"
			)

	for skill in skills:
		if skill == null:
			continue
		for prerequisite in skill.requires_skills:
			if not known_skills.has(prerequisite):
				result.add_error(
					&"progression.missing_prerequisite",
					(
						"Skill '%s' requires '%s', which this profile does not "
						+ "carry."
					) % [skill.id, prerequisite],
					resource_path,
					"skills"
				)

	for skill_id in starting_skills:
		if not known_skills.has(skill_id):
			result.add_error(
				&"progression.unknown_starting_skill",
				"Starting skill '%s' is not in this profile." % skill_id,
				resource_path,
				"starting_skills"
			)

	result.merge(_check_for_cycles(known_skills))
	return result


## Prerequisite chains that loop back on themselves.
##
## A cycle is not a slow unlock, it is an unreachable one, and it reads as a
## content bug that "the skill just does nothing" until somebody traces the
## chain by hand.
func _check_for_cycles(known: Dictionary[StringName, bool]) -> ValidationResult:
	var result := ValidationResult.new()
	var resolved: Dictionary[StringName, bool] = {}

	# Repeatedly take the skills whose prerequisites are all resolved. What is
	# left over when nothing more can be taken is exactly the cycles.
	var pending: Array[SkillDefinition] = []
	for skill in skills:
		if skill != null:
			pending.append(skill)

	while true:
		var progressed := false
		var still_pending: Array[SkillDefinition] = []
		for skill in pending:
			var satisfied := true
			for prerequisite in skill.requires_skills:
				if known.has(prerequisite) and not resolved.has(prerequisite):
					satisfied = false
					break
			if satisfied:
				resolved[skill.id] = true
				progressed = true
			else:
				still_pending.append(skill)
		pending = still_pending
		if pending.is_empty() or not progressed:
			break

	if not pending.is_empty():
		var stuck: Array[String] = []
		for skill in pending:
			stuck.append(str(skill.id))
		stuck.sort()
		result.add_error(
			&"progression.prerequisite_cycle",
			(
				"These skills require each other, directly or through others, so "
				+ "none of them can ever be unlocked: %s."
			) % ", ".join(stuck),
			resource_path,
			"skills"
		)
	return result
