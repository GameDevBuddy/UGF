class_name DamagePerceptionAdapter
extends FrameworkComponent
## Tells an NPC's memory who just hurt it.
##
## The plan's [code]damaged_by[/code] perception fact. It is an adapter rather
## than a line inside [PerceptionComponent] because it is the seam between two
## modules: Perception must not know what a [DamageContext] is, and Health must
## not know what a memory is (rule 9). Delete this and both still work; the NPC
## simply stands there being shot without ever looking round, which is the
## honest failure mode for a module nobody installed.
##
## [b]Being shot needs no sight line.[/b] Damage is recorded whether or not the
## attacker is visible, which is what makes fighting back from cover possible
## and is exactly why this is a perception fact rather than a combat one.

signal attacker_recorded(attacker: Node, amount: float)

## Where the facts go, wired at composition time (rule 20).
@export var perception: PerceptionComponent

## What to listen to. Resolved from the entity when left null.
@export var receiver: DamageReceiverComponent

## Threat seeded for an attacker never seen before -- an ambush. High by
## default: something that shot you unseen has earned the attention.
@export_range(0.0, 10.0, 0.1) var unseen_attacker_threat: float = 2.0


func initialize(context: EntityContext) -> void:
	super(context)
	if perception == null:
		perception = _find(PerceptionComponent) as PerceptionComponent
	if receiver == null:
		receiver = _find(DamageReceiverComponent) as DamageReceiverComponent
	if receiver != null and not receiver.damage_received.is_connected(_on_damaged):
		receiver.damage_received.connect(_on_damaged)


func _exit_tree() -> void:
	if receiver != null and receiver.damage_received.is_connected(_on_damaged):
		receiver.damage_received.disconnect(_on_damaged)


func _on_damaged(context: DamageContext) -> void:
	if perception == null or context == null or context.instigator == null:
		return
	# Self-inflicted damage is not an attacker. Falling, poison and standing in
	# your own fire would otherwise make an NPC hunt itself forever.
	if context.instigator == _entity_root():
		return

	var position := _position_of(context)
	perception.get_memory().damaged_by(
		context.instigator, position, context.final_amount, unseen_attacker_threat
	)
	attacker_recorded.emit(context.instigator, context.final_amount)


## Where to remember the attacker as being.
##
## The attacker's own position when it has one, because that is where to look;
## the hit position only says where the bullet landed, which for anything
## ranged is on us rather than on them.
func _position_of(context: DamageContext) -> Vector3:
	if context.instigator is Node3D:
		return (context.instigator as Node3D).global_position
	return context.hit_position


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
