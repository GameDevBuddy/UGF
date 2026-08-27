class_name ProgressionComponent
extends FrameworkComponent
## The capability of getting better at things.
##
## Owns experience, level and unspent points per track, and the set of skills
## unlocked. Implementation Plan 12 asks for "XP tracks, levels, skill points,
## perk/skill unlock hooks"; this is all four, because they are one piece of
## state that has to change together. Awarding experience can cross a level
## boundary, which hands out points, which is what makes a skill affordable --
## splitting that across three components would put one transaction in three
## owners and rule 4 would be gone.
##
## [b]It grants nothing by itself.[/b] A skill's effects are [StatModifier]s
## pushed at a [StatsComponent] and semantic states pushed at a
## [SemanticState], both optional. With neither present the component still
## tracks levels correctly, which is what an NPC that levels but has no stats
## actually wants (rule 31).
##
## [b]Reputation progression is not here.[/b] The plan lists it in the same
## breath as XP, and it is already [FactionService]'s: standing with a faction
## is a relationship between two parties, not a number on one character. A
## second store for it would be the duplicate rule 23 forbids.

## Emitted when experience is added to a track, whether or not a level changed.
signal experience_gained(track: StringName, amount: float, total: float)
## Emitted once per level crossed, in order, so a listener sees 4, 5, 6 rather
## than one jump from 3 to 6.
signal level_gained(track: StringName, level: int, previous: int)
## Emitted when a track reaches its maximum.
signal track_mastered(track: StringName)
## Emitted when a skill is unlocked, by purchase or by grant.
signal skill_unlocked(skill: StringName)
## Emitted when a skill is taken back and its modifiers removed.
signal skill_refunded(skill: StringName, points_returned: int)
## Emitted when unspent points change for any reason.
signal points_changed(track: StringName, unspent: int)

## Progression configuration. Takes precedence over the definition's profile.
@export var profile_override: ProgressionProfile

## Where a skill's modifiers go. Resolved from the entity when left null.
@export var stats: StatsComponent

## Where a skill's granted states go. Resolved from the entity when left null.
@export var semantic_state: SemanticState

## Consulted for a skill's [member SkillDefinition.required_flags]. Left null,
## a skill with flag requirements can never be unlocked -- which is the honest
## answer when the narrative store a requirement names is not present.
@export var narrative: NarrativeStateService

var _profile: ProgressionProfile = null
var _experience: Dictionary[StringName, float] = {}
var _unspent: Dictionary[StringName, int] = {}
var _unlocked: Dictionary[StringName, bool] = {}
## Levels already announced, so a restore does not re-emit every level a
## character ever gained.
var _levels: Dictionary[StringName, int] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if stats == null:
		stats = _find_sibling(StatsComponent) as StatsComponent
	if semantic_state == null:
		semantic_state = _find_semantic_state()
	_seed_tracks()
	_grant_starting_skills()


func get_profile() -> ProgressionProfile:
	return _profile


# --- Reading --------------------------------------------------------------

func has_track(track_id: StringName) -> bool:
	return _profile != null and _profile.get_track(track_id) != null


func get_track_ids() -> Array[StringName]:
	return _profile.get_track_ids() if _profile != null else [] as Array[StringName]


func get_experience(track_id: StringName) -> float:
	return _experience.get(track_id, 0.0)


func get_level(track_id: StringName) -> int:
	return _levels.get(track_id, 1)


func get_unspent_points(track_id: StringName) -> int:
	return _unspent.get(track_id, 0)


## Experience still needed for the next level on this track.
func get_remaining(track_id: StringName) -> float:
	var track := _track(track_id)
	return track.get_remaining(get_experience(track_id)) if track != null else 0.0


## How far through the current level, 0.0 to 1.0, for a progress bar.
func get_fraction(track_id: StringName) -> float:
	var track := _track(track_id)
	return track.get_fraction(get_experience(track_id)) if track != null else 0.0


func is_maxed(track_id: StringName) -> bool:
	var track := _track(track_id)
	return track != null and track.is_maxed(get_experience(track_id))


func has_skill(skill_id: StringName) -> bool:
	return _unlocked.has(skill_id)


func get_unlocked_skills() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_unlocked.keys())
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return found


# --- Experience -----------------------------------------------------------

## Adds experience to a track and levels it up as far as that reaches.
##
## Refuses rather than discarding: an unknown track, a negative amount or a
## track already at its maximum all come back as a failure, so a caller
## awarding experience for a kill can tell "counted" from "wasted".
func award(track_id: StringName, amount: float) -> FrameworkResult:
	var track := _track(track_id)
	if track == null:
		return FrameworkResult.fail(
			&"progression.unknown_track",
			"This character has no track '%s'." % track_id
		)
	if amount <= 0.0:
		return FrameworkResult.fail(
			&"progression.not_an_award",
			"Experience awards must be positive; got %.2f." % amount
		)
	if track.is_maxed(get_experience(track_id)):
		return FrameworkResult.fail(
			&"progression.track_mastered",
			"Track '%s' is already at its maximum level." % track_id
		)

	var previous_level := get_level(track_id)
	var total: float = get_experience(track_id) + amount
	# Clamped to the top threshold rather than left to grow. Experience past
	# the last level is a number that only ever gets bigger, saved forever, and
	# read by a progress bar that has to special-case it.
	var ceiling := track.get_threshold(track.max_level)
	_experience[track_id] = minf(total, ceiling)
	experience_gained.emit(track_id, amount, _experience[track_id])

	var new_level := track.get_level_for(_experience[track_id])
	for level in range(previous_level + 1, new_level + 1):
		_apply_level(track, level, level - 1)

	return FrameworkResult.ok(new_level)


## Sets a track's level directly, granting the points for every level crossed.
##
## For a debug console, a save migration or a project that grants levels rather
## than experience. Going down never takes points back: they may already have
## been spent, and a refund that cannot be paid would leave a negative balance.
func set_level(track_id: StringName, level: int) -> FrameworkResult:
	var track := _track(track_id)
	if track == null:
		return FrameworkResult.fail(
			&"progression.unknown_track", "This character has no track '%s'." % track_id
		)

	var target := clampi(level, 1, track.max_level)
	var previous := get_level(track_id)
	_experience[track_id] = track.get_threshold(target)
	if target <= previous:
		_levels[track_id] = target
		return FrameworkResult.ok(target)
	for crossed in range(previous + 1, target + 1):
		_apply_level(track, crossed, crossed - 1)
	return FrameworkResult.ok(target)


# --- Skills ---------------------------------------------------------------

## Everything standing between this character and [param skill_id].
##
## Checked in full before anything is spent (rule 17), and reported as a
## specific code so a UI can say "two more levels" rather than "unavailable".
func can_unlock(skill_id: StringName) -> FrameworkResult:
	if _profile == null:
		return FrameworkResult.fail(
			&"progression.no_profile", "This character has no progression profile."
		)
	var skill := _profile.get_skill(skill_id)
	if skill == null:
		return FrameworkResult.fail(
			&"progression.unknown_skill", "No skill '%s' on this character." % skill_id
		)
	if _unlocked.has(skill_id):
		return FrameworkResult.fail(
			&"progression.already_unlocked", "'%s' is already unlocked." % skill_id
		)

	var level := get_level(skill.track_id)
	if level < skill.required_level:
		return FrameworkResult.fail(
			&"progression.level_too_low",
			(
				"'%s' needs %s at level %d; it is at %d."
				% [skill_id, skill.track_id, skill.required_level, level]
			)
		)
	if get_unspent_points(skill.track_id) < skill.cost:
		return FrameworkResult.fail(
			&"progression.not_enough_points",
			(
				"'%s' costs %d point(s); %d unspent."
				% [skill_id, skill.cost, get_unspent_points(skill.track_id)]
			)
		)

	for prerequisite in skill.requires_skills:
		if not _unlocked.has(prerequisite):
			return FrameworkResult.fail(
				&"progression.missing_prerequisite",
				"'%s' needs '%s' first." % [skill_id, prerequisite]
			)

	# Conflicts are checked in both directions, so only one side of a branch
	# has to declare the pair and a designer cannot half-author the exclusion.
	for conflict in skill.conflicts_with:
		if _unlocked.has(conflict):
			return FrameworkResult.fail(
				&"progression.conflicting_skill",
				"'%s' cannot be held alongside '%s'." % [skill_id, conflict]
			)
	for held in _unlocked:
		var other := _profile.get_skill(held)
		if other != null and other.conflicts_with.has(skill_id):
			return FrameworkResult.fail(
				&"progression.conflicting_skill",
				"'%s' cannot be held alongside '%s'." % [skill_id, held]
			)

	for flag in skill.required_flags:
		if narrative == null or not narrative.get_flag(flag):
			return FrameworkResult.fail(
				&"progression.flag_not_set",
				"'%s' needs the flag '%s'." % [skill_id, flag]
			)

	return FrameworkResult.ok(skill)


## Spends the points and applies the skill's effects.
func unlock(skill_id: StringName) -> FrameworkResult:
	var check := can_unlock(skill_id)
	if check.is_err():
		return check

	var skill: SkillDefinition = check.payload
	_unspent[skill.track_id] = get_unspent_points(skill.track_id) - skill.cost
	_apply_skill(skill)
	points_changed.emit(skill.track_id, _unspent[skill.track_id])
	return FrameworkResult.ok(skill)


## Grants a skill without cost or requirements, for a starting perk, a story
## reward or a debug console.
func grant(skill_id: StringName) -> FrameworkResult:
	if _profile == null:
		return FrameworkResult.fail(
			&"progression.no_profile", "This character has no progression profile."
		)
	var skill := _profile.get_skill(skill_id)
	if skill == null:
		return FrameworkResult.fail(
			&"progression.unknown_skill", "No skill '%s' on this character." % skill_id
		)
	if _unlocked.has(skill_id):
		return FrameworkResult.fail(
			&"progression.already_unlocked", "'%s' is already unlocked." % skill_id
		)
	_apply_skill(skill)
	return FrameworkResult.ok(skill)


## Takes a skill back, removes its modifiers and returns its points.
##
## Removal is by source, exactly as [StatsComponent] requires: the skill's own
## id is the source of every modifier it applied, so a refund takes back what
## this skill gave and nothing another skill happens to share.
func refund(skill_id: StringName) -> FrameworkResult:
	if not _unlocked.has(skill_id):
		return FrameworkResult.fail(
			&"progression.not_unlocked", "'%s' is not unlocked." % skill_id
		)
	var skill := _profile.get_skill(skill_id) if _profile != null else null
	if skill == null:
		return FrameworkResult.fail(
			&"progression.unknown_skill", "No skill '%s' on this character." % skill_id
		)

	# Anything that depends on this one goes first, or a character keeps a
	# skill whose prerequisite it no longer holds.
	for held in get_unlocked_skills():
		if held == skill_id:
			continue
		var other := _profile.get_skill(held)
		if other != null and other.requires_skills.has(skill_id):
			return FrameworkResult.fail(
				&"progression.has_dependents",
				"'%s' cannot be refunded while '%s' depends on it." % [skill_id, held]
			)

	_unlocked.erase(skill_id)
	if stats != null:
		stats.remove_modifiers_from(skill.get_source_id())
	if semantic_state != null:
		for state in skill.grants_states:
			semantic_state.remove_state(state)
	_unspent[skill.track_id] = get_unspent_points(skill.track_id) + skill.cost

	skill_refunded.emit(skill_id, skill.cost)
	points_changed.emit(skill.track_id, _unspent[skill.track_id])
	return FrameworkResult.ok(skill)


## Skills that could be unlocked right now, for a skill tree drawing itself.
func get_available_skills() -> Array[StringName]:
	var found: Array[StringName] = []
	if _profile == null:
		return found
	for skill in _profile.skills:
		if skill != null and can_unlock(skill.id).is_ok():
			found.append(skill.id)
	return found


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves experience, points and which skills are held -- never the modifiers
## those skills granted.
##
## Modifiers are reapplied from the definitions on restore. Saving them too
## would double every bonus on load, the same trap [EquipmentComponent] and
## [StatusEffectComponent] both avoid (rule 4).
func capture_state() -> Dictionary:
	var experience: Dictionary = {}
	for track_id in _experience:
		experience[String(track_id)] = _experience[track_id]
	var points: Dictionary = {}
	for track_id in _unspent:
		points[String(track_id)] = _unspent[track_id]
	var skills: Array[String] = []
	for skill_id in get_unlocked_skills():
		skills.append(String(skill_id))
	return {"experience": experience, "points": points, "skills": skills}


func restore_state(data: Dictionary) -> void:
	for skill_id in get_unlocked_skills():
		var held := _profile.get_skill(skill_id) if _profile != null else null
		if held != null and stats != null:
			stats.remove_modifiers_from(held.get_source_id())
		if held != null and semantic_state != null:
			for state in held.grants_states:
				semantic_state.remove_state(state)
	_unlocked.clear()
	_experience.clear()
	_unspent.clear()
	_levels.clear()

	var experience: Dictionary = data.get("experience", {})
	for key in experience:
		_experience[StringName(key)] = float(experience[key])
	var points: Dictionary = data.get("points", {})
	for key in points:
		_unspent[StringName(key)] = int(points[key])

	# Levels are derived from experience rather than saved. Two numbers that
	# must agree are one number that can disagree, and the curve is the
	# authority on which level a given amount of experience buys.
	if _profile != null:
		for track in _profile.tracks:
			if track != null:
				_levels[track.id] = track.get_level_for(get_experience(track.id))

	var skills: Array = data.get("skills", [])
	for entry in skills:
		var skill := _profile.get_skill(StringName(entry)) if _profile != null else null
		if skill != null:
			_apply_skill(skill)


# --- Internals ------------------------------------------------------------

func _track(track_id: StringName) -> ProgressionTrackDefinition:
	return _profile.get_track(track_id) if _profile != null else null


## Records a level, hands out its rewards and announces it.
func _apply_level(track: ProgressionTrackDefinition, level: int, previous: int) -> void:
	_levels[track.id] = level
	if track.points_per_level > 0:
		_unspent[track.id] = get_unspent_points(track.id) + track.points_per_level
		points_changed.emit(track.id, _unspent[track.id])
	if track.stat_per_level_id != &"" and track.stat_per_level != 0.0 and stats != null:
		stats.set_base(
			track.stat_per_level_id,
			stats.get_base(track.stat_per_level_id) + track.stat_per_level
		)
	level_gained.emit(track.id, level, previous)
	if level >= track.max_level:
		if track.mastered_state != &"" and semantic_state != null:
			semantic_state.add_state(track.mastered_state)
		track_mastered.emit(track.id)


func _apply_skill(skill: SkillDefinition) -> void:
	_unlocked[skill.id] = true
	if stats != null:
		for modifier in skill.modifiers:
			if modifier == null:
				continue
			# Sourced to the skill rather than to whatever the .tres happens to
			# say, so a refund can take back exactly this skill's contribution
			# even if two skills share an authored modifier resource.
			var copy: StatModifier = modifier.duplicate()
			copy.source = skill.get_source_id()
			stats.add_modifier(copy)
	if semantic_state != null:
		for state in skill.grants_states:
			semantic_state.add_state(state)
	skill_unlocked.emit(skill.id)


func _seed_tracks() -> void:
	if _profile == null:
		return
	for track in _profile.tracks:
		if track == null:
			continue
		if not _experience.has(track.id):
			_experience[track.id] = track.get_threshold(track.starting_level)
		_levels[track.id] = track.get_level_for(_experience[track.id])
		if not _unspent.has(track.id):
			# Points for the levels a character starts above the first. A
			# character starting at level 5 has earned four levels' worth.
			_unspent[track.id] = track.points_per_level * (track.starting_level - 1)


func _grant_starting_skills() -> void:
	if _profile == null:
		return
	for skill_id in _profile.starting_skills:
		grant(skill_id)


func _resolve_profile() -> ProgressionProfile:
	if profile_override != null:
		return profile_override
	var context := get_context()
	var definition := context.definition if context != null else null
	if definition != null and "progression" in definition:
		return definition.get("progression") as ProgressionProfile
	return null


func _find_sibling(type: Variant) -> FrameworkComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child as FrameworkComponent
	return null


func _find_semantic_state() -> SemanticState:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child is SemanticState:
			return child as SemanticState
	return null
