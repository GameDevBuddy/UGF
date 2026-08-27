class_name PerceptionProvider
extends RefCounted
## Where perception asks the world what is out there and what is in the way.
##
## The same seam [InputSource] is for input and [HitProvider] is for combat,
## and for the same reason: an NPC whose senses call into the physics server
## cannot be tested without a navmesh, colliders and a physics frame. A guard
## noticing an intruder is a decision, and rule 33 wants decisions testable.
##
## Deliberately separate from [HitProvider] rather than reused. They answer
## different questions -- "what would a bullet stop on" and "what can be seen
## from here" use different layers in almost every project -- and sharing one
## would make AI fail to load in a build with no Combat module (rule 10).

## Everything that could be perceived within [param radius] of [param origin].
## Order is not meaningful.
func find_candidates(_origin: Vector3, _radius: float) -> Array[Node]:
	var empty: Array[Node] = []
	return empty


## Whether the straight line between two points is unobstructed.
##
## True by default: a provider with no world should report an unoccluded one
## rather than blinding every NPC that uses it.
func has_line_of_sight(_from: Vector3, _to: Vector3, _ignore: Array[Node] = []) -> bool:
	return true
