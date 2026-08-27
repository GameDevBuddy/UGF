class_name PerceptionSolver
extends RefCounted
## The geometry of noticing something, as static functions on no state.
##
## The same shape [MovementSolver], [DamagePipeline] and [CombatSolver] have.
## It duplicates one cone test that [CombatSolver] also has, and that is
## deliberate: rule 10 says deleting Combat must not stop AI loading, and a
## six-line dot product is a much smaller price than a module dependency.

## Whether [param point] falls inside a cone of [param angle_degrees] opening
## along [param forward] from [param origin], within [param distance].
##
## Half-angle on each side, so a 110-degree field of view is 55 degrees either
## way -- roughly a person's, which is what that number is meant to describe.
static func is_within_cone(
	origin: Vector3,
	forward: Vector3,
	point: Vector3,
	angle_degrees: float,
	distance: float
) -> bool:
	var to_point := point - origin
	if to_point.length() > distance:
		return false
	if angle_degrees >= 360.0 or to_point.is_zero_approx():
		return true
	var direction := forward.normalized()
	if direction.is_zero_approx():
		return true
	return rad_to_deg(direction.angle_to(to_point.normalized())) <= angle_degrees * 0.5


## How far a target of [param visibility] can be seen from with a base range of
## [param sight_range]. A crouching target at half visibility is spotted at
## half the distance, which is the whole of stealth in one multiplication.
static func effective_range(sight_range: float, visibility: float) -> float:
	return maxf(0.0, sight_range * visibility)


## Whether a sound of [param loudness] made at [param position] carries to
## [param origin]. Louder carries further, linearly: a gunshot at four is heard
## four times as far as a footstep at one.
static func noise_reaches(
	origin: Vector3, position: Vector3, hearing_range: float, loudness: float
) -> bool:
	if hearing_range <= 0.0 or loudness <= 0.0:
		return false
	return origin.distance_to(position) <= hearing_range * loudness


## How urgent a remembered target is, for a brain choosing between several.
##
## Threat first, then nearness, then freshness. Returns a plain number so
## sorting is a comparison rather than a policy scattered across brains.
static func urgency(
	threat: float, distance: float, time_since_seen: float
) -> float:
	var nearness := 1.0 / maxf(1.0, distance)
	var freshness := 1.0 / (1.0 + maxf(0.0, time_since_seen))
	return threat * 100.0 + nearness * 10.0 + freshness
