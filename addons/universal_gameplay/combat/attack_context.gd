class_name AttackContext
extends RefCounted
## Everything one swing or one shot knows about itself.
##
## Built by [CombatComponent], handed to a delivery strategy, and read back
## when hits become damage. The same role [InteractionContext] and
## [DamageContext] play: a value object that crosses module boundaries so
## neither end has to depend on the other.

## Who is attacking. The character, not the sword.
var instigator: Node = null

## The thing that physically deals it: a weapon component, a projectile, the
## instigator itself when unarmed. Becomes [member DamageContext.source].
var source: Node = null

## Which attack this is.
var attack: AttackDefinition = null

## Definition id of the weapon involved, for kill attribution and statistics.
var weapon_id: StringName = &""

## Where the attack comes from in world space: the muzzle, the shoulder, the
## camera. Not necessarily the instigator's own position.
var origin: Vector3 = Vector3.ZERO

## Where it is pointed. Normalised by the deliveries that need it.
var direction: Vector3 = Vector3.FORWARD

## Cone in degrees this shot goes into, supplied by the weapon's current
## spread. Melee ignores it.
var spread_degrees: float = 0.0

## Deterministic randomness for the attack. Injected rather than global so a
## test seeds it and a networked game can share the stream.
var rng: RandomNumberGenerator = null

## Nodes a query must not stop on: the attacker and its own colliders.
var exclude: Array[Node] = []

## Where a delivery that spawns something puts it. Null means a delivery that
## needs a world does nothing, which beats spawning into a freed tree.
var world: Node = null

## Free-form per-attack bag. Deliberately small.
var extras: Dictionary = {}


static func create(
	p_instigator: Node,
	p_attack: AttackDefinition,
	p_origin: Vector3 = Vector3.ZERO,
	p_direction: Vector3 = Vector3.FORWARD
) -> AttackContext:
	var context := AttackContext.new()
	context.instigator = p_instigator
	context.source = p_instigator
	context.attack = p_attack
	context.origin = p_origin
	context.direction = p_direction
	if p_instigator != null:
		var exclude: Array[Node] = [p_instigator]
		context.exclude = exclude
	return context


## The rng for this attack, creating a randomised one on first use so a caller
## that does not care about determinism does not have to supply one.
func get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng


## Turns a resolved hit into the damage that should land on it.
##
## Here rather than in the delivery, because every delivery produces the same
## shape of damage and the exit gate for this milestone is precisely that a
## sword and a rifle produce one [DamageContext].
func make_damage(hit: CombatHit) -> DamageContext:
	var amount := 0.0
	var tags: Array[StringName] = []
	if attack != null:
		amount = attack.damage * hit.damage_scale
		tags = attack.damage_tags.duplicate()
	var damage := DamageContext.create(amount, instigator, source, tags)
	damage.weapon_id = weapon_id
	damage.hit_position = hit.position
	damage.hit_normal = hit.normal
	return damage


func _to_string() -> String:
	var who := instigator.name if instigator != null else "<nobody>"
	var what := attack.get_debug_name() if attack != null else "<no attack>"
	return "AttackContext(%s: %s)" % [who, what]
