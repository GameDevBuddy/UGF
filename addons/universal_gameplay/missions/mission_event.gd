extends FrameworkEvent
## A mission started, finished, or ticked an objective off.
##
## One event class for four names rather than four near-identical ones: the
## payload is the same three ids in every case, and the name is what a
## subscriber matches on (rule 23).
##
## Missions publishing mission facts is what makes chains work: the mission
## that unlocks after this one is an objective counting
## [constant GameplayNames.EVENT_MISSION_COMPLETED] with a matcher on the id,
## and Missions needs to know nothing about which mission that is.
##
## No class_name: events are constructed by the service that publishes them
## and matched by name on the bus.

var name_override: StringName = &""
var mission_id: StringName = &""
var objective_id: StringName = &""
var subject: Node = null


static func create(
	p_event_name: StringName,
	p_mission_id: StringName,
	p_objective_id: StringName = &"",
	p_subject: Node = null
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/missions/mission_event.gd"
	) as GDScript).new()
	event.name_override = p_event_name
	event.mission_id = p_mission_id
	event.objective_id = p_objective_id
	event.subject = p_subject
	event.source = p_subject
	return event


func get_event_name() -> StringName:
	return name_override


func describe() -> String:
	if objective_id != &"":
		return "%s: %s / %s" % [name_override, mission_id, objective_id]
	return "%s: %s" % [name_override, mission_id]
