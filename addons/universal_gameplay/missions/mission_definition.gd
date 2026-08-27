class_name MissionDefinition
extends FrameworkDefinition
## A whole mission, as content.
##
## Objectives, how they are sequenced, what unlocks it and what it pays. Adding
## a mission to a game creates a [code].tres[/code] and no GDScript (rule 15).

## Player-facing summary shown in a journal.
@export_multiline var description: String = ""

## What has to be done. Order matters when [member sequential] is on.
@export var objectives: Array[ObjectiveDefinition] = []

@export_group("Sequencing")
## Activate objectives one at a time in order, rather than all at once. A
## chain of "go here, then talk to them, then come back" wants this on; a
## board of independent bounties wants it off.
@export var sequential: bool = false

## Complete the mission when every non-optional objective is done. Off leaves
## completion to an explicit call, which is what a mission a cutscene ends
## wants.
@export var completes_automatically: bool = true

@export_group("Availability")
## Narrative flags that must all be raised before this can start.
@export var required_flags: Array[StringName] = []

## Narrative flags that block it while any is raised.
@export var forbidden_flags: Array[StringName] = []

## Missions that must have been completed first. Ids rather than references,
## so a chain does not load every mission in it at once (rule 32).
@export var required_missions: Array[StringName] = []

## Start as soon as its prerequisites are met, without anyone offering it.
@export var auto_start: bool = false

## Whether it can be done more than once. Off is the usual case.
@export var repeatable: bool = false

@export_group("Payment")
@export var rewards: Array[MissionReward] = []


func get_description() -> String:
	if not description.is_empty():
		return description
	return display_name if not display_name.is_empty() else String(id)


func get_objective(objective_id: StringName) -> ObjectiveDefinition:
	for objective in objectives:
		if objective != null and objective.id == objective_id:
			return objective
	return null


## Objectives that must be finished for the mission to complete.
func get_required_objectives() -> Array[ObjectiveDefinition]:
	var required: Array[ObjectiveDefinition] = []
	for objective in objectives:
		if objective != null and not objective.optional:
			required.append(objective)
	return required


## Whether the story is in a state that allows this to start.
##
## Takes the service rather than a context object, because that is the whole
## of what it needs and a mission that could not be offered without one is a
## mission no project can gate (rule 31).
func is_available(narrative: NarrativeStateService, completed: Array = []) -> bool:
	for mission_id in required_missions:
		if not completed.has(mission_id):
			return false
	if narrative == null:
		return required_flags.is_empty()
	for flag in required_flags:
		if not narrative.get_flag(flag):
			return false
	for flag in forbidden_flags:
		if narrative.get_flag(flag):
			return false
	return true


func validate() -> ValidationResult:
	var result := super()
	if objectives.is_empty():
		result.add_error(
			&"mission.no_objectives",
			"%s asks for nothing, so it would complete the moment it started." % get_debug_name(),
			resource_path,
			"objectives"
		)

	var seen: Dictionary[StringName, bool] = {}
	var required := 0
	for objective in objectives:
		if objective == null:
			result.add_warning(
				&"mission.empty_objective_slot",
				"%s has an empty objective slot." % get_debug_name(),
				resource_path,
				"objectives"
			)
			continue
		if objective.id != &"" and seen.has(objective.id):
			result.add_error(
				&"mission.duplicate_objective_id",
				(
					"%s has two objectives with id '%s', so progress on one is "
					+ "indistinguishable from the other."
				) % [get_debug_name(), objective.id],
				resource_path,
				"objectives"
			)
		seen[objective.id] = true
		if not objective.optional:
			required += 1
		result.merge(objective.validate())

	if required == 0 and not objectives.is_empty():
		result.add_warning(
			&"mission.all_optional",
			(
				"Every objective in %s is optional, so it completes "
				+ "immediately."
			) % get_debug_name(),
			resource_path,
			"objectives"
		)
	for flag in required_flags:
		if forbidden_flags.has(flag):
			result.add_error(
				&"mission.contradictory_flags",
				(
					"%s both requires and forbids '%s', so it can never be "
					+ "offered."
				) % [get_debug_name(), flag],
				resource_path,
				"required_flags"
			)
	if required_missions.has(id):
		result.add_error(
			&"mission.requires_itself",
			"%s requires itself to have been completed." % get_debug_name(),
			resource_path,
			"required_missions"
		)
	for reward in rewards:
		if reward != null:
			result.merge(reward.validate())
	return result

## Prerequisite missions, which must not form a loop.
##
## A chain of missions each requiring the next is a chain no player can start.
func get_dependency_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for mission_id in required_missions:
		if mission_id != &"":
			ids.append(mission_id)
	return ids


## Item ids this mission pays out. A reward pointing at a renamed item is a
## mission that completes and hands over nothing.
func get_referenced_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for reward in rewards:
		if reward == null:
			continue
		var item_id: Variant = reward.get("item_id")
		if item_id is StringName and item_id != &"":
			ids.append(item_id)
	return ids
