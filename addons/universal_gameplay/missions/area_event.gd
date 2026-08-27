extends FrameworkEvent
## Something entered or left a named place.
##
## The "ReachArea" objective of Implementation Plan 19, expressed as an event
## so Missions never learns what an [Area3D] is. Areas are named
## semantically -- [code]area.docks[/code] -- rather than by node path, so a
## mission survives the level being rebuilt around it (rule 32).
##
## No class_name: events are constructed by the trigger that publishes them.

## Semantic name of the place.
var area_id: StringName = &""

## What entered or left. The entity root, not its collider.
var body: Node = null

## False when this is a departure.
var entered: bool = true

var tags: Array[StringName] = []


static func create(
	p_area_id: StringName,
	p_body: Node,
	p_entered: bool,
	p_tags: Array[StringName] = []
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/missions/area_event.gd"
	) as GDScript).new()
	event.area_id = p_area_id
	event.body = p_body
	event.entered = p_entered
	event.source = p_body
	event.tags = p_tags.duplicate()
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_AREA_ENTERED


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func describe() -> String:
	var who := body.name if body != null else "<something>"
	return "area_%s: %s %s" % ["entered" if entered else "left", who, area_id]
