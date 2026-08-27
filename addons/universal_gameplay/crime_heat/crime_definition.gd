class_name CrimeDefinition
extends FrameworkDefinition
## What counts as a crime, and how much trouble it is.
##
## Adding an offence to a game creates a [code].tres[/code] and no GDScript
## (rule 15). Theft, assault, murder, trespass and reckless driving differ in
## their numbers, in whose law they break and in whether anybody has to see
## them — and all four are data.

## How much heat this adds when reported. The ladder in [HeatProfile] turns a
## total into a wanted tier.
@export_range(0.0, 10000.0, 1.0, "or_greater") var heat: float = 25.0

## Reputation lost with the wronged faction. Separate from heat on purpose:
## being wanted wears off, being remembered as a murderer does not.
@export_range(0.0, 1000.0, 1.0, "or_greater") var reputation_cost: float = 10.0

@export_group("Witnesses")
## Whether somebody has to see it.
##
## [b]On for almost everything.[/b] A crime nobody witnessed is the whole
## fantasy of a stealth game, and a framework that made every offence
## automatically known would have no way back to it.
@export var requires_witness: bool = true

## Heat multiplier per additional witness beyond the first, so a murder in a
## crowded square is worse than one down an alley. Zero makes witnesses a
## yes-or-no question.
@export_range(0.0, 5.0, 0.01) var witness_scale: float = 0.25

## Cap on the witness multiplier, so a packed stadium is not unbounded.
@export_range(1.0, 100.0, 0.1, "or_greater") var maximum_witness_scale: float = 3.0

@export_group("Jurisdiction")
## Whose law this breaks. Blank means the victim's own faction, resolved when
## the crime is reported.
@export var law_faction: StringName = &""

## Crimes this one supersedes: reporting a murder need not also report the
## assault that preceded it. Ids rather than resources, so a definition does
## not load the ones it outranks (rule 32).
@export var supersedes: Array[StringName] = []

@export_group("Vocabulary")
## What kind of offence this is, for a UI and for an objective matching on it:
## [code]crime.violent[/code], [code]crime.property[/code].
@export var crime_tags: Array[StringName] = []


func is_witnessed_crime() -> bool:
	return requires_witness


func supersedes_crime(crime_id: StringName) -> bool:
	return supersedes.has(crime_id)


func has_crime_tag(tag: StringName) -> bool:
	return crime_tags.has(tag)


## Heat for this offence given how many people saw it.
##
## The first witness costs nothing extra; each one after adds
## [member witness_scale], capped. A crime that needs no witness is charged in
## full regardless, because "the body was found" is not a headcount.
func get_heat_for(witness_count: int) -> float:
	if not requires_witness:
		return heat
	if witness_count <= 0:
		return 0.0
	var scale := 1.0 + witness_scale * float(witness_count - 1)
	return heat * minf(scale, maximum_witness_scale)


func validate() -> ValidationResult:
	var result := super()
	if heat <= 0.0 and reputation_cost <= 0.0:
		result.add_warning(
			&"crime.costless",
			(
				"%s costs neither heat nor reputation, so committing it changes "
				+ "nothing."
			) % get_debug_name(),
			resource_path,
			"heat"
		)
	if maximum_witness_scale < 1.0:
		result.add_error(
			&"crime.witness_scale_below_one",
			(
				"%s caps its witness multiplier below one, so being seen makes "
				+ "it cheaper."
			) % get_debug_name(),
			resource_path,
			"maximum_witness_scale"
		)
	if supersedes.has(id):
		result.add_error(
			&"crime.supersedes_itself",
			"%s supersedes itself." % get_debug_name(),
			resource_path,
			"supersedes"
		)
	return result
