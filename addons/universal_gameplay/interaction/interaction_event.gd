extends FrameworkEvent
## Somebody finished doing something to something.
##
## Carries the interaction's id, the verb, and both parties, so a mission
## objective matching "open the vault door" holds no reference to the door and
## keeps working when it is unloaded (rule 32).
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

## Definition id of the interaction that completed.
var interaction_id: StringName = &""

## Its verb -- open, take, hotwire -- for an objective matching a class of
## action rather than one specific interaction.
var verb: StringName = &""

## Tags from the interaction's definition, for an objective matching
## [code]interaction.theft[/code] rather than one id.
var tags: Array[StringName] = []

## Who did it.
var interactor: Node = null

## What it was done to.
var target: Node = null


static func create(context: InteractionContext) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/interaction/interaction_event.gd"
	) as GDScript).new()
	event.interactor = context.interactor
	event.target = context.target
	event.source = context.interactor
	if context.definition != null:
		event.interaction_id = context.definition.id
		event.verb = context.definition.verb
		event.tags = context.definition.tags.duplicate()
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_INTERACTION_COMPLETED


func describe() -> String:
	return "interaction_completed: %s on %s" % [
		interaction_id, target.name if target != null else "<unknown>"
	]
