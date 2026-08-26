class_name FrameworkEvent
extends RefCounted
## Base class for a cross-feature fact published on the EventBus.
##
## An event is a statement that something [i]has happened[/i], addressed to
## nobody in particular (rule 6). It is not a command. If you know who should
## react, call them directly instead -- that is rule 5, and it is the line that
## keeps the bus from becoming a global router.
##
## Events are immutable by convention: a subscriber must never mutate one,
## because the next subscriber will see the change.

## The node the fact happened to or originated from. May be null for facts
## with no scene presence, e.g. a world-state change.
var source: Node = null

## Engine milliseconds at construction, for the debug event monitor's timeline
## (Implementation Plan 29).
var timestamp_ms: int = 0


func _init() -> void:
	timestamp_ms = Time.get_ticks_msec()


## The EventBus signal this event is published on. Subclasses must override it
## and return a constant from [GameplayNames]. The bus uses this to route the
## event, so a mismatch means the event is silently generic-only.
func get_event_name() -> StringName:
	return &""


## Short description for the debug event monitor.
func describe() -> String:
	return get_event_name() if get_event_name() != &"" else "<unnamed event>"


func _to_string() -> String:
	return "%s@%d" % [describe(), timestamp_ms]
