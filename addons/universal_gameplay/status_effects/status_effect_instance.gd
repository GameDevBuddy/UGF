class_name StatusEffectInstance
extends RefCounted
## One live application of a [StatusEffectDefinition] to one entity.
##
## The definition is the shared immutable content; this is the per-application
## mutable state -- how long is left, how many stacks, who applied it. Keeping
## them apart is rule 2 and rule 16: a hundred burning enemies point at one
## [code]effect_burning.tres[/code] and each has its own timer.

## The content this is an application of.
var definition: StatusEffectDefinition = null

## Seconds left. Meaningless while [member permanent] is set.
var remaining: float = 0.0

## Whether this application never expires on its own.
##
## An explicit flag rather than a negative [member remaining], because those
## two states are not the same thing and encoding them in one number makes
## them collide: a five-second effect ticked by six seconds lands at -1, which
## a sentinel scheme reads as "permanent". The effect then never expires and
## its modifiers stay on the target forever.
var permanent: bool = false

## How many times this has stacked, always at least 1.
var stacks: int = 1

## Who applied it. Kept for kill attribution: a poison that finishes someone off
## should credit whoever poisoned them, not the corpse.
var instigator: Node = null

## Modifiers this application put on the target, so removal takes back exactly
## these and not another application's.
var applied_modifiers: Array[StatModifier] = []

## Seconds since the last periodic application.
var since_tick: float = 0.0


static func create(
	p_definition: StatusEffectDefinition, p_instigator: Node = null
) -> StatusEffectInstance:
	var instance := StatusEffectInstance.new()
	instance.definition = p_definition
	instance.instigator = p_instigator
	instance.permanent = p_definition.is_permanent()
	instance.remaining = 0.0 if instance.permanent else p_definition.duration
	return instance


func get_id() -> StringName:
	return definition.id if definition != null else &""


func is_permanent() -> bool:
	return permanent


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


## Restarts the duration. What [constant StatusEffectDefinition.Stacking.REFRESH]
## does on re-application.
func refresh() -> void:
	if definition != null and not definition.is_permanent():
		remaining = definition.duration


## Adds a stack up to the definition's cap. Returns true if one was added.
func add_stack() -> bool:
	if definition == null or stacks >= definition.max_stacks:
		return false
	stacks += 1
	return true


func remove_stack() -> bool:
	if stacks <= 1:
		return false
	stacks -= 1
	return true


## Fraction of the original duration left, 1 to 0. What an icon's cooldown
## sweep wants. Permanent effects report 1.
func get_fraction_remaining() -> float:
	if is_permanent() or definition == null or definition.duration <= 0.0:
		return 1.0
	return clampf(remaining / definition.duration, 0.0, 1.0)


## Damage this application deals per second, scaled by stacks.
func get_damage_per_second() -> float:
	if definition == null:
		return 0.0
	return definition.damage_per_second * float(stacks)


func _to_string() -> String:
	if is_permanent():
		return "%s x%d (permanent)" % [get_id(), stacks]
	return "%s x%d (%.1fs left)" % [get_id(), stacks, remaining]
