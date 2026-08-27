class_name HeatProfile
extends Resource
## The wanted ladder and how quickly it cools.
##
## One profile per law faction, so the city police and the desert militia can
## have completely different patience from the same code (rule 11).

## The rungs, in any order. Sorted by threshold when resolved, so authoring
## order cannot silently change behaviour.
@export var tiers: Array[WantedTier] = []

@export_group("Decay")
## Heat lost per second once the cooldown delay has passed.
@export_range(0.0, 1000.0, 0.1, "or_greater") var decay_per_second: float = 1.0

## Heat above which decay stops entirely. Zero always cools. Non-zero is a
## crime the law does not forget without an arrest or a bribe.
@export_range(0.0, 100000.0, 1.0, "or_greater") var permanent_above: float = 0.0

@export_group("Ceiling")
## Most heat one actor can carry with this faction. Zero is unbounded.
@export_range(0.0, 100000.0, 1.0, "or_greater") var maximum_heat: float = 0.0


func has_tiers() -> bool:
	return not tiers.is_empty()


## The rungs sorted low to high. Built on demand rather than cached, because
## caching mutable derived state on a shared definition is exactly what rule 2
## forbids — two entities using one profile would race on it.
func get_sorted_tiers() -> Array[WantedTier]:
	var sorted: Array[WantedTier] = []
	for tier in tiers:
		if tier != null:
			sorted.append(tier)
	sorted.sort_custom(
		func(a: WantedTier, b: WantedTier) -> bool: return a.threshold < b.threshold
	)
	return sorted


## The tier [param heat] falls in, or null below the lowest rung.
func resolve_tier(heat: float) -> WantedTier:
	var found: WantedTier = null
	for tier in get_sorted_tiers():
		if heat >= tier.threshold:
			found = tier
		else:
			break
	return found


## Where the tier [param heat] is in would end. Used to report "how close to
## the next star", which every wanted UI wants and nobody should re-derive.
func get_next_threshold(heat: float) -> float:
	for tier in get_sorted_tiers():
		if tier.threshold > heat:
			return tier.threshold
	return 0.0


func clamp_heat(heat: float) -> float:
	var floored := maxf(0.0, heat)
	return floored if maximum_heat <= 0.0 else minf(floored, maximum_heat)


## Heat after [param delta] seconds of nobody committing anything.
##
## [param since_last_crime] is what makes a cooldown delay work: the tier's
## own patience is checked by the caller, and this only ever subtracts.
func decay(heat: float, delta: float) -> float:
	if delta <= 0.0 or decay_per_second <= 0.0 or heat <= 0.0:
		return heat
	if permanent_above > 0.0 and heat >= permanent_above:
		return heat
	return maxf(0.0, heat - decay_per_second * delta)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if not has_tiers():
		result.add_error(
			&"heat.no_tiers",
			"A heat profile with no tiers can never make anybody wanted.",
			resource_path,
			"tiers"
		)
	var seen: Array[float] = []
	for tier in get_sorted_tiers():
		if seen.has(tier.threshold):
			result.add_warning(
				&"heat.duplicate_threshold",
				(
					"Two tiers share the threshold %.1f, so one of them is "
					+ "unreachable."
				) % tier.threshold,
				resource_path,
				"tiers"
			)
		seen.append(tier.threshold)
		result.merge(tier.validate())

	if permanent_above > 0.0:
		var top := get_sorted_tiers()
		if not top.is_empty() and permanent_above < top[0].threshold:
			result.add_info(
				&"heat.permanent_below_first_tier",
				(
					"Heat becomes permanent at %.1f, below the first tier at "
					+ "%.1f, so an actor can be permanently heated and not "
					+ "wanted at all."
				) % [permanent_above, top[0].threshold],
				resource_path,
				"permanent_above"
			)
	if maximum_heat > 0.0:
		var rungs := get_sorted_tiers()
		if not rungs.is_empty() and maximum_heat < rungs.back().threshold:
			result.add_warning(
				&"heat.ceiling_below_top_tier",
				(
					"Heat is capped at %.1f but the top tier begins at %.1f, so "
					+ "it can never be reached."
				) % [maximum_heat, rungs.back().threshold],
				resource_path,
				"maximum_heat"
			)
	return result
