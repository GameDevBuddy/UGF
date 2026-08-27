class_name PhysicsHitProvider
extends HitProvider
## The real world, behind the seam.
##
## The only place in Combat that touches Godot's physics server. Everything
## above it -- deliveries, the attack state machine, damage application -- is
## plain maths and can be exercised with a fake provider (rule 33).

## Collision layers queried. Defaults to everything, which is the right default
## for a framework that cannot know a project's layer scheme.
var collision_mask: int = 0xFFFFFFFF

## Whether queries stop on [Area3D] as well as bodies. Off by default: an
## interaction volume or a trigger is not something a bullet should stop on.
var hit_areas: bool = false

var _space: PhysicsDirectSpaceState3D = null


## Builds a provider against the world [param node] lives in. Returns a
## provider with no space when the node is not in a tree, which answers every
## query with nothing rather than erroring.
static func for_node(node: Node3D) -> PhysicsHitProvider:
	var provider := PhysicsHitProvider.new()
	if node != null and node.is_inside_tree():
		var world := node.get_world_3d()
		if world != null:
			provider._space = world.direct_space_state
	return provider


func is_ready() -> bool:
	return _space != null


func cast_ray(
	origin: Vector3,
	direction: Vector3,
	distance: float,
	exclude: Array[Node] = []
) -> CombatHit:
	if _space == null or distance <= 0.0:
		return null
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * distance
	)
	query.collision_mask = collision_mask
	query.collide_with_areas = hit_areas
	query.exclude = _rids(exclude)

	var result := _space.intersect_ray(query)
	if result.is_empty():
		return null

	var position: Vector3 = result.get("position", origin)
	var hit := CombatHit.create(
		_entity_of(result.get("collider")),
		position,
		result.get("normal", Vector3.UP),
		origin.distance_to(position)
	)
	hit.collider = result.get("collider")
	return hit


func overlap_sphere(
	origin: Vector3, radius: float, exclude: Array[Node] = []
) -> Array[CombatHit]:
	var hits: Array[CombatHit] = []
	if _space == null or radius <= 0.0:
		return hits

	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = collision_mask
	query.collide_with_areas = hit_areas
	query.exclude = _rids(exclude)

	# One entry per collider, and an entity with three collision shapes would
	# otherwise be struck three times by one swing.
	var seen: Dictionary[int, bool] = {}
	for result in _space.intersect_shape(query, 32):
		var collider: Object = result.get("collider")
		if collider == null or not collider is Node3D:
			continue
		var entity := _entity_of(collider)
		if entity == null or seen.has(entity.get_instance_id()):
			continue
		seen[entity.get_instance_id()] = true

		var position: Vector3 = (collider as Node3D).global_position
		var hit := CombatHit.create(
			entity, position, (origin - position).normalized(), origin.distance_to(position)
		)
		hit.collider = collider as Node
		hits.append(hit)
	return hits


# --- Internals ------------------------------------------------------------

## Walks up to the entity root a collider belongs to, so a hit reports the
## character rather than its capsule.
##
## Upward from a known node and stopping at the first entity root: the bounded
## kind of tree walk, not the archaeology rule 22 forbids.
func _entity_of(collider: Variant) -> Node:
	if not collider is Node:
		return null
	var node := collider as Node
	while node != null:
		if DefinitionBinder.is_entity_root(node):
			return node
		node = node.get_parent()
	return collider as Node


func _rids(exclude: Array[Node]) -> Array[RID]:
	var rids: Array[RID] = []
	for node in exclude:
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
		elif node != null:
			for child in node.get_children():
				if child is CollisionObject3D:
					rids.append((child as CollisionObject3D).get_rid())
	return rids
