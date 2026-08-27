class_name DefenseDamageAdapter
extends FrameworkComponent
## Lets a defender's block, parry or dodge affect what actually lands.
##
## The seam between Combat and Health, and the reason neither imports the
## other. [DamageReceiverComponent] announces an incoming blow and offers a
## scale; [DefenseComponent] decides what that scale is. Health never learns
## what a parry is, Combat never learns what hit points are, and deleting this
## component leaves both working -- the defender simply takes every blow in
## full, which is the honest behaviour for a character with no defence
## installed (rule 9, rule 10).
##
## It also delivers the parry's reward. A parry staggers the attacker, and the
## attacker's own [DefenseComponent] is what has to be told -- so this adapter
## is the one place that reaches across to another entity, and it does it
## through that entity's own public method rather than by writing its state.

## Emitted when this adapter scaled a blow, for debug tooling watching it.
signal mitigated(context: DamageContext, scale: float)

## The defence to consult, wired at composition time (rule 20).
@export var defense: DefenseComponent

## The receiver to observe. Resolved from the entity when left null.
@export var receiver: DamageReceiverComponent


func initialize(context: EntityContext) -> void:
	super(context)
	if defense == null:
		defense = _find(DefenseComponent) as DefenseComponent
	if receiver == null:
		receiver = _find(DamageReceiverComponent) as DamageReceiverComponent

	if receiver != null and not receiver.damage_incoming.is_connected(_on_incoming):
		receiver.damage_incoming.connect(_on_incoming)
	if defense != null and not defense.parried.is_connected(_on_parried):
		defense.parried.connect(_on_parried)


func _exit_tree() -> void:
	if receiver != null and receiver.damage_incoming.is_connected(_on_incoming):
		receiver.damage_incoming.disconnect(_on_incoming)
	if defense != null and defense.parried.is_connected(_on_parried):
		defense.parried.disconnect(_on_parried)


func _on_incoming(context: DamageContext) -> void:
	if defense == null or receiver == null:
		return
	var scale := defense.mitigate(context)
	if scale < 1.0:
		receiver.scale_incoming(scale)
		mitigated.emit(context, scale)


## Staggers whoever was parried.
##
## Duck-typed rather than cast: the attacker may be an NPC with a defence
## component, a turret with none, or a projectile's source that is not a
## character at all. A parry against something that cannot be staggered still
## nullifies the blow; it just does not open anything up.
func _on_parried(attacker: Node, seconds: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	for child in attacker.get_children():
		if child.has_method("stagger"):
			child.call("stagger", seconds)
			return


func _find(type: Variant) -> FrameworkComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child as FrameworkComponent
	return null
