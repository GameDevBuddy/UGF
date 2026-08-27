class_name DialogueCondition
extends Resource
## A question a conversation asks before showing something.
##
## [b]Conditions query; they never mutate.[/b] That is Implementation Plan 18
## stated as a rule, and it is load-bearing: a condition is evaluated to decide
## whether to [i]offer[/i] a choice, so a condition with a side effect fires for
## options the player never picked. Anything that changes the world is a
## [DialogueAction].

## Whether this holds. Called often; keep it cheap and pure.
func evaluate(_context: DialogueContext) -> bool:
	return true


## Short author-facing description, for debug overlays and validation output.
func describe() -> String:
	return ""


func validate() -> ValidationResult:
	return ValidationResult.new()


## True when every condition in [param conditions] holds. Null entries are
## skipped rather than failing, so an empty slot in an authored array does not
## silently hide a line.
static func all_hold(
	conditions: Array[DialogueCondition], context: DialogueContext
) -> bool:
	for condition in conditions:
		if condition != null and not condition.evaluate(context):
			return false
	return true
