class_name MemoryEntry
extends RefCounted
## What an NPC remembers about one other entity.
##
## The reason an NPC can search where you went rather than losing you the
## instant you break line of sight. Holds the last known position, how long ago
## that was, and whether the target is visible right now -- which are three
## different questions and are answered separately on purpose.

## The entity remembered. May become invalid: check [method is_valid].
var target: Node = null

## Where it was last perceived.
var last_known_position: Vector3 = Vector3.ZERO

## Which way it was last seen heading, for predicting where it went.
var last_known_velocity: Vector3 = Vector3.ZERO

## Seconds since it was last perceived. Zero while it is in view.
var time_since_seen: float = 0.0

## Seconds it has been continuously perceived, reset when contact breaks. What
## a notice time is measured against.
var time_in_view: float = 0.0

## Whether it is perceived right now, as opposed to merely remembered.
var visible: bool = false

## Whether the notice time has elapsed. An entity in view but not yet noticed
## is what makes sneaking past a guard possible.
var noticed: bool = false

## How dangerous it looked when last perceived.
var threat: float = 0.0

## How it was perceived, for a brain that treats a noise differently from a
## sighting.
var heard: bool = false


static func create(p_target: Node, p_threat: float = 1.0) -> MemoryEntry:
	var entry := MemoryEntry.new()
	entry.target = p_target
	entry.threat = p_threat
	return entry


func is_valid() -> bool:
	return target != null and is_instance_valid(target)


## Records a sighting this frame.
func see(position: Vector3, p_threat: float, delta: float) -> void:
	if not visible:
		time_in_view = 0.0
	last_known_velocity = (position - last_known_position) / delta if delta > 0.0 else Vector3.ZERO
	last_known_position = position
	threat = p_threat
	visible = true
	heard = false
	time_since_seen = 0.0
	time_in_view += delta


## Records a noise. A heard target is remembered at the noise's position and is
## never "visible": you know something is there, not where it is looking.
func hear(position: Vector3) -> void:
	last_known_position = position
	last_known_velocity = Vector3.ZERO
	time_since_seen = 0.0
	visible = false
	heard = true
	# A noise is noticed immediately. There is no gradual "did I hear that".
	noticed = true


## Records that it was not perceived this frame.
func lose(delta: float) -> void:
	visible = false
	time_in_view = 0.0
	time_since_seen += delta


## Whether this memory has decayed past [param duration] seconds.
func is_stale(duration: float) -> bool:
	return not visible and time_since_seen >= duration


## Where to search for it now, extrapolated from where it was heading.
##
## Capped rather than unbounded: an NPC that projects a sprint five seconds
## forward searches a wall on the far side of the map.
func predict_position(max_lead: float = 1.5) -> Vector3:
	if visible:
		return last_known_position
	return last_known_position + last_known_velocity * minf(time_since_seen, max_lead)


func _to_string() -> String:
	var name := target.name if is_valid() else "<gone>"
	return "MemoryEntry(%s visible=%s noticed=%s age=%.1fs)" % [
		name, visible, noticed, time_since_seen
	]
