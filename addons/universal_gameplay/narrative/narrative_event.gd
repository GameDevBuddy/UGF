extends FrameworkEvent
## The story changed: a flag moved, or a counter did.
##
## One event class for both, because the payload is the same shape and the
## name is what a subscriber matches on. Published so an objective can count
## "the alarm was raised" without Missions importing Narrative, and so a
## mission chain can be authored entirely as flags.
##
## No class_name: events are constructed by the adapter that publishes them.

var name_override: StringName = &""

## The flag or counter that changed.
var key: StringName = &""

## Its new value: a bool for a flag, a number for a counter.
var value: Variant = null

## What it was before, for an objective interested in a direction of travel.
var previous: Variant = null


static func create(
	p_event_name: StringName,
	p_key: StringName,
	p_value: Variant,
	p_previous: Variant = null
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/narrative/narrative_event.gd"
	) as GDScript).new()
	event.name_override = p_event_name
	event.key = p_key
	event.value = p_value
	event.previous = p_previous
	return event


func get_event_name() -> StringName:
	return name_override


func describe() -> String:
	return "%s: %s = %s" % [name_override, key, str(value)]
