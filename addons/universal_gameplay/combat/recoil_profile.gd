class_name RecoilProfile
extends Resource
## How a weapon's aim degrades as it is fired, and how it settles.
##
## Two separate things with one cause. [b]Spread[/b] is the cone shots go into
## and belongs to the weapon; [b]recoil[/b] is where the view is pushed and
## belongs to the camera. Keeping them apart is what lets a laser-accurate
## weapon still kick, and a wild one not move the screen at all.
##
## All angles are degrees.

@export_group("Spread")
## Cone at rest. Zero is perfectly accurate when standing still.
@export_range(0.0, 45.0, 0.01) var spread_min: float = 0.0

## Cone the weapon never exceeds however long it is held down.
@export_range(0.0, 45.0, 0.01) var spread_max: float = 5.0

## Added to the cone by each shot.
@export_range(0.0, 45.0, 0.01) var spread_per_shot: float = 0.5

## Degrees the cone closes per second while not firing.
@export_range(0.0, 90.0, 0.01, "or_greater") var spread_recovery_per_second: float = 4.0

@export_group("Recoil")
## Upward kick per shot.
@export_range(0.0, 30.0, 0.01) var recoil_pitch: float = 0.4

## Sideways kick per shot. Applied symmetrically, so a burst climbs rather
## than drifting one way.
@export_range(0.0, 30.0, 0.01) var recoil_yaw: float = 0.15

## Ceiling on accumulated offset in either axis.
@export_range(0.0, 90.0, 0.01, "or_greater") var recoil_max: float = 8.0

## Degrees the view settles back per second.
@export_range(0.0, 180.0, 0.01, "or_greater") var recoil_recovery_per_second: float = 6.0


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if spread_max < spread_min:
		result.add_error(
			&"recoil.inverted_spread",
			"Maximum spread is below minimum spread, so the cone would close as it fires.",
			resource_path,
			"spread_max"
		)
	if spread_per_shot > 0.0 and spread_recovery_per_second <= 0.0:
		result.add_warning(
			&"recoil.spread_never_recovers",
			(
				"Spread grows with every shot and never recovers, so accuracy "
				+ "degrades permanently over a session."
			),
			resource_path,
			"spread_recovery_per_second"
		)
	if recoil_pitch > 0.0 and recoil_recovery_per_second <= 0.0:
		result.add_warning(
			&"recoil.never_settles",
			"Recoil never settles, so the view drifts upward permanently.",
			resource_path,
			"recoil_recovery_per_second"
		)
	return result
