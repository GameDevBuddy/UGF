class_name ToggleStateAction
extends InteractionAction
## Flips a semantic state on the target. The door, and everything shaped like
## a door.
##
## The one built-in action, because it is the one behaviour that recurs across
## genres: a door is open or shut, a chest is open or shut, a terminal is
## active or not, a lamp is on or off. Four scripts doing this by hand is worse
## than one resource with a state name on it (rule 23 — reuse is demonstrated,
## so the abstraction is earned).

enum Mode { TOGGLE, SET, CLEAR }


## The state flipped on the target, e.g. [code]state.open[/code].
@export var state: StringName = &""

## Force a direction rather than toggling. [code]TOGGLE[/code] flips it,
## [code]SET[/code] always turns it on, [code]CLEAR[/code] always turns it off —
## so a one-way lever and a two-way door are the same resource with different
## settings.
@export var mode: Mode = Mode.TOGGLE


func execute(context: InteractionContext) -> FrameworkResult:
	if state == &"":
		return FrameworkResult.fail(
			&"action.no_state", "This toggle action names no state."
		)
	var semantic := _find_state(context)
	if semantic == null:
		return FrameworkResult.fail(
			&"action.no_semantic_state",
			"The target has no SemanticState to toggle."
		)

	var active: bool
	match mode:
		Mode.SET:
			active = true
		Mode.CLEAR:
			active = false
		_:
			active = not semantic.has_state(state)
	semantic.set_state(state, active)
	return FrameworkResult.ok(active)


func can_execute(context: InteractionContext) -> FrameworkResult:
	if state == &"":
		return FrameworkResult.fail(
			&"action.no_state", "This toggle action names no state."
		)
	if _find_state(context) == null:
		return FrameworkResult.fail(
			&"action.no_semantic_state",
			"The target has no SemanticState to toggle."
		)
	return FrameworkResult.ok(null)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if state == &"":
		result.add_error(
			&"toggle_action.no_state",
			"A toggle action with no state name does nothing.",
			resource_path,
			"state"
		)
	return result


func _find_state(context: InteractionContext) -> SemanticState:
	if context == null or context.target == null:
		return null
	if context.interaction != null and context.interaction.semantic_state != null:
		return context.interaction.semantic_state
	for component in DefinitionBinder.collect_components(context.target):
		if component is SemanticState:
			return component as SemanticState
	return null
