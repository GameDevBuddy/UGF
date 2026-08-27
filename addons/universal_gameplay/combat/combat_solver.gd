class_name CombatSolver
extends RefCounted
## Every piece of combat maths, as static functions on no state.
##
## The same shape [MovementSolver] and [DamagePipeline] have, for the same
## reason: spread cones, recoil curves, range falloff and attack timing are
## decisions a project will want to tune and a test will want to pin down, and
## none of them needs a node, a scene or a physics frame (rule 33).
##
## [b]Randomness arrives as an argument.[/b] Spread takes a
## [RandomNumberGenerator], so a test seeds it and gets the same cone twice --
## and a networked game can hand every client the same stream. A solver that
## called [method @GlobalScope.randf] would be untestable and unsynchronisable
## in one stroke.

enum Phase {
	## Nothing is happening.
	IDLE,
	## Wind-up. The attack is committed but has not connected.
	STARTUP,
	## The damage window. Hits resolve here and nowhere else.
	ACTIVE,
	## Follow-through. The attack cannot hit again but still occupies the actor.
	RECOVERY,
}


# --- Attack timing --------------------------------------------------------

## Which phase an attack is in [param elapsed] seconds after it began.
##
## Startup, active and recovery in order. An attack with all three at zero is
## instantaneous: it resolves and is over, which is what a hitscan shot is.
static func phase_at(
	elapsed: float, startup: float, active: float, recovery: float
) -> Phase:
	if elapsed < 0.0:
		return Phase.IDLE
	if elapsed < startup:
		return Phase.STARTUP
	if elapsed < startup + active:
		return Phase.ACTIVE
	if elapsed < startup + active + recovery:
		return Phase.RECOVERY
	return Phase.IDLE


static func total_duration(startup: float, active: float, recovery: float) -> float:
	return maxf(0.0, startup) + maxf(0.0, active) + maxf(0.0, recovery)


# --- Spread ---------------------------------------------------------------

## Nudges [param direction] somewhere inside a cone of [param spread_degrees].
##
## Uniform over the cone's disc rather than over its angle: sampling the angle
## uniformly clusters shots at the centre, which reads as a weapon that is more
## accurate than its numbers say.
static func spread_direction(
	direction: Vector3, spread_degrees: float, rng: RandomNumberGenerator
) -> Vector3:
	var forward := direction.normalized()
	if spread_degrees <= 0.0 or forward.is_zero_approx() or rng == null:
		return forward

	var max_radius := tan(deg_to_rad(clampf(spread_degrees, 0.0, 89.0)))
	var radius := max_radius * sqrt(rng.randf())
	var angle := rng.randf() * TAU

	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var above := right.cross(forward).normalized()

	var offset := right * (cos(angle) * radius) + above * (sin(angle) * radius)
	return (forward + offset).normalized()


## Spread after one more shot, clamped to the profile's maximum.
static func accumulate_spread(current: float, profile: RecoilProfile) -> float:
	if profile == null:
		return current
	return minf(current + profile.spread_per_shot, profile.spread_max)


## Spread after [param delta] seconds of not shooting.
static func recover_spread(current: float, profile: RecoilProfile, delta: float) -> float:
	if profile == null:
		return current
	return maxf(
		profile.spread_min, current - profile.spread_recovery_per_second * delta
	)


# --- Recoil ---------------------------------------------------------------
#
# Recoil is an offset the camera adds, not a rotation combat applies. Rule 21:
# presentation observes, it is not driven from inside the domain.

## Recoil offset in degrees after one more shot, as (pitch, yaw).
static func accumulate_recoil(
	current: Vector2, profile: RecoilProfile, rng: RandomNumberGenerator = null
) -> Vector2:
	if profile == null:
		return current
	var yaw := profile.recoil_yaw
	if rng != null and profile.recoil_yaw != 0.0:
		# Symmetric, so a burst climbs rather than drifting to one side.
		yaw = rng.randf_range(-profile.recoil_yaw, profile.recoil_yaw)
	var kicked := current + Vector2(profile.recoil_pitch, yaw)
	return Vector2(
		clampf(kicked.x, -profile.recoil_max, profile.recoil_max),
		clampf(kicked.y, -profile.recoil_max, profile.recoil_max)
	)


## Recoil offset after [param delta] seconds of settling.
static func recover_recoil(
	current: Vector2, profile: RecoilProfile, delta: float
) -> Vector2:
	if profile == null:
		return current
	return current.move_toward(
		Vector2.ZERO, profile.recoil_recovery_per_second * delta
	)


# --- Range ----------------------------------------------------------------

## Damage multiplier at [param distance] metres.
##
## Full damage up to [param falloff_start], the minimum from
## [param falloff_end] on, and a straight line between. A rifle that keeps its
## damage to 60m and half of it past 120m is two numbers, not a curve resource.
static func range_multiplier(
	distance: float, falloff_start: float, falloff_end: float, minimum: float
) -> float:
	if falloff_end <= falloff_start or distance <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return minimum
	var travelled := (distance - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, minimum, travelled)


# --- Arcs -----------------------------------------------------------------

## Whether [param point] falls inside a cone of [param arc_degrees] opening
## along [param forward] from [param origin], within [param distance].
##
## Half-angle on each side, so 90 degrees is a sensible sword swing rather
## than a 45-degree sliver.
static func is_within_arc(
	origin: Vector3,
	forward: Vector3,
	point: Vector3,
	arc_degrees: float,
	distance: float
) -> bool:
	var to_point := point - origin
	if to_point.length() > distance:
		return false
	if arc_degrees >= 360.0:
		return true
	if to_point.is_zero_approx():
		return true
	var direction := forward.normalized()
	if direction.is_zero_approx():
		return true
	var angle := rad_to_deg(direction.angle_to(to_point.normalized()))
	return angle <= arc_degrees * 0.5
