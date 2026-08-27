extends FrameworkEvent
## Somebody took a perk.
##
## Separate from the level event rather than a field on it, because a mission
## matching "unlock Master Locksmith" and one matching "reach level 10" are
## asking different questions, and one event with a mode field would make every
## matcher check the mode first.
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

var skill_id: StringName = &""
var track_id: StringName = &""
var actor: Node = null


static func create(p_actor: Node, p_skill: StringName, p_track: StringName) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/progression/skill_unlocked_event.gd"
	) as GDScript).new()
	event.actor = p_actor
	event.source = p_actor
	event.skill_id = p_skill
	event.track_id = p_track
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_SKILL_UNLOCKED


func describe() -> String:
	return "skill_unlocked: %s took %s" % [
		actor.name if actor != null else "<unknown>", skill_id
	]
