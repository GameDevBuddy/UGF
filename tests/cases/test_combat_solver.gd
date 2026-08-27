extends FrameworkTestCase
## Covers CombatSolver: attack phases, spread, recoil, range falloff and arcs.
##
## All of it static maths on no state, which is the point -- these are the
## numbers a designer tunes, and pinning them down needs no scene, no physics
## and no weapon.

func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Phases ---------------------------------------------------------------

func test_an_attack_with_no_timing_is_never_in_a_phase() -> void:
	assert_eq(CombatSolver.phase_at(0.0, 0.0, 0.0, 0.0), CombatSolver.Phase.IDLE)
	assert_eq(CombatSolver.total_duration(0.0, 0.0, 0.0), 0.0)


func test_phases_run_in_order() -> void:
	assert_eq(CombatSolver.phase_at(0.05, 0.2, 0.1, 0.3), CombatSolver.Phase.STARTUP)
	assert_eq(CombatSolver.phase_at(0.25, 0.2, 0.1, 0.3), CombatSolver.Phase.ACTIVE)
	assert_eq(CombatSolver.phase_at(0.4, 0.2, 0.1, 0.3), CombatSolver.Phase.RECOVERY)
	assert_eq(CombatSolver.phase_at(0.7, 0.2, 0.1, 0.3), CombatSolver.Phase.IDLE)


func test_the_boundaries_belong_to_the_later_phase() -> void:
	# Exactly representable timings on purpose. 0.2 + 0.1 is 0.30000000000000004,
	# so a test asserting the boundary at 0.3 would be asserting floating-point
	# luck rather than the rule -- and the rule is what matters: an instant
	# lands in the phase it opens, not the one it closes.
	assert_eq(CombatSolver.phase_at(0.25, 0.25, 0.25, 0.5), CombatSolver.Phase.ACTIVE)
	assert_eq(CombatSolver.phase_at(0.5, 0.25, 0.25, 0.5), CombatSolver.Phase.RECOVERY)
	assert_eq(CombatSolver.phase_at(1.0, 0.25, 0.25, 0.5), CombatSolver.Phase.IDLE)


func test_negative_time_is_idle() -> void:
	assert_eq(CombatSolver.phase_at(-1.0, 0.2, 0.1, 0.3), CombatSolver.Phase.IDLE)


func test_duration_is_the_sum() -> void:
	assert_almost_eq(CombatSolver.total_duration(0.2, 0.1, 0.3), 0.6)


# --- Spread ---------------------------------------------------------------

func test_no_spread_leaves_the_direction_alone() -> void:
	var direction := CombatSolver.spread_direction(Vector3.FORWARD, 0.0, _rng())
	assert_almost_eq(direction.distance_to(Vector3.FORWARD), 0.0)


func test_spread_stays_inside_its_cone() -> void:
	var rng := _rng()
	for shot in 200:
		var direction := CombatSolver.spread_direction(Vector3.FORWARD, 5.0, rng)
		var angle := rad_to_deg(Vector3.FORWARD.angle_to(direction))
		assert_true(angle <= 5.001, "shot %d was %f degrees off" % [shot, angle])


func test_spread_actually_moves_the_shot() -> void:
	var rng := _rng()
	var moved := 0
	for shot in 50:
		if CombatSolver.spread_direction(Vector3.FORWARD, 5.0, rng) != Vector3.FORWARD:
			moved += 1
	assert_true(moved > 45, "a five degree cone should move nearly every shot")


func test_the_same_seed_gives_the_same_shots() -> void:
	var first := CombatSolver.spread_direction(Vector3.FORWARD, 5.0, _rng(99))
	var second := CombatSolver.spread_direction(Vector3.FORWARD, 5.0, _rng(99))
	assert_almost_eq(first.distance_to(second), 0.0)


func test_spread_works_along_the_vertical_axis() -> void:
	# The basis this builds degenerates when forward is world up, and a shot
	# straight down is exactly what a grenade drop is.
	var direction := CombatSolver.spread_direction(Vector3.UP, 5.0, _rng())
	assert_true(direction.is_normalized())
	assert_true(rad_to_deg(Vector3.UP.angle_to(direction)) <= 5.001)


func test_spread_returns_the_direction_with_no_generator() -> void:
	assert_almost_eq(
		CombatSolver.spread_direction(Vector3.FORWARD, 5.0, null).distance_to(Vector3.FORWARD),
		0.0
	)


func test_spread_accumulates_to_its_cap() -> void:
	var profile := CombatFixtures.recoil(2.0, 5.0)
	var spread := 0.0
	for shot in 10:
		spread = CombatSolver.accumulate_spread(spread, profile)
	assert_almost_eq(spread, 5.0)


func test_spread_recovers_to_its_floor() -> void:
	var profile := CombatFixtures.recoil(2.0, 5.0)
	profile.spread_min = 1.0
	var spread := CombatSolver.recover_spread(5.0, profile, 1.0)
	assert_almost_eq(spread, 3.0)
	assert_almost_eq(CombatSolver.recover_spread(spread, profile, 10.0), 1.0)


# --- Recoil ---------------------------------------------------------------

func test_recoil_climbs_and_is_capped() -> void:
	var profile := CombatFixtures.recoil()
	profile.recoil_pitch = 2.0
	profile.recoil_max = 5.0
	var recoil := Vector2.ZERO
	for shot in 10:
		recoil = CombatSolver.accumulate_recoil(recoil, profile)
	assert_almost_eq(recoil.x, 5.0)


func test_recoil_settles_back_to_zero() -> void:
	var profile := CombatFixtures.recoil()
	profile.recoil_recovery_per_second = 4.0
	var settled := CombatSolver.recover_recoil(Vector2(4.0, 0.0), profile, 1.0)
	assert_almost_eq(settled.x, 0.0)


func test_yaw_kick_is_symmetric() -> void:
	# A burst that always kicked the same way would walk off target instead of
	# climbing, which is a different weapon entirely.
	var profile := CombatFixtures.recoil()
	profile.recoil_yaw = 1.0
	var rng := _rng()
	var left := 0
	var right := 0
	for shot in 100:
		var kicked := CombatSolver.accumulate_recoil(Vector2.ZERO, profile, rng)
		if kicked.y < 0.0:
			left += 1
		elif kicked.y > 0.0:
			right += 1
	assert_true(left > 20 and right > 20, "got %d left and %d right" % [left, right])


func test_a_null_profile_changes_nothing() -> void:
	assert_almost_eq(CombatSolver.accumulate_spread(3.0, null), 3.0)
	assert_almost_eq(CombatSolver.recover_spread(3.0, null, 1.0), 3.0)
	assert_almost_eq(CombatSolver.accumulate_recoil(Vector2(1.0, 0.0), null).x, 1.0)
	assert_almost_eq(CombatSolver.recover_recoil(Vector2(1.0, 0.0), null, 1.0).x, 1.0)


# --- Range ----------------------------------------------------------------

func test_damage_is_full_inside_the_falloff_start() -> void:
	assert_almost_eq(CombatSolver.range_multiplier(10.0, 30.0, 60.0, 0.5), 1.0)


func test_damage_is_the_minimum_past_the_falloff_end() -> void:
	assert_almost_eq(CombatSolver.range_multiplier(100.0, 30.0, 60.0, 0.5), 0.5)


func test_damage_fades_linearly_between() -> void:
	assert_almost_eq(CombatSolver.range_multiplier(45.0, 30.0, 60.0, 0.5), 0.75)


func test_no_falloff_configured_means_no_falloff() -> void:
	assert_almost_eq(CombatSolver.range_multiplier(500.0, 0.0, 0.0, 0.1), 1.0)


# --- Arcs -----------------------------------------------------------------

func test_a_point_straight_ahead_is_in_the_arc() -> void:
	assert_true(
		CombatSolver.is_within_arc(
			Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 1.5, 90.0, 2.0
		)
	)


func test_a_point_behind_is_not() -> void:
	assert_false(
		CombatSolver.is_within_arc(
			Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 1.5, 90.0, 2.0
		)
	)


func test_the_arc_is_a_half_angle_on_each_side() -> void:
	# 90 degrees means 45 either way, so a target at 40 degrees is in and one
	# at 50 is out. Getting this backwards makes every sword swing feel wrong.
	var inside := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(40.0))
	var outside := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(50.0))
	assert_true(CombatSolver.is_within_arc(Vector3.ZERO, Vector3.FORWARD, inside, 90.0, 2.0))
	assert_false(CombatSolver.is_within_arc(Vector3.ZERO, Vector3.FORWARD, outside, 90.0, 2.0))


func test_range_is_checked_as_well_as_angle() -> void:
	assert_false(
		CombatSolver.is_within_arc(
			Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 5.0, 90.0, 2.0
		)
	)


func test_a_full_circle_hits_everything_in_range() -> void:
	assert_true(
		CombatSolver.is_within_arc(
			Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 1.5, 360.0, 2.0
		)
	)
