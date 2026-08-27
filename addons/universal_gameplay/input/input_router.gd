class_name InputRouter
extends FrameworkService
## Decides which context is allowed to hear input, and answers queries about
## semantic actions.
##
## Gameplay code never asks a keyboard anything. It asks this router whether
## [code]jump[/code] is pressed, and the router answers according to the
## context stack: on foot, yes; with a menu open, no. The character controller
## therefore contains no knowledge of menus, vehicles or conversations, and a
## new modal state is a context push rather than a flag threaded through every
## controller (Implementation Plan 24).
##
## [b]The stack, not a single value.[/b] Contexts nest in practice -- a
## conversation started from inside a vehicle has to return to driving, not to
## walking. A stack restores the previous state for free; a single current
## context makes every caller responsible for remembering what to put back,
## and one that forgets leaves the player unable to move.
##
## The router is a service rather than an autoload (rule 8). Split-screen wants
## one router per player, and a global cannot be two things at once.

## Emitted when the active context changes, including when the stack empties.
signal context_changed(active_id: StringName)
## Emitted when control is suppressed or restored, so a controller can drop
## whatever it was holding rather than being frozen mid-stride.
signal control_suppressed(suppressed: bool)

var _stack: Array[InputContext] = []
var _source: InputSource = null
var _was_suppressed: bool = false


func _init(source: InputSource = null) -> void:
	_source = source if source != null else EngineInputSource.new()


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_INPUT


# --- Source ---------------------------------------------------------------

## Replaces where raw action state is read from. This is the seam a replay
## system, a recorded-input test or a network client's intent stream plugs in
## at (Implementation Plan 27).
func set_source(source: InputSource) -> void:
	_source = source if source != null else EngineInputSource.new()


func get_source() -> InputSource:
	return _source


# --- Context stack --------------------------------------------------------

## Pushes a context on top of the stack, making it active.
func push_context(context: InputContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(
			&"input.null_context", "Cannot push a null input context."
		)
	_stack.append(context)
	_notify_change()
	return FrameworkResult.ok(context)


## Removes the top context, restoring whatever was beneath it.
func pop_context() -> FrameworkResult:
	if _stack.is_empty():
		return FrameworkResult.fail(
			&"input.empty_stack", "There is no input context to pop."
		)
	var context: InputContext = _stack.pop_back()
	_notify_change()
	return FrameworkResult.ok(context)


## Removes the topmost context with this id, wherever it sits in the stack.
##
## Needed because contexts do not always unwind in order: a menu opened during
## a conversation can be closed by a global "close everything" without the
## conversation having ended. Popping blindly there would remove the wrong one.
func remove_context(id: StringName) -> FrameworkResult:
	for index in range(_stack.size() - 1, -1, -1):
		if _stack[index].id == id:
			return _remove_at(index)
	return FrameworkResult.fail(
		&"input.context_not_active", "Input context '%s' is not on the stack." % id
	)


## Removes one specific context object, matched by identity rather than by id.
##
## Two things can legitimately push contexts with the same id -- two characters
## both on foot, two players in split-screen. Removing by id would take the
## topmost, which is whichever of them pushed last rather than the one asking
## to be removed. Anything holding the context it pushed should use this.
func remove_context_instance(context: InputContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(
			&"input.null_context", "Cannot remove a null input context."
		)
	for index in range(_stack.size() - 1, -1, -1):
		if _stack[index] == context:
			return _remove_at(index)
	return FrameworkResult.fail(
		&"input.context_not_active",
		"Input context '%s' is not on the stack." % context.id
	)


func _remove_at(index: int) -> FrameworkResult:
	var context: InputContext = _stack[index]
	_stack.remove_at(index)
	_notify_change()
	return FrameworkResult.ok(context)


## Replaces the entire stack with one context. Use for hard transitions, such
## as entering a cutscene, where nothing beneath should be restored.
func set_context(context: InputContext) -> FrameworkResult:
	_stack.clear()
	if context == null:
		_notify_change()
		return FrameworkResult.ok(null)
	return push_context(context)


func clear_contexts() -> void:
	_stack.clear()
	_notify_change()


func get_active_context() -> InputContext:
	return _stack.back() if not _stack.is_empty() else null


func get_active_context_id() -> StringName:
	var active := get_active_context()
	return active.id if active != null else &""


func has_context(id: StringName) -> bool:
	for context in _stack:
		if context.id == id:
			return true
	return false


func get_context_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for context in _stack:
		ids.append(context.id)
	return ids


func get_depth() -> int:
	return _stack.size()


# --- Queries --------------------------------------------------------------

## Whether [param action] is audible under the current stack.
##
## Walks from the top down: the first context that either allows the action or
## blocks everything else decides. A context with [member
## InputContext.blocks_lower] false and no claim on the action lets the
## question fall through to the context beneath it.
func is_action_allowed(action: StringName) -> bool:
	for index in range(_stack.size() - 1, -1, -1):
		var context: InputContext = _stack[index]
		if context.allows(action):
			return true
		if context.blocks_lower:
			return false
	# An empty stack hears nothing. Input is opt-in: a project that has not
	# pushed a context yet has not said who should be listening, and guessing
	# "everything" would make the router's whole job optional.
	return false


## Whether the active context suppresses gameplay control entirely.
func is_control_suppressed() -> bool:
	var active := get_active_context()
	return active != null and active.suppresses_control


func is_pressed(action: StringName) -> bool:
	return is_action_allowed(action) and _source.is_pressed(action)


func was_just_pressed(action: StringName) -> bool:
	return is_action_allowed(action) and _source.was_just_pressed(action)


func was_just_released(action: StringName) -> bool:
	return is_action_allowed(action) and _source.was_just_released(action)


func get_strength(action: StringName) -> float:
	return _source.get_strength(action) if is_action_allowed(action) else 0.0


func get_axis(negative: StringName, positive: StringName) -> float:
	return get_strength(positive) - get_strength(negative)


## Two-axis vector, clamped to unit length. Blocked actions contribute zero,
## so a half-blocked context yields a partial vector rather than nothing --
## which is what a context that permits strafing but not advancing wants.
func get_vector(
	negative_x: StringName,
	positive_x: StringName,
	negative_y: StringName,
	positive_y: StringName
) -> Vector2:
	var vector := Vector2(
		get_axis(negative_x, positive_x), get_axis(negative_y, positive_y)
	)
	return vector.limit_length(1.0)


## The standard movement vector: x is strafe, y is forward/back.
##
## Forward is negative y, matching Godot's screen-space convention, so the
## value drops straight into a basis without a sign flip at every call site.
func get_move_vector() -> Vector2:
	return get_vector(
		GameplayNames.ACTION_MOVE_LEFT,
		GameplayNames.ACTION_MOVE_RIGHT,
		GameplayNames.ACTION_MOVE_FORWARD,
		GameplayNames.ACTION_MOVE_BACK
	)


# --- Validation -----------------------------------------------------------

## Reports actions the stacked contexts reference that the source cannot
## supply -- usually an InputMap missing a binding.
##
## Content validation is a feature (rule 27), and an unbound action is exactly
## the failure that is invisible at runtime: nothing errors, the key simply
## never works.
func validate_bindings() -> ValidationResult:
	var result := ValidationResult.new()
	var seen: Dictionary[StringName, bool] = {}
	for context in _stack:
		result.merge(context.validate())
		for action in context.actions:
			if action == &"" or seen.has(action):
				continue
			seen[action] = true
			if not _source.has_action(action):
				result.add_warning(
					&"input.unbound_action",
					(
						"Action '%s' is used by context '%s' but is not bound."
						% [action, context.id]
					)
				)
	return result


func _notify_change() -> void:
	context_changed.emit(get_active_context_id())
	var suppressed := is_control_suppressed()
	if suppressed != _was_suppressed:
		_was_suppressed = suppressed
		control_suppressed.emit(suppressed)
