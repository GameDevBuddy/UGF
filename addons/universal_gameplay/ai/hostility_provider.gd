class_name HostilityProvider
extends RefCounted
## Decides whether one entity should fight another.
##
## [b]A seam, not a policy.[/b] AI needs to know whether the thing it just
## noticed is an enemy, and the answer is a different subsystem's in almost
## every genre: factions, teams, a wanted level, a script. Declaring the
## question here and letting something else answer it is what keeps
## [RoleBrain] from importing Factions (rule 9, rule 20).
##
## The default answer is "yes". That is deliberate: an arena shooter with no
## factions installed should have its enemies fight, and a framework whose AI
## does nothing until a social system is configured would be worse than one
## that is too aggressive by default (rule 31).

## Whether [param observer] should treat [param target] as an enemy.
func is_hostile(_observer: Node, _target: Node) -> bool:
	return true


## Multiplier on how threatening [param target] looks to [param observer].
## Above one makes a brain prioritise it; zero makes it uninteresting.
func get_threat_scale(_observer: Node, _target: Node) -> float:
	return 1.0


## Whether [param target] is someone [param observer] would help. Unused by
## the shipped brain and here because an ally check with no answer is the
## thing every project adds first.
func is_ally(_observer: Node, _target: Node) -> bool:
	return false
