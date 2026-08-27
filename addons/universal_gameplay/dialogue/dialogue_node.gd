class_name DialogueNode
extends Resource
## One step in a conversation.
##
## [b]Four node types, not six.[/b] Implementation Plan 18 lists Line, Choice,
## Branch, Action, Jump and End. Action and Jump are fields on this base rather
## than types of their own, because that is all they are: an Action node is a
## node with actions and no text, and a Jump node is a node whose only content
## is where it goes -- both already expressible as [member enter_actions] and
## [member next] on any node. Two classes whose entire body would be inherited
## is the abstraction rule 23 asks us not to add, and every node needing to
## run actions and name a successor anyway means the fields have to exist here
## regardless.
##
## The consequence worth stating: a project porting a graph from a tool that
## has explicit Action and Jump nodes maps both onto a bare [DialogueNode].

## Stable identity within its conversation. Every node needs one: [member next]
## and every jump target names a node by id rather than by index, so inserting
## a line in the middle of a conversation does not renumber the rest (rule 32).
@export var id: StringName = &""

## Everything that must hold for this node to be reachable. A node whose
## conditions fail is skipped, and the runtime moves on to its successor.
@export var conditions: Array[DialogueCondition] = []

## Run when this node is entered, before anything is shown.
@export var enter_actions: Array[DialogueAction] = []

## Where the conversation goes next. Blank ends it.
@export var next: StringName = &""


## Whether this node can be entered right now.
func is_available(context: DialogueContext) -> bool:
	return DialogueCondition.all_hold(conditions, context)


## Where to go after this node. Overridden by nodes that decide dynamically.
func get_next(_context: DialogueContext) -> StringName:
	return next


## Whether reaching this node ends the conversation.
func is_terminal() -> bool:
	return false


## Whether the runtime should stop and wait here for the player. A line waits
## to be read; a bare action node does not.
func waits_for_input() -> bool:
	return false


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if id == &"":
		result.add_error(
			&"dialogue_node.no_id",
			"A dialogue node with no id cannot be jumped to or referenced.",
			resource_path,
			"id"
		)
	for condition in conditions:
		if condition != null:
			result.merge(condition.validate())
	for action in enter_actions:
		if action != null:
			result.merge(action.validate())
	return result


## Node ids this one can lead to, for the reachability check a definition runs.
func get_outgoing() -> Array[StringName]:
	var out: Array[StringName] = []
	if next != &"":
		out.append(next)
	return out
