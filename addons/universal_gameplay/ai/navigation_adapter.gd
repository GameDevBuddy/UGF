class_name NavigationAdapter
extends FrameworkComponent
## Turns "go there" into a direction to move in.
##
## Wraps a [NavigationAgent3D] when one is wired and steers straight at the
## goal when one is not. Both are legitimate: a top-down arena game with no
## navmesh should not have to bake one to make an NPC walk at you, and rule 31
## says a missing optional piece is a valid state rather than an error.
##
## [b]It never moves anything.[/b] It answers a direction; the brain feeds that
## to [method MovementComponent.set_move_direction], which is the same call the
## player's controller makes (rule 14, rule 4).

## Emitted when the current goal is reached.
signal destination_reached(destination: Vector3)
## Emitted when a goal is set, so a debug overlay can draw it.
signal destination_set(destination: Vector3)

## Godot's pathfinder. Absent, this steers straight at the goal.
@export var agent: NavigationAgent3D

## Body whose position is compared against the goal. Absent, the entity root.
@export var body: Node3D

## Metres from the goal that count as arrived, when there is no agent to say.
@export_range(0.01, 10.0, 0.01) var arrival_distance: float = 0.5

var _destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _arrived: bool = false


func initialize(context: EntityContext) -> void:
	super(context)
	if body == null:
		body = get_entity() as Node3D


func has_destination() -> bool:
	return _has_destination


func get_destination() -> Vector3:
	return _destination


func is_navigating() -> bool:
	return _has_destination and not _arrived


## Sets where to go. Re-setting the same goal does not restart anything, so a
## brain can call this every tick without cancelling its own path.
func set_destination(destination: Vector3) -> void:
	if _has_destination and _destination.is_equal_approx(destination):
		return
	_destination = destination
	_has_destination = true
	_arrived = false
	if agent != null:
		agent.target_position = destination
	destination_set.emit(destination)


func clear_destination() -> void:
	_has_destination = false
	_arrived = false


## Distance still to cover, or zero when there is nowhere to be.
func get_remaining_distance() -> float:
	if not _has_destination:
		return 0.0
	return get_position().distance_to(_destination)


func is_at_destination() -> bool:
	if not _has_destination:
		return true
	if agent != null:
		return agent.is_navigation_finished()
	return get_remaining_distance() <= arrival_distance


## Which way to move this frame to make progress, or zero when there is nowhere
## to go. Normalised and flattened: height is the mover's business, not the
## navigator's.
func get_desired_direction() -> Vector3:
	if not _has_destination or _arrived:
		return Vector3.ZERO
	var here := get_position()
	var next := _destination
	if agent != null:
		agent.target_position = _destination
		next = agent.get_next_path_position()
	var direction := next - here
	direction.y = 0.0
	if direction.length() <= 0.001:
		return Vector3.ZERO
	return direction.normalized()


func get_position() -> Vector3:
	if body != null and body.is_inside_tree():
		return body.global_position
	return Vector3.ZERO


## Checks arrival and announces it once. Called by the controller each tick;
## separate from [method get_desired_direction] so asking which way to go never
## has the side effect of declaring the journey over.
func tick(_delta: float) -> void:
	if not _has_destination or _arrived:
		return
	if is_at_destination():
		_arrived = true
		destination_reached.emit(_destination)
