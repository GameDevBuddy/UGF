extends FrameworkEvent
## The player said something that matters.
##
## The cross-feature half of the M8 exit gate. A mission that turns on which
## answer was given subscribes to this and never reads a dialogue's internals
## to do it -- which is exactly what Implementation Plan 18 asks for.
##
## No class_name, for the same reason [FrameworkEvent] subclasses generally
## have none: they are published by name and constructed by their adapter.

var dialogue_id: StringName = &""
var node_id: StringName = &""
var choice_id: StringName = &""
var tags: Array[StringName] = []
var listener: Node = null


static func create(
	p_dialogue_id: StringName,
	p_node_id: StringName,
	p_choice: DialogueChoice,
	p_speaker: Node = null,
	p_listener: Node = null
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/dialogue/dialogue_choice_event.gd"
	) as GDScript).new()
	event.dialogue_id = p_dialogue_id
	event.node_id = p_node_id
	event.source = p_speaker
	event.listener = p_listener
	if p_choice != null:
		event.choice_id = p_choice.id
		event.tags = p_choice.tags.duplicate()
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_DIALOGUE_CHOICE


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func describe() -> String:
	return "choice '%s' taken in '%s'" % [choice_id, dialogue_id]
