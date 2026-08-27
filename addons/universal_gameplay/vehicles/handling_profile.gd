class_name HandlingProfile
extends Resource
## How a vehicle accelerates, turns and stops.
##
## The vehicle equivalent of [MovementProfile], and reusable the same way: a
## sedan, a van and a sports car are three [code].tres[/code] files and no
## GDScript (rule 11, rule 13). Nothing here knows about a physics body --
## these are the numbers [VehicleSolver] does arithmetic with, and what turns
## that arithmetic into motion is the adapter's business (Implementation
## Plan 22).

@export_group("Speed")
## Top forward speed, metres per second. 30 is roughly 108 km/h.
@export_range(0.1, 200.0, 0.1, "or_greater") var max_speed: float = 30.0

## Top reverse speed. Lower than forward on anything with a gearbox.
@export_range(0.1, 100.0, 0.1, "or_greater") var max_reverse_speed: float = 8.0

@export_group("Response")
## Metres per second gained per second at full throttle.
@export_range(0.1, 100.0, 0.1, "or_greater") var acceleration: float = 8.0

## Metres per second lost per second under braking.
@export_range(0.1, 200.0, 0.1, "or_greater") var braking: float = 16.0

## Speed lost per second with no throttle and no brake: engine braking, rolling
## resistance, air. What makes releasing the throttle slow you down.
@export_range(0.0, 100.0, 0.1, "or_greater") var drag: float = 3.0

## Extra deceleration while the handbrake is down, on top of [member braking].
@export_range(0.0, 200.0, 0.1, "or_greater") var handbrake_force: float = 24.0

@export_group("Steering")
## Radians per second of heading change at full lock and full grip.
@export_range(0.0, 10.0, 0.01, "or_greater") var steering_rate: float = 1.6

## Fraction of [member max_speed] at which steering is at its weakest. Above
## this, turning authority has bottomed out. Zero disables the falloff, which
## is what a tank or a hovercraft wants.
@export_range(0.0, 1.0, 0.01) var steering_falloff: float = 0.6

## How much authority remains at and above the falloff speed. One is no
## falloff; low values are a car that will not turn at motorway speed.
@export_range(0.05, 1.0, 0.01) var minimum_steering: float = 0.35

## Below this speed a vehicle does not turn at all, because a stationary car
## with its wheels turned does not rotate.
@export_range(0.0, 20.0, 0.1) var steering_threshold: float = 0.5

@export_group("Consumption")
## Fuel units per second at full throttle. Idling costs a fraction of it.
@export_range(0.0, 100.0, 0.01, "or_greater") var fuel_per_second: float = 0.35

## Fraction of [member fuel_per_second] burned while the engine runs and the
## throttle is closed.
@export_range(0.0, 1.0, 0.01) var idle_fuel_fraction: float = 0.15


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if max_reverse_speed > max_speed:
		result.add_warning(
			&"handling.fast_reverse",
			"This vehicle reverses faster than it drives forwards.",
			resource_path,
			"max_reverse_speed"
		)
	if drag <= 0.0:
		result.add_info(
			&"handling.no_drag",
			(
				"With no drag, releasing the throttle never slows this vehicle "
				+ "down; only braking will."
			),
			resource_path,
			"drag"
		)
	if braking < drag:
		result.add_warning(
			&"handling.weak_brakes",
			"Braking is weaker than drag, so the brake pedal slows this less than coasting.",
			resource_path,
			"braking"
		)
	return result
