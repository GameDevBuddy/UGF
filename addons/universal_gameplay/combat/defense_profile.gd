class_name DefenseProfile
extends Resource
## What a character can do about being hit: block, parry, dodge.
##
## Implementation Plan 14 lists all three plus poise and stagger hooks. They are
## one profile rather than three because they are one decision made at one
## moment -- the defender is doing exactly one of them when the blow lands, and
## three components would have to agree on which (rule 4).
##
## [b]Timing is what separates them.[/b] A block is held and always works from
## the front; a parry is a window at the start of that same block and works
## once, perfectly; a dodge moves you out of the way entirely for a few frames.
## All three are numbers here rather than behaviour, so a project retunes its
## combat feel by editing a resource (rule 11).

@export_group("Block")
## Fraction of damage a held block removes. One is a perfect block, which is a
## legitimate choice for a tower shield and a bad one for most weapons.
@export_range(0.0, 1.0, 0.01) var block_reduction: float = 0.6

## Half-angle in degrees a block covers, measured from where the defender is
## facing. A hundred and eighty covers everything, which makes facing
## irrelevant and blocking strictly better than not blocking.
@export_range(0.0, 180.0, 1.0) var block_arc_degrees: float = 100.0

## Stamina spent per point of damage blocked. Zero makes blocking free, which
## makes it the only thing anybody ever does.
@export_range(0.0, 10.0, 0.01) var block_stamina_per_damage: float = 0.5

## Blocking stops when stamina runs out, and this is what that costs: the
## defender is staggered for this long and cannot block again until it passes.
@export_range(0.0, 10.0, 0.05, "or_greater") var guard_break_stagger: float = 1.0

@export_group("Parry")
## Seconds at the start of a block during which a hit is parried outright.
## Zero disables parrying without needing a second profile.
@export_range(0.0, 2.0, 0.01) var parry_window: float = 0.2

## Damage fraction a parry lets through. Zero is the usual case: a parry that
## still hurt would not be worth the timing.
@export_range(0.0, 1.0, 0.01) var parry_reduction: float = 1.0

## Seconds the attacker is staggered by a successful parry. This is the reward,
## and a parry that granted no opening would be a block with extra steps.
@export_range(0.0, 10.0, 0.05, "or_greater") var parry_stagger: float = 1.2

@export_group("Dodge")
## Seconds of invulnerability from the moment a dodge starts.
@export_range(0.0, 2.0, 0.01) var dodge_invulnerable: float = 0.3

## Total seconds a dodge occupies, including the part with no invulnerability.
## The recovery tail is what stops dodging being spammable.
@export_range(0.0, 4.0, 0.01) var dodge_duration: float = 0.6

@export_range(0.0, 200.0, 1.0, "or_greater") var dodge_stamina_cost: float = 20.0

@export_group("Poise")
## Damage absorbed before the defender is staggered. Zero means any hit
## staggers, which is right for a civilian and wrong for anything armoured.
@export_range(0.0, 1000.0, 1.0, "or_greater") var poise: float = 0.0

## Seconds a poise break staggers for.
@export_range(0.0, 10.0, 0.05, "or_greater") var poise_break_stagger: float = 0.8

## Seconds of not being hit before poise recovers fully.
@export_range(0.0, 30.0, 0.1, "or_greater") var poise_recovery_delay: float = 3.0


## Whether an incoming direction is inside the block arc.
##
## [param facing] and [param incoming] are both world-space and planar; the
## vertical component is dropped because a blow from above is still in front of
## you, and a shield that failed against a downward swing would be a shield
## nobody uses.
func covers(facing: Vector3, incoming: Vector3) -> bool:
	if block_arc_degrees >= 180.0:
		return true
	var front := Vector3(facing.x, 0.0, facing.z)
	var at := Vector3(incoming.x, 0.0, incoming.z)
	if front.length_squared() <= 0.0 or at.length_squared() <= 0.0:
		# Nothing to measure against. Covered, because the alternative is a
		# block that silently fails on any entity nobody bothered to rotate.
		return true
	return rad_to_deg(front.normalized().angle_to(at.normalized())) <= block_arc_degrees


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if parry_window > 0.0 and parry_stagger <= 0.0:
		result.add_warning(
			&"defense.parry_without_reward",
			(
				"This profile parries but staggers the attacker for no time, so "
				+ "a parry is a block with harder timing and no payoff."
			),
			resource_path,
			"parry_stagger"
		)
	if block_stamina_per_damage <= 0.0 and block_reduction > 0.0:
		result.add_warning(
			&"defense.free_block",
			(
				"Blocking costs no stamina, so it is strictly better than not "
				+ "blocking and there is no reason to ever stop."
			),
			resource_path,
			"block_stamina_per_damage"
		)
	if dodge_invulnerable > dodge_duration:
		result.add_error(
			&"defense.dodge_never_ends",
			(
				"The invulnerable window outlasts the dodge itself, so the "
				+ "recovery that balances it never happens."
			),
			resource_path,
			"dodge_invulnerable"
		)
	return result
