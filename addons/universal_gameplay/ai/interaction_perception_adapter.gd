class_name InteractionPerceptionAdapter
extends FrameworkComponent
## Tells an NPC's memory that somebody used something in front of it.
##
## The plan's interaction stimulus, and the reason a guard can react to a lock
## being picked rather than only to the thief being seen.
##
## [b]It listens to the bus, not to the interaction.[/b] An NPC cannot hold a
## reference to every door in the district, so the fact arrives as a broadcast
## and this adapter decides whether its own NPC was close enough to notice --
## which is the shape rule 5 asks for: facts are broadcast, and the listener
## decides whether it cares.
##
## Delete it and nothing else changes. That is what makes "NPCs notice
## interactions" a feature a project opts into per entity rather than a tax on
## every interaction in the world.

signal stimulus_recorded(interactor: Node, interaction_id: StringName)

## Where the facts go, wired at composition time (rule 20).
@export var perception: PerceptionComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

## How far away an interaction can be and still be noticed. Separate from
## sight range: a lock being picked is noticed by proximity and attention, not
## by a clean line to the lock itself.
@export_range(0.0, 200.0, 0.5, "or_greater") var notice_radius: float = 12.0

## Interaction verbs worth reacting to. Empty means all of them, which is
## rarely what a project wants: a guard that investigates every light switch
## is a guard nobody enjoys.
@export var verbs_of_interest: Array[StringName] = []

## Threat seeded for an interactor never seen before.
@export_range(0.0, 10.0, 0.1) var stimulus_threat: float = 1.0

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if perception == null:
		perception = _find(PerceptionComponent) as PerceptionComponent
	_bus = event_bus if event_bus != null else _find_bus()
	if _bus == null or not _bus.has_method("subscribe"):
		return
	if _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_INTERACTION_COMPLETED)
	_bus.call("subscribe", GameplayNames.EVENT_INTERACTION_COMPLETED, _on_interaction)


func _exit_tree() -> void:
	if _bus != null and _bus.has_method("unsubscribe"):
		_bus.call("unsubscribe", GameplayNames.EVENT_INTERACTION_COMPLETED, _on_interaction)


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus


func _on_interaction(event: FrameworkEvent) -> void:
	if perception == null or event == null:
		return
	var interactor: Node = event.get("interactor")
	if interactor == null or interactor == _entity_root():
		return

	var verb: StringName = event.get("verb")
	if not verbs_of_interest.is_empty() and not verbs_of_interest.has(verb):
		return

	var position := _position_of(interactor)
	if position == null:
		return
	if not _within_notice(position):
		return

	var interaction_id: StringName = event.get("interaction_id")
	perception.get_memory().witnessed_interaction(
		interactor, position, interaction_id, stimulus_threat
	)
	stimulus_recorded.emit(interactor, interaction_id)


func _within_notice(position: Vector3) -> bool:
	var here := _entity_root()
	if not (here is Node3D):
		# Nothing to measure from. Noticing everything would give a headless
		# test entity district-wide hearing, so it notices nothing instead.
		return false
	return (here as Node3D).global_position.distance_to(position) <= notice_radius


func _position_of(interactor: Node) -> Variant:
	if interactor is Node3D:
		return (interactor as Node3D).global_position
	return null


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


func _find(type: Variant) -> FrameworkComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child as FrameworkComponent
	return null


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus")
