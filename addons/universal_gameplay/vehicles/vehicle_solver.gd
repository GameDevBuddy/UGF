class_name VehicleSolver
extends RefCounted
## Pure driving maths: how speed and heading change under throttle, brake and
## steering.
##
## Static, node-free and frame-free, the way [MovementSolver] and
## [CombatSolver] are. Rule 33 wants domain logic testable without a live
## scene, and driving is the second place a framework usually loses that: the
## handling ends up inside a [VehicleBody3D] and from then on the only way to
## learn what a handling profile does is to drive it.
##
## Split out like this, "the handbrake stops you faster than the brake" and
## "a car will not turn while stationary" are unit tests that run in
## microseconds, and the adapter is left with the small job of turning the
## answer into motion.


## Speed after one step, given the pedals.
##
## [param throttle] and [param brake] are 0..1. Negative throttle is reverse.
## The sign of [param speed] is the direction of travel, so braking is always
## a pull towards zero rather than a push backwards -- which is what stops a
## braking car from reversing through the stop.
static func solve_speed(
	speed: float,
	throttle: float,
	brake: float,
	handbrake: bool,
	profile: HandlingProfile,
	delta: float
) -> float:
	if profile == null or delta <= 0.0:
		return speed

	var slowing := brake > 0.0 or handbrake
	if slowing:
		var force := profile.braking * clampf(brake, 0.0, 1.0)
		if handbrake:
			force += profile.handbrake_force
		return _towards_zero(speed, force * delta)

	var demand := clampf(throttle, -1.0, 1.0)
	if is_zero_approx(demand):
		# Coasting. Drag pulls towards zero and never through it.
		return _towards_zero(speed, profile.drag * delta)

	# Asking for the opposite direction while still rolling is braking, not
	# instant reverse: a car at 20 m/s pressing back slows down first.
	if not is_zero_approx(speed) and signf(demand) != signf(speed):
		return _towards_zero(speed, (profile.braking * absf(demand)) * delta)

	var ceiling := profile.max_speed if demand > 0.0 else profile.max_reverse_speed
	var target := demand * ceiling
	var stepped := speed + profile.acceleration * demand * delta
	# Clamped towards the target rather than to it, so a vehicle already over
	# its ceiling -- pushed, dropped, or downgraded by an upgrade coming off --
	# coasts back down instead of snapping.
	if demand > 0.0:
		return minf(stepped, maxf(target, speed))
	return maxf(stepped, minf(target, speed))


## How much steering authority is available at [param speed].
##
## Full at a standstill-plus-a-bit, falling to [member
## HandlingProfile.minimum_steering] by the falloff speed. Returns zero below
## the threshold, because a stationary car with its wheels turned does not
## rotate — and a vehicle that pirouettes on the spot is the single most
## common tell of handling written directly into a physics callback.
static func solve_steering_authority(speed: float, profile: HandlingProfile) -> float:
	if profile == null:
		return 0.0
	var magnitude := absf(speed)
	if magnitude < profile.steering_threshold:
		return 0.0
	if profile.steering_falloff <= 0.0:
		return 1.0
	var falloff_speed := profile.max_speed * profile.steering_falloff
	if falloff_speed <= 0.0:
		return 1.0
	var t := clampf(magnitude / falloff_speed, 0.0, 1.0)
	return lerpf(1.0, profile.minimum_steering, t)


## Heading after one step, in radians.
##
## [param steering] is -1..1. Reversing inverts the turn, because a car backing
## up with the wheel left goes right — the thing every driver knows and every
## naive implementation gets wrong.
static func solve_heading(
	heading: float,
	speed: float,
	steering: float,
	profile: HandlingProfile,
	delta: float
) -> float:
	if profile == null or delta <= 0.0:
		return heading
	var authority := solve_steering_authority(speed, profile)
	if is_zero_approx(authority):
		return heading
	var direction := -1.0 if speed < 0.0 else 1.0
	var turn := clampf(steering, -1.0, 1.0) * profile.steering_rate * authority
	return wrapf(heading + turn * direction * delta, -PI, PI)


## The velocity a speed and heading amount to. Y is left alone by design:
## gravity and slopes belong to whatever body is moving, not to handling.
static func solve_velocity(speed: float, heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading)) * speed


## Fuel burned in one step. Idling costs a fraction of full throttle, so a
## vehicle left running empties eventually.
static func solve_fuel_use(
	throttle: float, running: bool, profile: HandlingProfile, delta: float
) -> float:
	if profile == null or not running or delta <= 0.0:
		return 0.0
	var demand := absf(clampf(throttle, -1.0, 1.0))
	var fraction := maxf(demand, profile.idle_fuel_fraction)
	return profile.fuel_per_second * fraction * delta


## Speed as a fraction of the profile's ceiling in the direction of travel.
## What a speedometer, an engine-note blend and a camera FOV all want.
static func get_speed_fraction(speed: float, profile: HandlingProfile) -> float:
	if profile == null:
		return 0.0
	var ceiling := profile.max_speed if speed >= 0.0 else profile.max_reverse_speed
	if ceiling <= 0.0:
		return 0.0
	return clampf(absf(speed) / ceiling, 0.0, 1.0)


static func _towards_zero(value: float, amount: float) -> float:
	if value > 0.0:
		return maxf(0.0, value - amount)
	if value < 0.0:
		return minf(0.0, value + amount)
	return 0.0
