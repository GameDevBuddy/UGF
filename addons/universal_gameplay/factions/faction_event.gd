extends FrameworkEvent
## Somebody's opinion changed enough to matter.
##
## Published only on band crossings -- neutral to hostile, wary to friendly --
## rather than on every point of standing, because that is when behaviour
## changes and a bus carrying every reputation tick would be noise (rule 6).
##
## No class_name: events are constructed by the adapter that publishes them
## and matched by name on the bus.

## Whose opinion changed.
var faction: StringName = &""

## Who it is about: another faction, or an actor.
var other: StringName = &""

var attitude: AttitudeSolver.Attitude = AttitudeSolver.Attitude.NEUTRAL

## The attitude as a semantic name, for an objective matching on it without
## depending on the enum.
var attitude_name: StringName = &"attitude.neutral"


static func create(
	p_faction: StringName, p_other: StringName, p_attitude: AttitudeSolver.Attitude
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/factions/faction_event.gd"
	) as GDScript).new()
	event.faction = p_faction
	event.other = p_other
	event.attitude = p_attitude
	event.attitude_name = AttitudeSolver.to_name(p_attitude)
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_ATTITUDE_CHANGED


func is_hostile() -> bool:
	return AttitudeSolver.is_hostile(attitude)


func describe() -> String:
	return "%s now %s towards %s" % [faction, attitude_name, other]
