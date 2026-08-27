class_name BranchNode
extends DialogueNode
## The conversation decides for itself which way to go.
##
## A choice the player never sees: has the quest been done, is the guard
## hostile, is it night. The branches are tried in order and the first whose
## conditions hold wins, so authoring order is precedence -- which is what a
## designer expects and what an unordered dictionary could not give them.

## Where to go when a set of conditions holds. Kept as parallel arrays rather
## than a Branch resource, because a two-field object with no behaviour is
## ceremony rather than structure (rule 23).
@export var branch_conditions: Array[DialogueCondition] = []

## Node id for the branch at the same index. Blank ends the conversation.
@export var branch_targets: Array[StringName] = []

## Where to go when no branch holds. Blank falls back to [member next].
@export var fallback: StringName = &""


func get_next(context: DialogueContext) -> StringName:
	var count := mini(branch_conditions.size(), branch_targets.size())
	for index in count:
		var condition := branch_conditions[index]
		if condition == null or condition.evaluate(context):
			return branch_targets[index]
	if fallback != &"":
		return fallback
	return next


func validate() -> ValidationResult:
	var result := super()
	if branch_conditions.size() != branch_targets.size():
		result.add_error(
			&"branch.mismatched_arrays",
			(
				"Branch node '%s' has %d conditions and %d targets; the extras "
				+ "on one side can never be reached."
			) % [id, branch_conditions.size(), branch_targets.size()],
			resource_path,
			"branch_targets"
		)
	if branch_conditions.is_empty():
		result.add_warning(
			&"branch.no_branches",
			"Branch node '%s' has no branches, so it always takes its fallback." % id,
			resource_path,
			"branch_conditions"
		)
	if fallback == &"" and next == &"":
		result.add_warning(
			&"branch.no_fallback",
			(
				"Branch node '%s' has no fallback, so a state where no branch "
				+ "holds ends the conversation."
			) % id,
			resource_path,
			"fallback"
		)
	for condition in branch_conditions:
		if condition != null:
			result.merge(condition.validate())
	return result


func get_outgoing() -> Array[StringName]:
	var out := super()
	for target in branch_targets:
		if target != &"":
			out.append(target)
	if fallback != &"":
		out.append(fallback)
	return out
