class_name ResistanceProfile
extends Resource
## How much damage an entity shrugs off, by damage tag.
##
## Armour and resistance are data, so a project's "heavy plate" is a
## [code].tres[/code] and not a class (rule 11). Matching is on the semantic
## tags a [DamageContext] carries -- [code]damage.fire[/code],
## [code]damage.ballistic[/code] -- rather than on an enum, because Core would
## then have to own the list of every damage type any game might want.

## Subtracted before percentage resistance. Flat armour is what makes a
## high-armour target immune to a swarm of weak hits while still vulnerable to
## one big one, which percentage resistance alone cannot express.
@export var flat_armor: float = 0.0

## Fraction reduced per damage tag, 0 to 1. A tag at 0.25 removes a quarter.
## Values above 1 heal, which is what a vulnerability of -0.5 is not: use
## [member vulnerabilities] for that.
@export var resistances: Dictionary[StringName, float] = {}

## Fraction added per damage tag. 0.5 means half again as much damage.
@export var vulnerabilities: Dictionary[StringName, float] = {}

## Tags this entity takes no damage from at all. Checked before everything
## else, so an immunity is absolute rather than a 100% resistance that a
## vulnerability could claw back.
@export var immunities: Array[StringName] = []

## Cap on total percentage resistance, so stacked sources cannot reach
## invulnerability by accident. 0.9 means damage is never reduced below a tenth.
@export_range(0.0, 1.0) var maximum_resistance: float = 0.9


## Total resistance fraction that applies to a set of damage tags.
##
## Resistances sum rather than compound: three sources of 20% fire resistance
## give 60%, not 49%. Summing is the behaviour designers predict, and the cap
## is what stops it reaching immunity.
func get_resistance_for(tags: Array[StringName]) -> float:
	var total := 0.0
	for tag in tags:
		total += resistances.get(tag, 0.0)
		total -= vulnerabilities.get(tag, 0.0)
	return minf(total, maximum_resistance)


func is_immune_to(tags: Array[StringName]) -> bool:
	for tag in tags:
		if immunities.has(tag):
			return true
	return false


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if flat_armor < 0.0:
		result.add_error(
			&"resistance_profile.negative_armor",
			"flat_armor is negative, which would add damage rather than reduce it.",
			resource_path,
			"flat_armor"
		)
	for tag in resistances:
		var value: float = resistances[tag]
		if value > 1.0:
			result.add_warning(
				&"resistance_profile.resistance_above_one",
				(
					"Resistance to '%s' is above 100%%; it is capped at %.0f%% anyway."
					% [tag, maximum_resistance * 100.0]
				),
				resource_path,
				"resistances"
			)
		if value < 0.0:
			result.add_warning(
				&"resistance_profile.negative_resistance",
				(
					"Resistance to '%s' is negative. Use vulnerabilities to express "
					+ "taking extra damage."
				) % tag,
				resource_path,
				"resistances"
			)
	for tag in immunities:
		if resistances.has(tag) or vulnerabilities.has(tag):
			result.add_warning(
				&"resistance_profile.redundant_immunity",
				(
					"'%s' is both an immunity and a resistance; the immunity wins and "
					+ "the resistance never applies."
				) % tag,
				resource_path,
				"immunities"
			)
	return result
