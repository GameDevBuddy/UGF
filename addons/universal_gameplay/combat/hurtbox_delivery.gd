class_name HurtboxDelivery
extends AttackDelivery
## An attack that hits whatever its weapon is currently touching.
##
## Implementation Plan 14 lists four hit-detection strategies: Area3D, shape
## cast, weapon hurtbox and animation event. [MeleeDelivery] is the first two
## -- an arc queried against the world from the attacker. This is the third:
## the blade itself carries an [Area3D] and whatever is inside it when the
## window opens is what got hit.
##
## [b]Why it is a separate delivery rather than a flag on the melee one.[/b]
## An arc is geometry the attacker computes; a hurtbox is geometry the
## animation moves. They disagree in the case that matters -- a sweeping
## overhead where the arc says "everything in front" and the blade says "the
## one thing the blade actually passed through" -- and a flag would make one of
## those two silently wrong (rule 23 cuts both ways: no abstraction without
## reuse, and no configuration flag standing in for two different behaviours).
##
## The hurtbox is handed over per attack in
## [member AttackContext.extras], keyed [code]hurtbox[/code], because the node
## belongs to whatever is swinging and a shared definition must never hold a
## reference to one instance of it (rule 2).

## Key the swinging entity puts its Area3D under in [member AttackContext.extras].
const HURTBOX_KEY: StringName = &"hurtbox"

## Most things the box can hit in one swing. Zero is unlimited.
@export_range(0, 64) var max_targets: int = 0

## Ignores anything already hit by this swing.
##
## On by default because a hurtbox stays overlapping for the length of the
## animation, and a window that resolved more than once would hit the same
## target every frame it was open.
@export var unique_targets: bool = true

## Damage multiplier for everything after the first target.
@export_range(0.0, 1.0, 0.01) var falloff_per_target: float = 1.0


## Reads the box handed over in the context rather than querying the world.
##
## [param provider] is unused and that is the point: a hurtbox already knows
## what it is touching, so there is nothing to ask the world. The parameter
## stays because it is the contract every delivery shares.
func resolve(context: AttackContext, _provider: HitProvider) -> Array[CombatHit]:
	var hits: Array[CombatHit] = []
	var box: Variant = context.extras.get(HURTBOX_KEY)
	if not (box is Area3D):
		# No box means no hits, not a crash. An entity whose weapon has no
		# hurtbox swings through the air, which is the honest result.
		return hits
	var area := box as Area3D

	var seen: Dictionary[int, bool] = {}
	var origin := area.global_position
	for body in _overlapping(area):
		if body == null or not is_instance_valid(body):
			continue
		if context.exclude.has(body):
			continue

		var root := _entity_root_of(body)
		if unique_targets:
			if seen.has(root.get_instance_id()):
				continue
			seen[root.get_instance_id()] = true

		var hit := CombatHit.create(
			root, body.global_position, Vector3.UP, origin.distance_to(body.global_position)
		)
		hit.collider = body
		hit.damage_scale = pow(falloff_per_target, float(hits.size()))
		hits.append(hit)

		if max_targets > 0 and hits.size() >= max_targets:
			break
	return hits


## The reach a hurtbox has is the reach of the animation that moves it, which
## nothing here can know. Reported as zero so an AI deciding whether to close
## in falls back on the attack's own range rather than trusting a number this
## class would have to invent.
func get_maximum_range() -> float:
	return 0.0


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if falloff_per_target <= 0.0 and max_targets != 1:
		result.add_warning(
			&"hurtbox.zero_falloff",
			(
				"Every target after the first takes no damage, which is a "
				+ "single-target attack written the long way around."
			),
			resource_path,
			"falloff_per_target"
		)
	return result


func _overlapping(area: Area3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	# Areas as well as bodies: a character built from an Area3D hurtbox rather
	# than a physics body is a perfectly ordinary way to build one, and a
	# delivery that only saw bodies would miss half the entities in some games.
	for body in area.get_overlapping_bodies():
		found.append(body)
	for other in area.get_overlapping_areas():
		found.append(other)
	return found


## Walks up to the entity a collider belongs to, so a hit on somebody's shin
## reports the character rather than the shin.
func _entity_root_of(node: Node3D) -> Node3D:
	var current: Node = node
	while current != null:
		if DefinitionBinder.is_entity_root(current) and current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return node
