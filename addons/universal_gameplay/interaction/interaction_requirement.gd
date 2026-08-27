class_name InteractionRequirement
extends Resource
## A condition an interaction must satisfy before it runs.
##
## The "requirements" half of Implementation Plan 34. A locked door, a terminal
## that needs a keycard, a lever that only works while the power is on: all of
## them are the same interaction with a different requirement resource attached
## (rule 11 -- content is data, so a locked door is authored, not scripted).
##
## [b]A requirement answers, it does not act.[/b] [method check] must be free of
## side effects, because it runs every frame a prompt is on screen and again
## when the interaction starts. The one side effect a requirement may have is
## [method commit], which runs only after the interaction has actually
## succeeded -- that is what lets a key be consumed without a failed action
## eating it (rule 17).

## Whether this requirement is met. Called often; keep it cheap and pure.
func check(_context: InteractionContext) -> FrameworkResult:
	return FrameworkResult.ok(null)


## Applied once the interaction has succeeded. The consuming half of a
## consumable requirement, and nothing else.
##
## A failure here is reported but does not undo the interaction: by the time
## this runs the door is already open. Requirements that can fail to commit
## should refuse in [method check] instead.
func commit(_context: InteractionContext) -> FrameworkResult:
	return FrameworkResult.ok(null)


## Short player-facing reason this is not met, for the prompt: "Needs a
## keycard". Empty means the prompt simply does not appear.
func describe() -> String:
	return ""


func validate() -> ValidationResult:
	return ValidationResult.new()
