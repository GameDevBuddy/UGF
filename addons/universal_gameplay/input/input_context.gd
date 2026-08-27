class_name InputContext
extends FrameworkDefinition
## Which semantic actions are live while this context is on top of the stack.
##
## A context is the answer to "who should be hearing input right now?"
## (Implementation Plan 24). On foot, the character controller. Driving, the
## vehicle. In a menu or a conversation, neither -- and crucially, the
## character controller does not need to know a menu exists in order to stop
## moving while one is open.
##
## It is a [FrameworkDefinition] because it is exactly that: immutable authored
## content, identified by a stable id, that configures behaviour without any
## code being written per context (rule 11).

## Actions this context passes through. An action absent from the list is not
## heard while this context is active, subject to [member blocks_lower].
@export var actions: Array[StringName] = []

## Whether actions this context does not list are blocked outright.
##
## True is the modal case -- a dialogue or a pause menu should stop the world
## beneath it. False is the additive case: a context that adds one action and
## otherwise lets the context below keep working.
@export var blocks_lower: bool = true

## Whether gameplay should treat this context as "no one is driving".
##
## The disabled and cinematic contexts set it. Controllers use it to release
## input cleanly rather than being left holding whatever was pressed on the
## frame control was taken away.
@export var suppresses_control: bool = false


func validate() -> ValidationResult:
	var result := super()
	for action in actions:
		if action == &"":
			result.add_warning(
				&"input_context.empty_action",
				"%s has an empty action entry." % get_debug_name(),
				resource_path,
				"actions"
			)
	if actions.is_empty() and not suppresses_control:
		result.add_warning(
			&"input_context.no_actions",
			(
				"%s lists no actions and does not suppress control, so it does nothing."
				% get_debug_name()
			),
			resource_path,
			"actions"
		)
	return result


func allows(action: StringName) -> bool:
	return actions.has(action)


## Convenience constructor for contexts built in code rather than authored.
static func create(
	p_id: StringName,
	p_actions: Array[StringName] = [],
	p_blocks_lower: bool = true,
	p_suppresses_control: bool = false
) -> InputContext:
	var context := InputContext.new()
	context.id = p_id
	context.display_name = str(p_id)
	context.actions = p_actions.duplicate()
	context.blocks_lower = p_blocks_lower
	context.suppresses_control = p_suppresses_control
	return context
