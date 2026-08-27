class_name CrimeEventAdapter
extends Node
## Promotes crimes and wanted-level changes to cross-feature facts.
##
## A [Node] rather than a [FrameworkComponent] for the same reason
## [FactionEventAdapter] is: what it observes is a service, and there is no
## entity whose composition decides whether the law is worth announcing.
##
## With it, a mission can have an objective that counts robberies and a HUD can
## show stars, neither of them importing Crime. Delete it and the law still
## works; nothing simply hears about it (rule 10).

signal crime_published(event: FrameworkEvent)

@export var service: HeatService
@export var event_bus: Node

@export var publish_crimes: bool = true
@export var publish_wanted: bool = true

const CrimeEvent := preload(
	"res://addons/universal_gameplay/crime_heat/crime_event.gd"
)

var _bus: Node = null
var _watched: HeatService = null


func _ready() -> void:
	set_bus(event_bus if event_bus != null else _find_bus())
	watch(service)


func _exit_tree() -> void:
	watch(null)


func watch(target: HeatService) -> void:
	if _watched == target:
		return
	if _watched != null and _watched.crime_reported.is_connected(_on_crime):
		_watched.crime_reported.disconnect(_on_crime)
		_watched.wanted_changed.disconnect(_on_wanted)
	_watched = target
	service = target
	if _watched != null and not _watched.crime_reported.is_connected(_on_crime):
		_watched.crime_reported.connect(_on_crime)
		_watched.wanted_changed.connect(_on_wanted)


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_CRIME_WITNESSED)
		_bus.call("register_event", GameplayNames.EVENT_WANTED_CHANGED)


func get_bus() -> Node:
	return _bus


func _on_crime(context: CrimeContext) -> void:
	if publish_crimes:
		_publish(CrimeEvent.witnessed(context))


func _on_wanted(actor_id: StringName, faction: StringName, tier: WantedTier) -> void:
	if publish_wanted:
		_publish(
			CrimeEvent.wanted(
				actor_id, faction, tier, _watched.get_heat(actor_id, faction)
			)
		)


func _publish(event: FrameworkEvent) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	_bus.call("publish", event)
	crime_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
