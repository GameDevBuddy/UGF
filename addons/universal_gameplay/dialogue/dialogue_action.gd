class_name DialogueAction
extends Resource
## Something a conversation does to the world.
##
## The mutating half of Implementation Plan 18, and the only half that is
## allowed to mutate. A [DialogueCondition] is evaluated to decide whether to
## offer a choice, so it must be free of side effects; an action runs only when
## a line is actually reached or a choice actually taken.
##
## Actions run in the order they are authored, and a failure does not stop the
## conversation: a quest flag that could not be raised because the narrative
## service is missing should leave the player talking, not frozen mid-sentence.

## Runs the action. The result is reported rather than thrown, so a caller that
## cares can log it and one that does not can ignore it.
func execute(_context: DialogueContext) -> FrameworkResult:
	return FrameworkResult.ok(null)


func describe() -> String:
	return ""


func validate() -> ValidationResult:
	return ValidationResult.new()


## Runs every action in order. Null entries are skipped rather than failing.
static func run_all(
	actions: Array[DialogueAction], context: DialogueContext
) -> void:
	for action in actions:
		if action != null:
			action.execute(context)
