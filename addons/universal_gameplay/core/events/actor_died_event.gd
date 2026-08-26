class_name ActorDiedEvent
extends FrameworkEvent
## Published when an actor's health reaches zero.
##
## This is the framework's canonical example of why the bus exists. Missions,
## loot, reputation and crime all care that something died, and Combat should
## know about none of them (Implementation Plan 9).

## The actor that died. Mirrors [member FrameworkEvent.source].
var actor: Node = null

## The damage that killed it. Null when death had no damage cause, e.g. a
## scripted death or a survival need bottoming out.
var context: DamageContext = null


static func create(p_actor: Node, p_context: DamageContext = null) -> ActorDiedEvent:
	var event := ActorDiedEvent.new()
	event.actor = p_actor
	event.source = p_actor
	event.context = p_context
	return event


func get_event_name() -> StringName:
	return GameplayNames.EVENT_ACTOR_DIED


## The actor credited with the kill, or null when nothing was.
func get_instigator() -> Node:
	return context.instigator if context != null else null


func describe() -> String:
	var actor_name := actor.name if actor != null else "<unknown>"
	var instigator := get_instigator()
	if instigator != null:
		return "actor_died: %s (by %s)" % [actor_name, instigator.name]
	return "actor_died: %s" % actor_name
