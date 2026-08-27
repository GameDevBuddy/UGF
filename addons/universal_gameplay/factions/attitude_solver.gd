class_name AttitudeSolver
extends RefCounted
## Turns a number into a disposition, as static functions on no state.
##
## Standing is a scale and behaviour is a set of bands, and where the bands sit
## is a design decision a project tunes. Keeping the conversion here means the
## question "at what standing does this guard draw a weapon?" has one answer
## that a test can pin down, rather than a threshold repeated in the brain, the
## vendor and the dialogue gate.

enum Attitude {
	## Will fight for you.
	ALLIED,
	## Helps, trades cheaply, lets you past.
	FRIENDLY,
	## No opinion.
	NEUTRAL,
	## Watches you. Not yet a fight.
	WARY,
	## Attacks on sight.
	HOSTILE,
}


## Which band [param standing] falls in, given a profile's thresholds.
##
## Bands are checked from most hostile upward, so a profile whose thresholds
## overlap resolves to the safer reading rather than to whichever comparison
## happened to run first.
static func resolve(
	standing: float,
	hostile_below: float,
	wary_below: float,
	friendly_above: float,
	allied_above: float
) -> Attitude:
	if standing <= hostile_below:
		return Attitude.HOSTILE
	if standing <= wary_below:
		return Attitude.WARY
	if standing >= allied_above:
		return Attitude.ALLIED
	if standing >= friendly_above:
		return Attitude.FRIENDLY
	return Attitude.NEUTRAL


static func is_hostile(attitude: Attitude) -> bool:
	return attitude == Attitude.HOSTILE


static func is_friendly(attitude: Attitude) -> bool:
	return attitude == Attitude.FRIENDLY or attitude == Attitude.ALLIED


## How threatening something of this attitude looks. Hostiles read as more
## dangerous than they are so an NPC picks the fight in front of it over the
## stronger thing standing behind it and doing nothing.
static func threat_scale(attitude: Attitude) -> float:
	match attitude:
		Attitude.HOSTILE:
			return 1.5
		Attitude.WARY:
			return 1.0
	return 0.0


## Price multiplier for a vendor of this attitude.
##
## Here rather than in Commerce because it is the same band table: a vendor who
## likes you charging less and a guard who dislikes you drawing a weapon are
## one number read two ways. M11's pricing policy consumes this rather than
## inventing a second set of thresholds.
static func price_scale(attitude: Attitude, spread: float = 0.2) -> float:
	match attitude:
		Attitude.ALLIED:
			return 1.0 - spread
		Attitude.FRIENDLY:
			return 1.0 - spread * 0.5
		Attitude.WARY:
			return 1.0 + spread * 0.5
		Attitude.HOSTILE:
			return 1.0 + spread
	return 1.0


static func to_name(attitude: Attitude) -> StringName:
	match attitude:
		Attitude.ALLIED:
			return &"attitude.allied"
		Attitude.FRIENDLY:
			return &"attitude.friendly"
		Attitude.WARY:
			return &"attitude.wary"
		Attitude.HOSTILE:
			return &"attitude.hostile"
	return &"attitude.neutral"
