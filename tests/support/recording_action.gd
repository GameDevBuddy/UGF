class_name RecordingAction
extends InteractionAction
## An action that counts its calls and can be told to refuse.
##
## Stands in for the project-specific actions the framework deliberately does
## not ship: talking to an NPC, entering a vehicle, looting a corpse. That the
## same [InteractionComponent] runs all of them is the M5 exit gate, and this
## is how the suites prove it without inventing four real subsystems.

var executed: int = 0
var checked: int = 0
var refuse_execute: bool = false
var refuse_check: bool = false
## Recorded rather than the context itself: a context holds the definition,
## the definition holds this action, and an action that holds the context
## closes a reference cycle that leaks every resource in it at exit.
var last_interactor: Node = null
var last_target: Node = null
var last_verb: StringName = &""


func execute(context: InteractionContext) -> FrameworkResult:
	_record(context)
	if refuse_execute:
		return FrameworkResult.fail(&"test.refused", "Refused on purpose.")
	executed += 1
	return FrameworkResult.ok(null)


func can_execute(context: InteractionContext) -> FrameworkResult:
	checked += 1
	_record(context)
	if refuse_check:
		return FrameworkResult.fail(&"test.unavailable", "Unavailable on purpose.")
	return FrameworkResult.ok(null)


func _record(context: InteractionContext) -> void:
	if context == null:
		return
	last_interactor = context.interactor
	last_target = context.target
	last_verb = context.get_verb()
