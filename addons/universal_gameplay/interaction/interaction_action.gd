class_name InteractionAction
extends Resource
## What happens when an interaction completes. The "action strategy" of
## Ontology Rulebook 13.
##
## [b]This abstraction is deliberately thin.[/b] Rule 23 forbids abstraction
## without demonstrated reuse and rule 24 says data-driven action objects are
## optional — so this is a single virtual method with one built-in
## implementation, not a mini-language. Most interactions in most projects will
## have no action at all and will be handled by connecting to
## [signal InteractionComponent.interaction_completed], which is the plain
## signal rule 7 asks for.
##
## An action earns its place where the same behaviour is authored over and over:
## a door, a chest, a terminal and a lamp are all "toggle a state on the
## target", and writing that four times in four scripts is worse than one
## resource with a checkbox. When a project needs something else, it extends
## this rather than the framework growing a case for it.


## Runs the action. Returning a failure aborts the interaction, which is what
## lets an action refuse late — a lock that turns out to be jammed, a purchase
## the vendor cannot fund.
func execute(_context: InteractionContext) -> FrameworkResult:
	return FrameworkResult.ok(null)


## Whether this action could run right now. Checked before the interaction
## starts, so a timed interaction does not spend three seconds winding up only
## to fail at the end.
func can_execute(_context: InteractionContext) -> FrameworkResult:
	return FrameworkResult.ok(null)


func validate() -> ValidationResult:
	return ValidationResult.new()
