class_name EventMonitor
extends Node
## A live feed of everything crossing the EventBus.
##
## [b]Debugability is architecture, not a nicety[/b] (Implementation Plan 28).
## A framework whose modules deliberately do not know about each other is a
## framework where "why did nothing happen when I killed him?" is genuinely
## hard to answer — the answer is always a fact that was or was not published,
## and this is where you look.
##
## A ring buffer, so leaving it running costs a fixed amount of memory rather
## than an increasing one. Subscribing to a bus is cheap; keeping every event
## since launch is not.

## Emitted per event recorded, for a panel that draws as it goes.
signal event_recorded(entry: Dictionary)

## The bus to watch. Left null, the [code]EventBus[/code] autoload.
@export var event_bus: Node

## How many entries to keep. The oldest are dropped.
@export_range(1, 10000) var capacity: int = 200

## Event names to record. Empty records everything, which is the usual case
## for a debug tool and the wrong default for anything else.
@export var only_events: Array[StringName] = []

## Event names never recorded. What silences a chatty one while watching for
## something rare.
@export var ignore_events: Array[StringName] = []

## Whether recording is on.
@export var recording: bool = true

var _entries: Array[Dictionary] = []
var _counts: Dictionary[StringName, int] = {}
var _bus: Node = null
var _watched: Array[StringName] = []


func _ready() -> void:
	attach(event_bus if event_bus != null else _find_bus())


func _exit_tree() -> void:
	attach(null)


# --- Attachment -----------------------------------------------------------

## Watches a bus. Subscribes to every event the bus has registered, which is
## why a monitor added late still sees everything the game publishes.
func attach(bus: Node) -> void:
	_detach()
	_bus = bus
	event_bus = bus
	if _bus == null or not _bus.has_method("subscribe"):
		return
	for event_name in _known_events():
		if _should_watch(event_name):
			_bus.call("subscribe", event_name, _on_event)
			_watched.append(event_name)


## Re-subscribes, picking up events registered since. A module installed after
## the monitor registers its own event names, and without this the monitor
## would silently never see them.
func rescan() -> void:
	attach(_bus)


func get_bus() -> Node:
	return _bus


func get_watched_events() -> Array[StringName]:
	return _watched.duplicate()


# --- The feed -------------------------------------------------------------

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func get_entry_count() -> int:
	return _entries.size()


## The most recent entries, newest last. What a panel draws.
func get_recent(count: int = 20) -> Array[Dictionary]:
	var from := maxi(0, _entries.size() - count)
	return _entries.slice(from)


func get_last() -> Dictionary:
	return _entries.back() if not _entries.is_empty() else {}


## Every entry for one event name.
func find_entries(event_name: StringName) -> Array[Dictionary]:
	return _entries.filter(
		func(entry: Dictionary) -> bool: return entry["event"] == event_name
	)


## How many of each event have been seen. The first thing worth looking at:
## a fact published a thousand times and a fact published never are two very
## different bugs.
func get_counts() -> Dictionary:
	return _counts.duplicate()


func get_count(event_name: StringName) -> int:
	return _counts.get(event_name, 0)


func has_seen(event_name: StringName) -> bool:
	return get_count(event_name) > 0


func clear() -> void:
	_entries.clear()
	_counts.clear()


## The feed as lines of text, for a console or a log dump.
func describe(count: int = 20) -> String:
	var lines := PackedStringArray()
	for entry in get_recent(count):
		lines.append(
			"%8d  %-24s %s" % [entry["at_ms"], entry["event"], entry["summary"]]
		)
	return "\n".join(lines)


# --- Internals ------------------------------------------------------------

func _on_event(event: FrameworkEvent) -> void:
	if not recording or event == null:
		return
	var event_name := event.get_event_name()
	var entry: Dictionary = {
		"event": event_name,
		"at_ms": Time.get_ticks_msec(),
		"source": event.source.name if event.source != null else "",
		"summary": _summarise(event),
	}
	_entries.append(entry)
	_counts[event_name] = _counts.get(event_name, 0) + 1
	# Trimmed after appending rather than before, so capacity 1 keeps the
	# newest rather than refusing it.
	while _entries.size() > capacity:
		_entries.remove_at(0)
	event_recorded.emit(entry)


## A one-line description built from the event's own exported fields.
##
## Read generically rather than by casting to each event type: a monitor that
## knew what an ActorDiedEvent was would need editing every time a module added
## a fact, which is exactly what a debug tool must not need (rule 9).
func _summarise(event: FrameworkEvent) -> String:
	var parts := PackedStringArray()
	for property in event.get_property_list():
		var name: String = property["name"]
		if name.begins_with("_") or name in ["script", "source", "timestamp_ms"]:
			continue
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = event.get(name)
		if value == null or _is_default(value):
			continue
		parts.append("%s=%s" % [name, value])
	return " ".join(parts)


## Whether a value is the type's zero. Skipping defaults is what keeps a line
## readable: an event with twelve fields and two set should print two.
func _is_default(value: Variant) -> bool:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).is_empty()
		TYPE_INT:
			return int(value) == 0
		TYPE_FLOAT:
			return is_zero_approx(value)
		TYPE_BOOL:
			return not value
		TYPE_ARRAY:
			return (value as Array).is_empty()
		TYPE_DICTIONARY:
			return (value as Dictionary).is_empty()
	return false


func _should_watch(event_name: StringName) -> bool:
	if ignore_events.has(event_name):
		return false
	return only_events.is_empty() or only_events.has(event_name)


func _known_events() -> Array[StringName]:
	if _bus != null and _bus.has_method("get_registered_event_names"):
		var names: Variant = _bus.call("get_registered_event_names")
		if names is Array:
			var typed: Array[StringName] = []
			typed.assign(names)
			return typed
	return []


func _detach() -> void:
	if _bus != null and _bus.has_method("unsubscribe"):
		for event_name in _watched:
			_bus.call("unsubscribe", event_name, _on_event)
	_watched.clear()


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
