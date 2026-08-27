class_name RegionTracker
extends FrameworkComponent
## Reports which region its entity is in, so nothing has to go looking.
##
## [b]The direction of this is the whole point.[/b] The obvious design is a
## service that walks every entity each frame asking where it is; that is
## precisely the global per-frame scan the M14 exit gate forbids. Inverting it
## — each entity telling the world when it crosses a boundary — makes the cost
## proportional to movement between regions rather than to population.
##
## Even the check is not per-frame. An entity is compared against its region's
## geometry only after it has moved [member movement_threshold] metres, because
## something standing still cannot have left, and something walking has not
## left a district in the last sixteen milliseconds.

## Emitted when this entity's region changes.
signal region_changed(from: StringName, to: StringName)

## Where to report to. Injected at composition time (rule 20); resolved from
## the core when left null.
@export var world: WorldStateService

## Which budget this entity counts against.
@export var category: StringName = &"population.ambient"

## The region this entity starts in. Blank asks the world where it stands.
@export var region_id: StringName = &""

## Metres this entity must move before its region is rechecked. The whole
## saving: a crowd standing at a bus stop costs nothing at all.
@export_range(0.0, 100.0, 0.1, "or_greater") var movement_threshold: float = 5.0

## The node whose position is tracked. Left null, the entity root.
@export var body: Node3D

## Recheck from [method Node._physics_process]. Off when a project drives
## region changes from its own streaming volumes, which is cheaper again.
@export var auto_tick: bool = false

var _region: StringName = &""
var _last_checked_at: Vector3 = Vector3.ZERO
var _registered: bool = false


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	if world == null:
		world = _resolve_world()
	if body == null:
		body = get_entity() as Node3D
	_register()
	set_physics_process(auto_tick)


func _exit_tree() -> void:
	# An entity leaving the tree must leave the count too, or a region slowly
	# fills with things that no longer exist and stops accepting spawns.
	if world != null and _registered:
		world.remove_entity(get_entity())
		_registered = false


func _physics_process(_delta: float) -> void:
	refresh()


# --- Queries --------------------------------------------------------------

func get_region_id() -> StringName:
	return _region


func is_registered() -> bool:
	return _registered


func get_position() -> Vector3:
	if body != null and body.is_inside_tree():
		return body.global_position
	return Vector3.ZERO


## Distance moved since the last region check. What the threshold compares.
func get_drift() -> float:
	return get_position().distance_to(_last_checked_at)


# --- Reporting ------------------------------------------------------------

## Rechecks this entity's region if it has moved far enough.
##
## Returns true when the region actually changed. Cheap to call often and
## cheaper to call rarely: below the threshold it is one distance comparison.
func refresh() -> bool:
	if world == null or not _registered:
		return false
	if movement_threshold > 0.0 and get_drift() < movement_threshold:
		return false
	_last_checked_at = get_position()
	var found := world.find_region_at(_last_checked_at)
	if found == &"" or found == _region:
		return false
	return _move_to(found)


## Puts this entity in a region explicitly. What a project's own streaming
## volume, a teleport and a test call.
func set_region(new_region: StringName) -> bool:
	if new_region == _region:
		return false
	return _move_to(new_region)


# --- Internals ------------------------------------------------------------

func _register() -> void:
	if world == null or _registered:
		return
	var target := region_id
	if target == &"":
		target = world.find_region_at(get_position())
	if target == &"":
		return
	if world.set_entity_region(get_entity(), target, category).is_ok():
		_region = target
		_registered = true
		_last_checked_at = get_position()


func _move_to(new_region: StringName) -> bool:
	var previous := _region
	var moved := world.set_entity_region(get_entity(), new_region, category)
	if moved.is_err():
		return false
	_region = new_region
	_registered = new_region != &""
	region_changed.emit(previous, new_region)
	return true


func _resolve_world() -> WorldStateService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_WORLD_STATE) as WorldStateService
