class_name StateRequirement
extends InteractionRequirement
## Requires semantic states to be present or absent on the target or the
## interactor.
##
## The other half of the door: [ToggleStateAction] sets [code]state.open[/code],
## and this is what makes a second interaction ("Close") available only while
## it is set. A corpse that can be looted but not talked to, a vehicle that can
## be entered only while unlocked, a terminal that refuses while the interactor
## is [code]state.downed[/code] -- all the same resource.

enum Subject {
	## States are read from the thing being interacted with.
	TARGET,
	## States are read from whoever is interacting.
	INTERACTOR,
}

## Which entity's states are read.
@export var subject: Subject = Subject.TARGET

## Every one of these must be present.
@export var required: Array[StringName] = []

## None of these may be present.
@export var forbidden: Array[StringName] = []

## Shown when the requirement is not met. Blank falls back to a generic line.
@export var unmet_text: String = ""


func check(context: InteractionContext) -> FrameworkResult:
	if required.is_empty() and forbidden.is_empty():
		return FrameworkResult.ok(null)
	var semantic := _get_state(context)
	if semantic == null:
		# Nothing can be asserted about an entity with no state component. A
		# required state is therefore unmet; a forbidden one is trivially met.
		if required.is_empty():
			return FrameworkResult.ok(null)
		return FrameworkResult.fail(&"requirement.no_semantic_state", describe())

	if not semantic.has_all_states(required):
		return FrameworkResult.fail(&"requirement.missing_state", describe())
	if not forbidden.is_empty() and semantic.has_any_state(forbidden):
		return FrameworkResult.fail(&"requirement.forbidden_state", describe())
	return FrameworkResult.ok(null)


func describe() -> String:
	if not unmet_text.is_empty():
		return unmet_text
	if not required.is_empty():
		return "Requires %s" % String(", ").join(_as_strings(required))
	if not forbidden.is_empty():
		return "Blocked by %s" % String(", ").join(_as_strings(forbidden))
	return ""


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if required.is_empty() and forbidden.is_empty():
		result.add_warning(
			&"state_requirement.empty",
			"A state requirement that names no states is always met.",
			resource_path,
			"required"
		)
	for state in required:
		if forbidden.has(state):
			result.add_error(
				&"state_requirement.contradiction",
				(
					"State requirement both requires and forbids %s, so it can "
					+ "never be met."
				) % state,
				resource_path,
				"required"
			)
	return result


func _get_state(context: InteractionContext) -> SemanticState:
	if context == null:
		return null
	if subject == Subject.INTERACTOR:
		return context.get_interactor_state()
	return context.get_target_state()


func _as_strings(states: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	for state in states:
		out.append(String(state))
	return out
