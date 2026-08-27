class_name NarrativeEventAdapter
extends Node
## Promotes narrative changes to cross-feature facts on the bus.
##
## A [Node] rather than a [FrameworkComponent], because what it observes is a
## service rather than an entity: there is no entity whose composition would
## decide whether a flag change is worth announcing. It is still deletable,
## which is the point -- a project that never counts flags in an objective
## simply never adds one, and nothing else changes (rule 10).
##
## Without this, a mission cannot count "the alarm was raised" without
## Missions importing Narrative. With it, that objective is an event name and
## a matcher on a key.

signal narrative_published(event: FrameworkEvent)

## The service to observe. Wired at composition time, or set later.
@export var narrative: NarrativeStateService

@export var event_bus: Node

@export var publish_flags: bool = true
@export var publish_counters: bool = true

const NarrativeEvent := preload(
	"res://addons/universal_gameplay/narrative/narrative_event.gd"
)

var _bus: Node = null
var _watched: NarrativeStateService = null


func _ready() -> void:
	set_bus(event_bus if event_bus != null else _find_bus())
	watch(narrative)


func _exit_tree() -> void:
	watch(null)


## Points the adapter at a service, disconnecting from any previous one.
func watch(service: NarrativeStateService) -> void:
	if _watched == service:
		return
	if _watched != null:
		if _watched.flag_changed.is_connected(_on_flag):
			_watched.flag_changed.disconnect(_on_flag)
		if _watched.counter_changed.is_connected(_on_counter):
			_watched.counter_changed.disconnect(_on_counter)
	_watched = service
	narrative = service
	if _watched == null:
		return
	if not _watched.flag_changed.is_connected(_on_flag):
		_watched.flag_changed.connect(_on_flag)
	if not _watched.counter_changed.is_connected(_on_counter):
		_watched.counter_changed.connect(_on_counter)


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus == null or not _bus.has_method("register_event"):
		return
	_bus.call("register_event", GameplayNames.EVENT_NARRATIVE_FLAG)
	_bus.call("register_event", GameplayNames.EVENT_NARRATIVE_COUNTER)


func get_bus() -> Node:
	return _bus


func _on_flag(flag: StringName, value: bool) -> void:
	if publish_flags:
		_publish(GameplayNames.EVENT_NARRATIVE_FLAG, flag, value, not value)


func _on_counter(counter: StringName, value: int, previous: int) -> void:
	if publish_counters:
		_publish(GameplayNames.EVENT_NARRATIVE_COUNTER, counter, value, previous)


func _publish(
	event_name: StringName, key: StringName, value: Variant, previous: Variant
) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	var event := NarrativeEvent.create(event_name, key, value, previous)
	_bus.call("publish", event)
	narrative_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
