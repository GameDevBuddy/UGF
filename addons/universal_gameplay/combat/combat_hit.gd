class_name CombatHit
extends RefCounted
## One thing an attack connected with.
##
## The unit every delivery strategy returns, whatever it is: a melee arc
## sweeping three bandits, a shotgun's eight pellets, a single rifle round, a
## grenade's blast. Combat resolves the geometry and produces these; turning
## one into a [DamageContext] is a separate step, which is what lets a
## non-damaging attack -- a shove, a taunt, a scan -- use the same pipeline.

## What was hit. The entity root when the collider belongs to one, so callers
## get the thing with health rather than its collision shape.
var target: Node = null

## The collider that actually stopped the query, for a hit-box that wants to
## multiply damage by where it landed.
var collider: Node = null

var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.ZERO

## Metres from the attack's origin. Read by range falloff.
var distance: float = 0.0

## Multiplier applied to the attack's damage for this particular hit: range
## falloff, a pellet that clipped the edge, a weak point. One means unmodified.
var damage_scale: float = 1.0


static func create(
	p_target: Node,
	p_position: Vector3 = Vector3.ZERO,
	p_normal: Vector3 = Vector3.ZERO,
	p_distance: float = 0.0
) -> CombatHit:
	var hit := CombatHit.new()
	hit.target = p_target
	hit.collider = p_target
	hit.position = p_position
	hit.normal = p_normal
	hit.distance = p_distance
	return hit


## The thing on the target that takes damage, or null when it takes none.
##
## A hit on scenery is a legitimate hit: it stops a bullet, it plays an impact,
## and it deals no damage to anything.
func get_receiver() -> DamageReceiverComponent:
	if target == null:
		return null
	for component in DefinitionBinder.collect_components(target):
		if component is DamageReceiverComponent:
			return component as DamageReceiverComponent
	return null


func is_damageable() -> bool:
	return get_receiver() != null


func _to_string() -> String:
	var name := target.name if target != null else "<nothing>"
	return "CombatHit(%s at %.2fm x%.2f)" % [name, distance, damage_scale]
