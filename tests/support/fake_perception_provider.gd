class_name FakePerceptionProvider
extends PerceptionProvider
## A world of candidates and one occlusion switch, so noticing can be tested
## without a navmesh, colliders or a physics frame.
##
## The payoff for perception querying a [PerceptionProvider] rather than the
## physics server: a guard spotting an intruder, failing to spot a crouching
## one, and losing them behind a wall are three assertions here rather than
## three scenes.

## Everything that could be perceived. Positions come from their transforms.
var candidates: Array[Node] = []

## Entities whose sight line is blocked, whatever the distance. Standing in
## for a wall, without needing one.
var occluded: Array[Node] = []

## Blocks every sight line at once.
var blind: bool = false

var candidate_calls: int = 0
var line_of_sight_calls: int = 0


func find_candidates(origin: Vector3, radius: float) -> Array[Node]:
	candidate_calls += 1
	var found: Array[Node] = []
	for candidate in candidates:
		var spatial := candidate as Node3D
		if spatial == null:
			continue
		if origin.distance_to(spatial.global_position) <= radius:
			found.append(candidate)
	return found


func has_line_of_sight(_from: Vector3, _to: Vector3, ignore: Array[Node] = []) -> bool:
	line_of_sight_calls += 1
	if blind:
		return false
	for node in ignore:
		if occluded.has(node):
			return false
	return true


func reset_counters() -> void:
	candidate_calls = 0
	line_of_sight_calls = 0
