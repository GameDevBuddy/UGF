class_name EndNode
extends DialogueNode
## The conversation is over.
##
## Distinct from a node with a blank [member DialogueNode.next], which also
## ends it: reaching an End is a statement the author made, and it can carry
## the outcome. A conversation that ends because someone forgot to wire the
## next node looks identical at runtime and is a bug.

## Semantic outcome, published with the completion event so a mission can turn
## on how a conversation ended without reading its internals:
## [code]outcome.accepted[/code], [code]outcome.refused[/code].
@export var outcome: StringName = &""


func is_terminal() -> bool:
	return true


func validate() -> ValidationResult:
	var result := super()
	if next != &"":
		result.add_warning(
			&"end.has_next",
			(
				"End node '%s' names a successor, which will never be reached. "
				+ "Use a plain node if the conversation should continue."
			) % id,
			resource_path,
			"next"
		)
	return result
