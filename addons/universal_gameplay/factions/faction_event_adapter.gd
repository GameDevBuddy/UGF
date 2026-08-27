class_name FactionEventAdapter
extends Node
## Promotes a change of heart to a cross-feature fact.
##
## A [Node] rather than a [FrameworkComponent], for the same reason
## [NarrativeEventAdapter] is: what it observes is a service, and there is no
## entity whose composition would decide whether a faction turning hostile is
## worth announcing.
##
## With it, a mission can have an objective that counts "the watch turned on
## you" without Missions importing Factions.

signal attitude_published(event: FrameworkEvent)

@export var service: FactionService
@export var event_bus: Node

const FactionEvent := preload(
	"res://addons/universal_gameplay/factions/faction_event.gd"
)

var _bus: Node = null
var _watched: FactionService = null


func _ready() -> void:
	set_bus(event_bus if event_bus != null else _find_bus())
	watch(service)


func _exit_tree() -> void:
	watch(null)


func watch(target: FactionService) -> void:
	if _watched == target:
		return
	if _watched != null and _watched.attitude_changed.is_connected(_on_attitude):
		_watched.attitude_changed.disconnect(_on_attitude)
	_watched = target
	service = target
	if _watched != null and not _watched.attitude_changed.is_connected(_on_attitude):
		_watched.attitude_changed.connect(_on_attitude)


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_ATTITUDE_CHANGED)


func get_bus() -> Node:
	return _bus


func _on_attitude(
	faction: StringName, other: StringName, attitude: AttitudeSolver.Attitude
) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	var event := FactionEvent.create(faction, other, attitude)
	_bus.call("publish", event)
	attitude_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
