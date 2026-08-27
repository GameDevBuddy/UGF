extends FrameworkEvent
## A conversation ended, and how.
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus, not referenced globally.
##
## Carries ids rather than nodes. A mission reacting to "the player accepted
## the job" should not hold a reference to the NPC who offered it, because that
## NPC may be dead, unloaded or replaced by the time the mission is checked
## (rule 22, rule 32).

var dialogue_id: StringName = &""
var outcome: StringName = &""
var speaker_id: StringName = &""
var listener: Node = null


static func create(
	p_dialogue_id: StringName,
	p_outcome: StringName,
	p_speaker: Node = null,
	p_listener: Node = null
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/dialogue/dialogue_event.gd"
	) as GDScript).new()
	event.dialogue_id = p_dialogue_id
	event.outcome = p_outcome
	event.source = p_speaker
	event.listener = p_listener
	event.speaker_id = _identify(p_speaker)
	return event


## The speaker's save id when it has one, so a mission can name who said it
## after the NPC is gone. Blank rather than a scene path: paths are an
## implementation detail (rule 32).
static func _identify(node: Node) -> StringName:
	if node == null:
		return &""
	for child in node.get_children():
		if child is PersistentIdentity:
			return (child as PersistentIdentity).get_persistent_id()
	return &""


func get_event_name() -> StringName:
	return GameplayNames.EVENT_DIALOGUE_COMPLETED


func describe() -> String:
	return "dialogue '%s' ended as '%s'" % [dialogue_id, outcome]
