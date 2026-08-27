class_name HitProvider
extends RefCounted
## Where combat asks the world what it just hit.
##
## The same seam [InputSource] is for input, and for the same reason: a
## delivery strategy that calls [PhysicsDirectSpaceState3D] directly cannot be
## tested without a live 3D world, colliders and a physics frame, and rule 33
## wants combat's decisions testable without any of that.
##
## Two queries is the whole interface. Everything the shipped deliveries need
## -- a rifle round, a shotgun's pellets, a sword's arc, a blast radius -- is
## one of these two, and a strategy that needs a third can take a provider
## subclass of its own.

## The first thing along a ray, or null when it hit nothing.
func cast_ray(
	_origin: Vector3,
	_direction: Vector3,
	_distance: float,
	_exclude: Array[Node] = []
) -> CombatHit:
	return null


## Everything inside a sphere. Order is not meaningful; callers that care about
## nearest-first sort by [member CombatHit.distance].
func overlap_sphere(
	_origin: Vector3, _radius: float, _exclude: Array[Node] = []
) -> Array[CombatHit]:
	var empty: Array[CombatHit] = []
	return empty
