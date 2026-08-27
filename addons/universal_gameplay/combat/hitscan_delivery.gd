class_name HitscanDelivery
extends AttackDelivery
## A shot that arrives the instant it is fired.
##
## One ray for a rifle, eight for a shotgun. The pellets are the reason spread
## belongs to the delivery rather than to the loop above it: each one gets its
## own direction out of the same cone and the same seeded stream, so a shotgun
## blast is reproducible.

## Metres the shot carries. Named max_range because range is a GDScript
## built-in and a member that shadows one is a trap for every later reader.
@export_range(0.0, 1000.0, 0.1, "or_greater") var max_range: float = 100.0

## Rays per shot. Above one is a shotgun; each pellet is a separate hit and
## carries the attack's damage in full.
@export_range(1, 64) var pellets: int = 1

## Additional cone in degrees this delivery always adds, on top of whatever
## spread the weapon's current state supplies. A shotgun's inherent scatter.
@export_range(0.0, 45.0, 0.01) var inherent_spread: float = 0.0

@export_group("Falloff")
## Metres of full damage.
@export_range(0.0, 1000.0, 0.1, "or_greater") var falloff_start: float = 0.0

## Metres past which damage is at its minimum.
@export_range(0.0, 1000.0, 0.1, "or_greater") var falloff_end: float = 0.0

## Multiplier at and beyond [member falloff_end].
@export_range(0.0, 1.0, 0.01) var minimum_multiplier: float = 1.0


func resolve(context: AttackContext, provider: HitProvider) -> Array[CombatHit]:
	var hits: Array[CombatHit] = []
	if context == null or provider == null or max_range <= 0.0:
		return hits

	var cone := context.spread_degrees + inherent_spread
	var rng := context.get_rng()
	for pellet in pellets:
		var direction := CombatSolver.spread_direction(context.direction, cone, rng)
		var hit := provider.cast_ray(context.origin, direction, max_range, context.exclude)
		if hit == null:
			continue
		hit.damage_scale = CombatSolver.range_multiplier(
			hit.distance, falloff_start, falloff_end, minimum_multiplier
		)
		hits.append(hit)
	return hits


func get_maximum_range() -> float:
	return max_range


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if max_range <= 0.0:
		result.add_error(
			&"hitscan.no_range",
			"A hitscan delivery with no range can never reach anything.",
			resource_path,
			"max_range"
		)
	if falloff_end > 0.0 and falloff_end <= falloff_start:
		result.add_error(
			&"hitscan.inverted_falloff",
			"Falloff ends at or before it starts, so damage would jump rather than fade.",
			resource_path,
			"falloff_end"
		)
	if falloff_end > max_range:
		result.add_warning(
			&"hitscan.falloff_beyond_range",
			"Falloff finishes past the weapon's range, so its minimum is never reached.",
			resource_path,
			"falloff_end"
		)
	return result
