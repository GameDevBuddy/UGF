class_name SpawnAnchor
extends FrameworkComponent
## A place things can appear: a doorway, a lay-by, an alley mouth, a lane end.
##
## [b]Anchors are registered, never searched for.[/b] The service keeps them
## bucketed by region, so "where can I put a pedestrian in the docks?" is a
## dictionary lookup rather than a walk of the scene tree — which is the same
## reason the population counts live in [WorldStateService] (rule 25 of the
## plan's performance rules, and half of the M14 exit gate).
##
## A component on a scene marker rather than a resource, because where a thing
## goes is a position in a scene and belongs in the scene.

## Emitted when this anchor places something, so a project can decorate it.
signal spawned_at(entity: Node)

## Which region this anchor belongs to. Blank asks the world which region the
## anchor stands in, once, at registration.
@export var region_id: StringName = &""

## Which pools may use this anchor. Empty accepts any pool that applies to the
## region, which is the usual case.
@export var accepts_categories: Array[StringName] = []

## Radius around the anchor within which something is placed, so a doorway
## does not produce a stack of identical pedestrians.
@export_range(0.0, 100.0, 0.1, "or_greater") var scatter: float = 1.0

## Whether the anchor may be used. What a blocked alley and a debug toggle
## move.
@export var enabled: bool = true

## Seconds before this anchor may be used again, so a doorway does not emit a
## crowd in one tick.
@export_range(0.0, 600.0, 0.1, "or_greater") var reuse_delay: float = 2.0

## Weight when the service picks among a region's anchors.
@export_range(0.0, 100.0, 0.01, "or_greater") var weight: float = 1.0

## The spatial node this anchor stands at.
##
## A [FrameworkComponent] is a plain [Node] and has no position of its own, the
## same reason [NavigationAdapter] and [VehicleBodyAdapter] take a body. Left
## null this falls back to the entity root, which covers the usual case of an
## anchor hung directly off a [Node3D] marker.
@export var marker: Node3D

var _cooldown: float = 0.0


func get_region_id() -> StringName:
	return region_id


func set_region_id(value: StringName) -> void:
	region_id = value


func accepts(category: StringName) -> bool:
	if not enabled or _cooldown > 0.0:
		return false
	return accepts_categories.is_empty() or accepts_categories.has(category)


func is_ready() -> bool:
	return enabled and _cooldown <= 0.0


func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown)


## Advances this anchor's cooldown. Called by the service for the anchors of
## active regions only, which is what keeps a dormant district free.
func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


## A position to place something at, scattered around the anchor.
func get_spawn_position(rng: RandomNumberGenerator) -> Vector3:
	var origin := get_position()
	if scatter <= 0.0:
		return origin
	var angle := rng.randf() * TAU
	var distance := sqrt(rng.randf()) * scatter
	return origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func get_position() -> Vector3:
	if marker != null and marker.is_inside_tree():
		return marker.global_position
	var entity := get_entity() as Node3D
	if entity != null and entity.is_inside_tree():
		return entity.global_position
	var parent := get_parent() as Node3D
	if parent != null and parent.is_inside_tree():
		return parent.global_position
	return Vector3.ZERO


## Marks the anchor as just used, starting its cooldown.
func mark_used(entity: Node = null) -> void:
	_cooldown = reuse_delay
	if entity != null:
		spawned_at.emit(entity)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if region_id == &"":
		result.add_info(
			&"anchor.no_region",
			(
				"This anchor names no region, so the world is asked which region "
				+ "it stands in when it registers. That needs the region to have "
				+ "geometry."
			),
			"",
			"region_id"
		)
	return result
