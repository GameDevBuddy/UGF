class_name FakeHitProvider
extends HitProvider
## A world made of spheres, so combat can be tested without one.
##
## This fixture is the payoff for deliveries querying a [HitProvider] rather
## than the physics server: a shotgun's pellet spread, a sword's arc and a
## bullet stopped by a wall are all assertable here in microseconds, with no
## collision shapes, no physics frame and no 3D scene (rule 33).

## Things that can be hit. Positions are read from their transforms.
var targets: Array[Node3D] = []

## Radius every target is treated as having.
var target_radius: float = 0.5

## Distance along any ray at which an opaque wall stands. Negative for none.
var wall_distance: float = -1.0

## Stands in for the wall, so a hit on it reports a target that takes no
## damage rather than a null.
var wall: Node = null

## Every direction [method cast_ray] was asked about, in order. What a spread
## test reads.
var ray_directions: Array[Vector3] = []
var ray_calls: int = 0
var overlap_calls: int = 0


func cast_ray(
	origin: Vector3,
	direction: Vector3,
	distance: float,
	exclude: Array[Node] = []
) -> CombatHit:
	ray_calls += 1
	var forward := direction.normalized()
	ray_directions.append(forward)

	var nearest: Node3D = null
	var nearest_distance := INF
	for target in targets:
		if target == null or exclude.has(target):
			continue
		var to_target := target.global_position - origin
		var along := to_target.dot(forward)
		if along < 0.0 or along > distance:
			continue
		var perpendicular := (to_target - forward * along).length()
		if perpendicular > target_radius or along >= nearest_distance:
			continue
		nearest = target
		nearest_distance = along

	if wall_distance >= 0.0 and wall_distance <= distance and wall_distance < nearest_distance:
		return CombatHit.create(
			wall, origin + forward * wall_distance, -forward, wall_distance
		)
	if nearest == null:
		return null
	return CombatHit.create(
		nearest, origin + forward * nearest_distance, -forward, nearest_distance
	)


func overlap_sphere(
	origin: Vector3, radius: float, exclude: Array[Node] = []
) -> Array[CombatHit]:
	overlap_calls += 1
	var hits: Array[CombatHit] = []
	for target in targets:
		if target == null or exclude.has(target):
			continue
		var distance := origin.distance_to(target.global_position)
		if distance > radius:
			continue
		hits.append(
			CombatHit.create(
				target,
				target.global_position,
				(origin - target.global_position).normalized(),
				distance
			)
		)
	return hits


func reset_counters() -> void:
	ray_calls = 0
	overlap_calls = 0
	ray_directions.clear()
