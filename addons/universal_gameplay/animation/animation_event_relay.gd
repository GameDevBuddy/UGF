class_name AnimationEventRelay
extends FrameworkComponent
## The one place an animation is allowed to talk back to gameplay.
##
## Implementation Plan 25 asks for animation events that open gameplay windows,
## and 14 lists "animation event" as a hit-detection strategy. Both need the
## same thing: a way for a keyframe to say "now" without the animation knowing
## what happens next.
##
## [b]This inverts the animation layer's usual direction, so it is deliberately
## the only file that does.[/b] [AnimationAdapter] is rule 21 as a class --
## presentation observes authority and never becomes one. A method-call track
## that reached into a combat component would make the animation the authority
## on when damage happens, which is exactly what rule 21 forbids and exactly
## what a frame-perfect fighting game needs. The relay is the compromise: the
## animation calls one method on one component that owns no gameplay state, and
## whoever cares subscribes.
##
## Wire it from an [AnimationPlayer] method-call track:
## [codeblock]
## AnimationEventRelay.fire("hit")
## [/codeblock]
##
## [b]It is optional, and what it drives must work without it.[/b] A combat
## component set to open its window on an animation event falls back to its
## authored timing when no relay ever fires, because a missing animation must
## not mean a sword that never connects (rule 31).

## Emitted for every event the animation fires.
signal event_fired(event_name: StringName, payload: Variant)

## Names this relay will pass on. Empty means all of them.
##
## A whitelist rather than a filter on the listener's side, because an
## animation shared between a dozen characters fires events most of them do not
## care about, and a listener that has to check is a listener that gets it
## wrong once.
@export var accepted_events: Array[StringName] = []

## Records what was fired, for a test and for a debug panel. Off in a release
## build, where nothing reads it.
@export var record_history: bool = false

var _history: Array[Dictionary] = []
var _subscribers: Dictionary[StringName, Array] = {}


## Called by the animation. The whole public surface an animation gets.
func fire(event_name: StringName, payload: Variant = null) -> void:
	if event_name == &"":
		return
	if not accepted_events.is_empty() and not accepted_events.has(event_name):
		return

	if record_history:
		_history.append({"event": event_name, "payload": payload})

	for handler in _subscribers.get(event_name, []):
		var callable: Callable = handler
		if callable.is_valid():
			callable.call(payload)
	event_fired.emit(event_name, payload)


## Registers interest in one event name.
##
## Kept alongside [signal event_fired] rather than instead of it: a component
## wanting exactly one event should not have to filter every other one, and a
## debug monitor wanting all of them should not have to enumerate names.
func subscribe(event_name: StringName, handler: Callable) -> void:
	if event_name == &"" or not handler.is_valid():
		return
	if not _subscribers.has(event_name):
		_subscribers[event_name] = [] as Array[Callable]
	if not _subscribers[event_name].has(handler):
		_subscribers[event_name].append(handler)


func unsubscribe(event_name: StringName, handler: Callable) -> void:
	if not _subscribers.has(event_name):
		return
	_subscribers[event_name].erase(handler)


func has_subscribers(event_name: StringName) -> bool:
	return not _subscribers.get(event_name, []).is_empty()


## What the animation has fired so far, when [member record_history] is on.
func get_history() -> Array[Dictionary]:
	return _history.duplicate()


func clear_history() -> void:
	_history.clear()


## Finds the relay on an entity, for a component wiring itself up.
static func find_on(entity: Node) -> AnimationEventRelay:
	if entity == null:
		return null
	for child in entity.get_children():
		if child is AnimationEventRelay:
			return child as AnimationEventRelay
	return null
