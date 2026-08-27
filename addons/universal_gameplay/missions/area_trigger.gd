class_name AreaTrigger
extends FrameworkComponent
## Publishes "somebody reached this place" as a cross-feature fact.
##
## Wraps an [Area3D] rather than being one, the way [NavigationAdapter] wraps a
## [NavigationAgent3D]: the area is a scene concern a level designer places,
## and this is the seam that turns its collision signals into something a
## mission can count without knowing that Area3D exists (rule 9, rule 21).
##
## Works with no area at all: [method enter] can be called directly by a
## project's own trigger volume, a cutscene, or a test.

signal entered(body: Node)
signal exited(body: Node)

## Semantic name of the place: [code]area.docks[/code]. Blank publishes
## nothing, because an unnamed area is one no objective could match.
@export var area_id: StringName = &""

## The volume to listen to. Absent, this only reacts to explicit calls.
@export var area: Area3D

## Tags carried on the event, for an objective matching a kind of place:
## [code]area.restricted[/code].
@export var tags: Array[StringName] = []

## Publish departures as well as arrivals. Off by default: most objectives ask
## whether you got there, not whether you left.
@export var publish_exits: bool = false

## Only announce bodies in this group. Blank announces everything, which for a
## busy area is a lot of events.
@export var only_group: StringName = &""

@export var event_bus: Node

const AreaEvent := preload(
	"res://addons/universal_gameplay/missions/area_event.gd"
)

var _bus: Node = null
var _inside: Dictionary[int, bool] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_bus = event_bus if event_bus != null else _find_bus()
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_AREA_ENTERED)
	_connect_area()


func _ready() -> void:
	if _bus == null:
		_bus = event_bus if event_bus != null else _find_bus()
	_connect_area()


func _exit_tree() -> void:
	if area == null:
		return
	if area.body_entered.is_connected(_on_body_entered):
		area.body_entered.disconnect(_on_body_entered)
	if area.body_exited.is_connected(_on_body_exited):
		area.body_exited.disconnect(_on_body_exited)


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_AREA_ENTERED)


func get_bus() -> Node:
	return _bus


## Whether [param body] is currently inside.
func contains(body: Node) -> bool:
	return body != null and _inside.has(body.get_instance_id())


func get_occupant_count() -> int:
	return _inside.size()


## Announces an arrival. Public so a project's own trigger volume, a cutscene
## or a test can drive it without an [Area3D].
##
## Re-entry by something already inside is ignored: a body brushing the edge of
## a volume can fire several times a second, and an objective counting arrivals
## would complete on one careless step.
func enter(body: Node) -> bool:
	if body == null or contains(body) or not _accepts(body):
		return false
	_inside[body.get_instance_id()] = true
	entered.emit(body)
	_publish(body, true)
	return true


func exit(body: Node) -> bool:
	if body == null or not contains(body):
		return false
	_inside.erase(body.get_instance_id())
	exited.emit(body)
	if publish_exits:
		_publish(body, false)
	return true


# --- Internals ------------------------------------------------------------

func _accepts(body: Node) -> bool:
	return only_group == &"" or body.is_in_group(only_group)


func _publish(body: Node, is_entering: bool) -> void:
	if area_id == &"" or _bus == null or not _bus.has_method("publish"):
		return
	_bus.call("publish", AreaEvent.create(area_id, body, is_entering, tags))


func _connect_area() -> void:
	if area == null:
		return
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	if not area.body_exited.is_connected(_on_body_exited):
		area.body_exited.connect(_on_body_exited)


## Walks up to the entity root, so a mission hears about the character rather
## than its capsule. Upward from a known node and stopping at the first entity
## root: the bounded kind of walk, not the archaeology rule 22 forbids.
func _entity_of(body: Node) -> Node:
	var node := body
	while node != null:
		if DefinitionBinder.is_entity_root(node):
			return node
		node = node.get_parent()
	return body


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")


func _on_body_entered(body: Node) -> void:
	enter(_entity_of(body))


func _on_body_exited(body: Node) -> void:
	exit(_entity_of(body))
