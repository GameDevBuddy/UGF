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

@export_group("State")
## What it spends. Null is a weapon that never runs out: a sword, a fist.
@export var ammo: AmmoProfile

## How its aim degrades and settles. Null is a weapon with no spread at all.
@export var recoil: RecoilProfile


func get_attack(secondary_attack: bool = false) -> AttackDefinition:
	if secondary_attack:
		return secondary
	return primary


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
