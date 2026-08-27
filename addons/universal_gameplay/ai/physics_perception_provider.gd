class_name PhysicsPerceptionProvider
extends PerceptionProvider
## The real world, behind the perception seam.
##
## Candidates come from the [constant GameplayNames.GROUP_PERCEIVABLE] group
## rather than a physics overlap: what an NPC should notice is a gameplay
## question, not a collision one, and a group is what that vocabulary is for
## (Ontology Rulebook 12). Occlusion is the only part that needs the physics
## server, and it is the only thing this asks it.

## Collision layers that block sight. Defaults to everything.
var occlusion_mask: int = 0xFFFFFFFF

var _tree: SceneTree = null
var _space: PhysicsDirectSpaceState3D = null


## Builds a provider against the world [param node] lives in. A node outside
## the tree yields a provider that finds nothing, rather than one that errors.
static func for_node(node: Node3D) -> PhysicsPerceptionProvider:
	var provider := PhysicsPerceptionProvider.new()
	if node != null and node.is_inside_tree():
		provider._tree = node.get_tree()
		var world := node.get_world_3d()
		if world != null:
			provider._space = world.direct_space_state
	return provider


func is_ready() -> bool:
	return _tree != null


func find_candidates(origin: Vector3, radius: float) -> Array[Node]:
	var found: Array[Node] = []
	if _tree == null or radius <= 0.0:
		return found
	for node in _tree.get_nodes_in_group(GameplayNames.GROUP_PERCEIVABLE):
		var spatial := node as Node3D
		if spatial == null or not spatial.is_inside_tree():
			continue
		if origin.distance_to(spatial.global_position) <= radius:
			found.append(spatial)
	return found


func has_line_of_sight(from: Vector3, to: Vector3, ignore: Array[Node] = []) -> bool:
	if _space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = occlusion_mask
	query.collide_with_areas = false
	query.exclude = _rids(ignore)
	return _space.intersect_ray(query).is_empty()


func _rids(ignore: Array[Node]) -> Array[RID]:
	var rids: Array[RID] = []
	for node in ignore:
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
		elif node != null:
			for child in node.get_children():
				if child is CollisionObject3D:
					rids.append((child as CollisionObject3D).get_rid())
	return rids
