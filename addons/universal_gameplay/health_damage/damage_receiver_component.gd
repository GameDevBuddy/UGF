class_name DamageReceiverComponent
extends FrameworkComponent
## The entry point for damage, and the only place mitigation happens.
##
## Split from [HealthComponent] on purpose. Health owns one number; this owns
## the question of how much of an incoming hit becomes a change to that number.
## Keeping them apart means a destructible crate can have health and no
## resistances, a shielded target can have resistances that change without
## health knowing, and the mitigation order stays in one testable place
## (rule 4).
##
## Anything that deals damage calls [method receive] here rather than reaching
## for health directly. That is rule 5 -- a targeted command to a known
## capability -- and it is what lets armour, shields and immunity exist without
## every weapon in the game knowing about them.

## Emitted after mitigation, before health is touched. Carries the context with
## [member DamageContext.final_amount] already reduced, so a shield effect or a
## damage-number popup sees what will actually land.
signal damage_received(context: DamageContext)
## Emitted when mitigation removed the hit entirely.
signal damage_blocked(context: DamageContext)

## Armour and resistances. Takes precedence over the definition's profile.
@export var profile_override: ResistanceProfile

## Health this forwards mitigated damage to, wired at composition time.
@export var health: HealthComponent

## Optional stats source for a resistance stat that adds to the profile, so a
## buff can grant resistance without editing a shared resource.
@export var stats: StatsComponent

## Stat id read for additional percentage resistance. Blank uses none.
@export var resistance_stat: StringName = &"stat.resistance"

var _profile: ResistanceProfile = null


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if health == null:
		health = _find_health()


## Mitigates [param context] and applies what survives to health.
##
## Returns the health component's result, so a caller learns whether the damage
## landed, was refused because the target is already dead, or was absorbed.
func receive(context: DamageContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(
			&"damage.null_context", "Cannot receive null damage."
		)

	DamagePipeline.mitigate(context, _profile, _get_extra_resistance())

	if not context.is_effective():
		damage_blocked.emit(context)
		if health != null:
			health.damage_absorbed.emit(context)
		return FrameworkResult.ok(0.0)

	damage_received.emit(context)

	if health == null:
		# A receiver with no health is not broken: a shield generator or a
		# destructible prop may care about being hit without having hit points.
		return FrameworkResult.ok(context.final_amount)
	return health.apply_damage(context)


## Convenience for callers that have an amount and tags rather than a context.
func receive_amount(
	amount: float,
	tags: Array[StringName] = [],
	instigator: Node = null,
	source: Node = null
) -> FrameworkResult:
	return receive(DamageContext.create(amount, instigator, source, tags))


## What [param amount] would become against this entity, without applying it.
func preview(amount: float, tags: Array[StringName] = []) -> float:
	return DamagePipeline.preview(amount, tags, _profile, _get_extra_resistance())


func get_profile() -> ResistanceProfile:
	return _profile


func is_immune_to(tags: Array[StringName]) -> bool:
	return _profile != null and _profile.is_immune_to(tags)


# --- Internals ------------------------------------------------------------

func _get_extra_resistance() -> float:
	if stats == null or resistance_stat == &"" or not stats.has_stat(resistance_stat):
		return 0.0
	return stats.get_value(resistance_stat, 0.0)


## Read by property name rather than by casting to a character definition, so a
## vehicle or a world object with its own definition type can be damageable
## without Health importing another module's types (rule 9).
func _resolve_profile() -> ResistanceProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "resistances" in definition:
		var candidate: Variant = definition.get("resistances")
		if candidate is ResistanceProfile:
			return candidate as ResistanceProfile
	return null


## Falls back to finding health on the same entity when it was not wired.
##
## Tree archaeology is what rule 22 forbids, and this is the narrow exception:
## the search is scoped to this entity's own components through the binder, it
## stops at nested entity roots, and it only runs when composition did not
## already answer the question. The export remains the documented way.
func _find_health() -> HealthComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is HealthComponent:
			return component as HealthComponent
	return null
