class_name WeaponProfile
extends Resource
## What makes an item a weapon.
##
## Hangs off [member ItemDefinition.weapon], the way an equipment profile does:
## a sword is an item that can be worn and swung, not a Sword class (rule 13,
## rule 16). A turret and a vehicle-mounted gun use the same profile without
## being items at all, by handing it to a [WeaponComponent] directly.

enum FireMode {
	## One attack per press. Rifles, bows, most melee.
	SINGLE,
	## Repeats while held, at [member rate_per_second].
	AUTOMATIC,
	## A fixed count per press, then stops until released.
	BURST,
	## Builds while held and fires on release. The bow, the plasma rifle, the
	## heavy swing.
	CHARGE,
}

## The attack a primary press produces.
@export var primary: AttackDefinition

## The attack a secondary press produces: a bash, a heavy swing, a grenade
## launcher under the barrel. Optional.
@export var secondary: AttackDefinition

@export_group("Firing")
@export var fire_mode: FireMode = FireMode.SINGLE

## Attacks per second while held. Zero means as fast as the attack's own
## timing allows, which for a melee weapon is the honest answer.
@export_range(0.0, 60.0, 0.01, "or_greater") var rate_per_second: float = 0.0

## Attacks per press in [constant FireMode.BURST].
@export_range(1, 16) var burst_count: int = 3

@export_subgroup("Charge")
## Seconds of holding to reach full charge. Only read in
## [constant FireMode.CHARGE].
@export_range(0.0, 30.0, 0.01, "or_greater") var charge_time: float = 1.0

## Fraction of a full charge below which a release does nothing.
##
## [b]Zero is deliberately not the default.[/b] A charge weapon that fires a
## limp shot on a stray tap reads as unresponsive rather than as forgiving, and
## the player cannot tell a wasted round from a missed input.
@export_range(0.0, 1.0, 0.01) var minimum_charge: float = 0.25

## Damage multiplier at full charge. The shot scales linearly from 1.0 at
## [member minimum_charge] to this at full.
@export_range(0.1, 20.0, 0.1, "or_greater") var charge_multiplier: float = 2.0

## Fires by itself the moment the charge fills, rather than waiting for the
## release. What a weapon that would overheat does.
@export var releases_at_full: bool = false

## Charge decays this fast when the trigger is let go below the minimum, as a
## fraction per second. Zero keeps a part-charge indefinitely.
@export_range(0.0, 10.0, 0.01) var charge_decay_per_second: float = 1.0

@export_group("State")
## What it spends. Null is a weapon that never runs out: a sword, a fist.
@export var ammo: AmmoProfile

## How its aim degrades and settles. Null is a weapon with no spread at all.
@export var recoil: RecoilProfile


func get_attack(secondary_attack: bool = false) -> AttackDefinition:
	if secondary_attack:
		return secondary
	return primary


## Whether a press builds a charge rather than firing immediately.
func is_charged() -> bool:
	return fire_mode == FireMode.CHARGE


## Damage scale for a shot released at [param charge], a fraction of full.
##
## Returns zero below [member minimum_charge], which is how a caller tells a
## wasted tap from a real shot. Above it the scale runs from 1.0 to
## [member charge_multiplier], so a minimum-charge shot does a weapon's normal
## damage rather than a fraction of it -- the charge is a bonus for waiting,
## not a tax for not waiting long enough.
func get_charge_scale(charge: float) -> float:
	if not is_charged():
		return 1.0
	var held := clampf(charge, 0.0, 1.0)
	if held < minimum_charge:
		return 0.0
	if minimum_charge >= 1.0:
		return charge_multiplier
	var progress := (held - minimum_charge) / (1.0 - minimum_charge)
	return lerpf(1.0, charge_multiplier, progress)


func uses_ammo() -> bool:
	return ammo != null and not ammo.is_infinite()


## Seconds between attacks, from the rate when there is one and from the
## attack's own duration when there is not.
func get_interval(secondary_attack: bool = false) -> float:
	if rate_per_second > 0.0:
		return 1.0 / rate_per_second
	var attack := get_attack(secondary_attack)
	return attack.get_duration() if attack != null else 0.0


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if primary == null:
		result.add_error(
			&"weapon.no_primary",
			"A weapon profile with no primary attack cannot be used.",
			resource_path,
			"primary"
		)
	else:
		result.merge(primary.validate())
	if secondary != null:
		result.merge(secondary.validate())
	if ammo != null:
		result.merge(ammo.validate())
	if recoil != null:
		result.merge(recoil.validate())
	if fire_mode == FireMode.AUTOMATIC and rate_per_second <= 0.0:
		result.add_warning(
			&"weapon.automatic_without_rate",
			(
				"An automatic weapon with no rate fires as fast as its attack "
				+ "timing allows, which for an instant attack is every frame."
			),
			resource_path,
			"rate_per_second"
		)
	return result
