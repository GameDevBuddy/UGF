class_name MeleeDelivery
extends AttackDelivery
## A swing: everything inside an arc, within reach.
##
## Queries a sphere and filters it to a cone, rather than asking physics for a
## cone shape it does not have. The filtering is [CombatSolver.is_within_arc],
## which means the question "would this swing have hit that bandit" is
## answerable in a unit test with three vectors and no world.

## Metres the swing reaches.
@export_range(0.0, 20.0, 0.01, "or_greater") var reach: float = 2.0

## Full opening angle in degrees. 360 hits everything within reach, which is
## the spin attack; 60 is a thrust.
@export_range(0.0, 360.0, 1.0) var arc_degrees: float = 90.0

## How many things one swing may connect with. Zero is unlimited. One is a
## thrust that stops at the first body.
@export_range(0, 32) var max_targets: int = 0

## Damage multiplier at the edge of reach, so a swing that barely connects
## does less. One disables falloff.
@export_range(0.0, 1.0, 0.01) var edge_multiplier: float = 1.0


func resolve(context: AttackContext, provider: HitProvider) -> Array[CombatHit]:
	var hits: Array[CombatHit] = []
	if context == null or provider == null or reach <= 0.0:
		return hits

	var candidates := provider.overlap_sphere(context.origin, reach, context.exclude)
	for hit in candidates:
		if not CombatSolver.is_within_arc(
			context.origin, context.direction, hit.position, arc_degrees, reach
		):
			continue
		hit.damage_scale = _falloff(hit.distance)
		hits.append(hit)

	# Nearest first, so a capped swing takes what it reached first rather than
	# whatever physics happened to report first.
	hits.sort_custom(func(a: CombatHit, b: CombatHit) -> bool: return a.distance < b.distance)
	if max_targets > 0 and hits.size() > max_targets:
		hits.resize(max_targets)
	return hits


func get_maximum_range() -> float:
	return reach


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if reach <= 0.0:
		result.add_error(
			&"melee.no_reach",
			"A melee delivery with no reach can never connect with anything.",
			resource_path,
			"reach"
		)
	if arc_degrees <= 0.0:
		result.add_error(
			&"melee.no_arc",
			"A melee delivery with a zero arc can never connect with anything.",
			resource_path,
			"arc_degrees"
		)
	return result


func _falloff(distance: float) -> float:
	if edge_multiplier >= 1.0 or reach <= 0.0:
		return 1.0
	return lerpf(1.0, edge_multiplier, clampf(distance / reach, 0.0, 1.0))
