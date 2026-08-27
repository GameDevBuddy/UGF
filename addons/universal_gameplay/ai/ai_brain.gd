class_name AIBrain
extends Resource
## What an NPC decides to do next.
##
## A [Resource] rather than a node, and a pure function of its [AIContext]
## rather than something that reads the tree. That is what makes a brain
## shareable across every guard in the game, testable without a scene, and
## replaceable by a project's own behaviour tree, GOAP planner or state machine
## without the framework having opinions about which (rule 20, rule 33).
##
## [b]It issues commands, it does not implement them.[/b] A brain calls
## [method MovementComponent.set_move_direction] and
## [method CombatComponent.attack] -- the same public methods the player's
## controller calls, with no privileged path and nothing an AI has to work
## around (rule 14). If a brain needs something the player's controller cannot
## do, that is a missing capability, not a reason for an AI back door.

## [b]No signals live here.[/b] A brain is a shared resource: one
## [code]guard_brain.tres[/code] backs forty guards, so a signal on it would
## deliver every guard's decision to every listener of every other guard.
## [AIControllerComponent] emits per-NPC state changes instead.


## Decides and commands. Called once per controller tick.
func think(_context: AIContext) -> void:
	pass


## What this brain is doing right now, as a semantic name for debug output and
## for a project's own presentation. Blank means it does not say.
func get_state() -> StringName:
	return &""


## Called once when the controller adopts this brain, so a stateful brain can
## reset. Brains are shared resources, so anything mutable a brain keeps is a
## bug waiting for the second NPC that uses it (rule 2, rule 16) -- per-NPC
## state belongs in [member AIControllerComponent.blackboard].
func reset(_context: AIContext) -> void:
	pass


func validate() -> ValidationResult:
	return ValidationResult.new()
