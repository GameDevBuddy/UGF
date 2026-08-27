class_name TargetingComponent
extends FrameworkComponent
## Free aim, soft target and hard lock, as Implementation Plan 14 lists them.
##
## [b]All three are the same query with a different commitment.[/b] Free aim
## picks nothing. A soft target picks the best candidate each frame and lets go
## the moment something better appears or the current one leaves the cone --
## it is an aim assist, and the player never notices it working. A hard lock
## picks once and holds until told otherwise, even when the target walks behind
## a wall, because a lock that dropped on a lost line of sight would be a lock
## that fails exactly when the fight gets interesting.
##
## [b]It is an adapter and the plan says so: "hard lock optional adapter".[/b]
## Nothing in Combat requires it. Deleting the component leaves a character
## shooting wherever it is pointed, which is what free aim is (rule 10).
##
## [b]Candidates come from Perception when it is there.[/b] A target you have
## not noticed is not a target you can lock onto, and reusing the memory an NPC
## already keeps beats a second sweep of the world every frame (rule 25).
## Without Perception the component takes candidates handed to it, which is
## what lets it be tested with three plain nodes and no scene.

## Emitted when the current target changes, including to null.
signal target_changed(target: Node, previous: Node)
## Emitted when a hard lock is taken or dropped.
signal lock_changed(locked: bool, target: Node)

enum Mode {
	## Picks nothing. The character shoots where it points.
	FREE,
	## Picks the best candidate continuously, and gives it up freely.
	SOFT,
	## Picks once and holds.
	HARD,
}

@export var mode: Mode = Mode.SOFT

## Where candidates come from. Resolved from the entity when left null; absent
## means candidates must be supplied through [method set_candidates].
@export var perception: PerceptionComponent

## Where the character is looking, for the cone test. Resolved to the entity
## root when left null.
@export var origin_source: Node3D

## Half-angle in degrees a soft target may sit within.
@export_range(0.0, 180.0, 1.0) var acquire_arc_degrees: float = 35.0

## How far a target may be. Zero is unlimited, which is rarely what a game
## wants and always what a test wants.
@export_range(0.0, 1000.0, 0.5, "or_greater") var acquire_range: float = 50.0

## Wider than [member acquire_arc_degrees], so a soft target does not flicker
## on and off at the boundary. A single threshold is the classic way to make an
## aim assist feel broken.
@export_range(0.0, 180.0, 1.0) var release_arc_degrees: float = 55.0

## A hard lock survives losing sight of its target. Turning this off makes a
## lock drop the moment the target steps behind cover.
@export var lock_survives_occlusion: bool = true

@export var auto_tick: bool = true

var _target: Node = null
var _locked: bool = false
var _candidates: Array[Node] = []


func _ready() -> void:
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	if perception == null:
		perception = _find(PerceptionComponent) as PerceptionComponent
	if origin_source == null:
		origin_source = _entity_root() as Node3D
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Reading --------------------------------------------------------------

func get_target() -> Node:
	if _target != null and not is_instance_valid(_target):
		_target = null
	return _target


func has_target() -> bool:
	return get_target() != null


func is_locked() -> bool:
	return _locked and has_target()


## Direction from the aim origin to the current target, or zero with none.
##
## What a combat component asks for instead of a raw look direction when the
## player is locked on.
func get_aim_direction() -> Vector3:
	var target := get_target()
	if target == null or origin_source == null or not (target is Node3D):
		return Vector3.ZERO
	var to := (target as Node3D).global_position - origin_source.global_position
	return to.normalized() if to.length_squared() > 0.0 else Vector3.ZERO


# --- Acting ---------------------------------------------------------------

## Supplies the candidate list directly, for an entity with no Perception.
func set_candidates(candidates: Array[Node]) -> void:
	_candidates = candidates.duplicate()


## Takes a hard lock on whatever is currently the best candidate.
##
## Refused with nothing in range rather than locking onto null, so a caller can
## play a failure sound instead of showing an empty reticle.
func lock() -> FrameworkResult:
	var best := _best_candidate()
	if best == null:
		return FrameworkResult.fail(&"targeting.nothing_in_range", "Nothing to lock onto.")
	_set_target(best)
	_locked = true
	lock_changed.emit(true, best)
	return FrameworkResult.ok(best)


func unlock() -> void:
	if not _locked:
		return
	_locked = false
	lock_changed.emit(false, _target)
	if mode != Mode.HARD:
		return
	# A hard lock dropped leaves nothing selected. Falling back to a soft
	# target would silently keep aim assist on for a player who just switched
	# it off.
	_set_target(null)


## Locks if free, unlocks if locked. What one button does.
func toggle_lock() -> FrameworkResult:
	if _locked:
		unlock()
		return FrameworkResult.ok(null)
	return lock()


## Moves the hard lock to the next candidate, for a right-stick flick.
func cycle(forward: bool = true) -> FrameworkResult:
	var eligible := _eligible_candidates()
	if eligible.size() <= 1:
		return FrameworkResult.fail(
			&"targeting.nothing_to_cycle", "There is nothing else to lock onto."
		)
	var index := eligible.find(get_target())
	var step := 1 if forward else -1
	var next: Node = eligible[posmod(index + step, eligible.size())]
	_set_target(next)
	if _locked:
		lock_changed.emit(true, next)
	return FrameworkResult.ok(next)


func tick(_delta: float) -> void:
	if mode == Mode.FREE:
		_set_target(null)
		return

	if _locked:
		_hold_lock()
		return

	_set_target(_best_candidate())


# --- Internals ------------------------------------------------------------

## A hard lock only ends when the target is gone, out of range, or dead.
func _hold_lock() -> void:
	var target := get_target()
	if target == null:
		unlock()
		return
	if _is_dead(target):
		unlock()
		return
	if acquire_range > 0.0 and _distance_to(target) > acquire_range:
		unlock()
		return
	if not lock_survives_occlusion and not _is_perceived(target):
		unlock()


## The best thing to aim at right now, or null.
##
## Nearest inside the cone rather than most central, because a distant enemy
## dead ahead is almost never the one being shot at, and an assist that
## preferred it would fight the player.
func _best_candidate() -> Node:
	var best: Node = null
	var best_distance := INF
	for candidate in _eligible_candidates():
		var distance := _distance_to(candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _eligible_candidates() -> Array[Node]:
	var found: Array[Node] = []
	var current := get_target()
	for candidate in _all_candidates():
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate == _entity_root():
			continue
		if _is_dead(candidate):
			continue
		if acquire_range > 0.0 and _distance_to(candidate) > acquire_range:
			continue
		# The wider arc applies to whatever is already selected, so a soft
		# target does not flicker on and off at the boundary.
		var arc := release_arc_degrees if candidate == current else acquire_arc_degrees
		if not _within_arc(candidate, arc):
			continue
		found.append(candidate)
	return found


func _all_candidates() -> Array[Node]:
	if perception == null:
		return _candidates
	var found: Array[Node] = []
	for entry in perception.get_memory().get_entries():
		if entry.is_valid() and entry.noticed:
			found.append(entry.target)
	return found


func _within_arc(candidate: Node, arc_degrees: float) -> bool:
	if arc_degrees >= 180.0 or origin_source == null or not (candidate is Node3D):
		return true
	var facing := -origin_source.global_transform.basis.z
	var to := (candidate as Node3D).global_position - origin_source.global_position
	var front := Vector3(facing.x, 0.0, facing.z)
	var at := Vector3(to.x, 0.0, to.z)
	if front.length_squared() <= 0.0 or at.length_squared() <= 0.0:
		return true
	return rad_to_deg(front.normalized().angle_to(at.normalized())) <= arc_degrees


func _distance_to(candidate: Node) -> float:
	if origin_source == null or not (candidate is Node3D):
		return 0.0
	return origin_source.global_position.distance_to((candidate as Node3D).global_position)


## Duck-typed rather than cast: Combat must not learn what a health component
## is to decide whether something is still worth aiming at (rule 9).
func _is_dead(candidate: Node) -> bool:
	for child in candidate.get_children():
		if child.has_method("is_dead") and child.call("is_dead"):
			return true
	return false


func _is_perceived(candidate: Node) -> bool:
	if perception == null:
		return true
	var entry := perception.get_memory().get_entry(candidate)
	return entry != null and entry.visible


func _set_target(target: Node) -> void:
	if _target == target:
		return
	var previous := _target
	_target = target
	target_changed.emit(_target, previous)


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


func _find(type: Variant) -> FrameworkComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child as FrameworkComponent
	return null
