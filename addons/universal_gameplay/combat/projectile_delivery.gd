class_name ProjectileDelivery
extends AttackDelivery
## A shot that takes time to arrive.
##
## The one delivery whose [method AttackDelivery.resolve] returns nothing and
## means it: a rocket in flight has hit nobody yet. The hits arrive later, on
## the projectile's own signal, and the [AttackContext] travels with it so the
## kill is still attributed to whoever fired.

## What is launched. Its root should carry a [Projectile]; a scene without one
## flies nowhere, which validation reports rather than the framework guessing.
@export var projectile_scene: PackedScene

## Rounds launched per shot, for a rocket pod or a spread of arrows.
@export_range(1, 32) var count: int = 1

## Cone in degrees this delivery always adds on top of the weapon's spread.
@export_range(0.0, 45.0, 0.01) var inherent_spread: float = 0.0

## Metres ahead of the origin the projectile appears, so it does not spawn
## inside the shooter's own collider.
@export_range(0.0, 5.0, 0.01) var muzzle_offset: float = 0.5

## Overrides the projectile scene's own speed. Zero keeps the scene's.
@export_range(0.0, 500.0, 0.1, "or_greater") var speed_override: float = 0.0


func resolve(context: AttackContext, provider: HitProvider) -> Array[CombatHit]:
	var hits: Array[CombatHit] = []
	if context == null or projectile_scene == null or context.world == null:
		return hits

	var rng := context.get_rng()
	var cone := context.spread_degrees + inherent_spread
	for index in count:
		var direction := CombatSolver.spread_direction(context.direction, cone, rng)
		var projectile := _spawn(context, provider, direction)
		if projectile == null:
			continue
		var muzzle := projectile.position
		context.world.add_child(projectile)
		# global_position is only legal inside the tree, so the world point is
		# carried in the local one and applied on the far side of add_child.
		projectile.global_position = muzzle
	return hits


## The projectiles a shot would launch, without a world to put them in. What a
## test uses, and what a pooling project overrides.
func build(
	context: AttackContext, provider: HitProvider, direction: Vector3
) -> Projectile:
	return _spawn(context, provider, direction)


func get_maximum_range() -> float:
	if projectile_scene == null:
		return 0.0
	var sample := projectile_scene.instantiate()
	var projectile := sample as Projectile
	var reach := projectile.max_distance if projectile != null else 0.0
	sample.free()
	return reach


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if projectile_scene == null:
		result.add_error(
			&"projectile.no_scene",
			"A projectile delivery with no scene fires nothing.",
			resource_path,
			"projectile_scene"
		)
	return result


func _spawn(
	context: AttackContext, provider: HitProvider, direction: Vector3
) -> Projectile:
	if projectile_scene == null:
		return null
	var instance := projectile_scene.instantiate()
	var projectile := instance as Projectile
	if projectile == null:
		# Content that is wrong, not a reason to crash the shot and leave the
		# weapon in a half-fired state.
		if instance != null:
			instance.free()
		return null

	if speed_override > 0.0:
		projectile.speed = speed_override
	projectile.position = context.origin + direction.normalized() * muzzle_offset
	projectile.launch(context, provider, direction)
	return projectile
