class_name DamagePipeline
extends RefCounted
## Turns requested damage into landed damage. Static, node-free, deterministic.
##
## [b]The order is fixed:[/b]
## [codeblock]
## immunity -> flat armour -> percentage resistance -> stat modifiers -> clamp
## [/codeblock]
## Flat armour before percentage, because the other way round makes armour
## worth more against big hits than small ones, which is backwards from what
## armour is for.
##
## "Damage is deterministic" is the M3 exit gate, and it is only checkable
## because this is a pure function: the same context and the same profile give
## the same number every time, with no node, no frame and no RNG. Variance --
## criticals, spread, falloff -- belongs to whoever builds the context, not
## here. A pipeline that rolled dice could not be tested and could not be
## replayed (Implementation Plan 27).


## Applies mitigation to [param context] and returns it, with
## [member DamageContext.final_amount] set to what will actually land.
##
## Mutates and returns the same context rather than copying, because the whole
## design of [DamageContext] is that one object travels the pipeline and
## whatever survives is what gets applied (rule 4).
static func mitigate(
	context: DamageContext,
	profile: ResistanceProfile = null,
	extra_resistance: float = 0.0
) -> DamageContext:
	if context == null:
		return null

	var amount := maxf(0.0, context.amount)

	if profile != null and profile.is_immune_to(context.tags):
		context.final_amount = 0.0
		return context

	if profile != null:
		amount = maxf(0.0, amount - profile.flat_armor)

	var resistance := extra_resistance
	if profile != null:
		resistance += profile.get_resistance_for(context.tags)
		resistance = minf(resistance, profile.maximum_resistance)
	else:
		resistance = clampf(resistance, -INF, 1.0)

	amount *= 1.0 - resistance
	context.final_amount = maxf(0.0, amount)
	return context


## What [param amount] would become under this profile, without a context.
##
## For UI that previews a hit and for balance tooling, neither of which should
## have to fabricate a [DamageContext] to ask a question.
static func preview(
	amount: float,
	tags: Array[StringName],
	profile: ResistanceProfile = null,
	extra_resistance: float = 0.0
) -> float:
	var context := DamageContext.create(amount, null, null, tags)
	return mitigate(context, profile, extra_resistance).final_amount


## Health after applying a mitigated context, clamped at zero.
static func apply_to(current_health: float, context: DamageContext) -> float:
	if context == null:
		return current_health
	return maxf(0.0, current_health - maxf(0.0, context.final_amount))


## Whether a mitigated context would reduce [param current_health] to zero.
static func is_lethal(current_health: float, context: DamageContext) -> bool:
	if context == null or current_health <= 0.0:
		return false
	return context.final_amount >= current_health
