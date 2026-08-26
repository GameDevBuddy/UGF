class_name DamageContext
extends RefCounted
## Describes one damage application, start to finish.
##
## The amount lives here rather than as a separate argument so there is exactly
## one source of truth for it (rule 4). Every stage of the pipeline -- armour,
## resistance, status effects, faction rules -- reads and rewrites this one
## object, and whatever survives to the end is what the health component
## applies.
##
## Core owns this type because damage crosses module boundaries: Weapons
## produces it, Health consumes it, Factions and Missions observe its outcome.
## None of those modules should have to depend on another to speak about it.

## Damage to apply, before any mitigation. Never negative; healing is its own
## operation, not negative damage.
var amount: float = 0.0

## The actor responsible. A turret's instigator is whoever placed it, not the
## turret, which is what makes kill attribution work.
var instigator: Node = null

## The thing that physically dealt the damage: weapon, projectile, hazard.
var source: Node = null

## Semantic damage vocabulary, e.g. &"damage.fire". Resistances and status
## effects match on these instead of on an enum Core would have to own.
var tags: Array[StringName] = []

## Definition id of the weapon involved, when there was one.
var weapon_id: StringName = &""

var hit_position: Vector3 = Vector3.ZERO
var hit_normal: Vector3 = Vector3.ZERO

## Set by the pipeline once mitigation has run, so observers can report what
## actually landed rather than what was requested.
var final_amount: float = 0.0
## True when the damage reduced its target to zero health.
var was_lethal: bool = false


static func create(
	p_amount: float,
	p_instigator: Node = null,
	p_source: Node = null,
	p_tags: Array[StringName] = []
) -> DamageContext:
	var context := DamageContext.new()
	context.amount = maxf(0.0, p_amount)
	context.instigator = p_instigator
	context.source = p_source
	context.tags = p_tags.duplicate()
	context.final_amount = context.amount
	return context


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_any_tag(any_of: Array[StringName]) -> bool:
	for tag in any_of:
		if tags.has(tag):
			return true
	return false


## True when there is anything left to apply. A context fully absorbed by
## armour is not an error, it is a zero-damage hit that still happened.
func is_effective() -> bool:
	return final_amount > 0.0


func _to_string() -> String:
	return "DamageContext(amount=%.2f final=%.2f tags=%s)" % [amount, final_amount, str(tags)]
