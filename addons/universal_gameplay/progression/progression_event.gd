extends FrameworkEvent
## Somebody got better at something.
##
## Carries the track and the level as plain values rather than the component,
## so a mission objective matching "reach level 5 in rifles" holds no reference
## to the character that did it and keeps working when they are unloaded
## (rule 32).
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

## The track that levelled.
var track_id: StringName = &""

## The level just reached.
var level: int = 0

## The level before this one, so a listener can see how far it jumped.
var previous_level: int = 0

## The character. A reference for a listener that wants it, never how the event
## is matched.
var actor: Node = null


static func create(
	p_actor: Node, p_track: StringName, p_level: int, p_previous: int
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/progression/progression_event.gd"
	) as GDScript).new()
	event.actor = p_actor
	event.source = p_actor
	event.track_id = p_track
	event.level = p_level
	event.previous_level = p_previous
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_LEVEL_GAINED


func describe() -> String:
	return "level_gained: %s reached %d on %s" % [
		actor.name if actor != null else "<unknown>", level, track_id
	]
