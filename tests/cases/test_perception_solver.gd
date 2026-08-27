extends FrameworkTestCase
## Covers PerceptionSolver: the geometry of noticing something.

func test_something_straight_ahead_is_in_the_cone() -> void:
	assert_true(
		PerceptionSolver.is_within_cone(
			Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 5.0, 110.0, 20.0
		)
	)


func test_something_behind_is_not() -> void:
	assert_false(
		PerceptionSolver.is_within_cone(
			Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 5.0, 110.0, 20.0
		)
	)


func test_the_field_of_view_is_a_half_angle_each_side() -> void:
	# 110 degrees means 55 either way, which is roughly a person's. Getting
	# this backwards gives every guard tunnel vision.
	var inside := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(50.0)) * 5.0
	var outside := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(60.0)) * 5.0
	assert_true(PerceptionSolver.is_within_cone(Vector3.ZERO, Vector3.FORWARD, inside, 110.0, 20.0))
	assert_false(
		PerceptionSolver.is_within_cone(Vector3.ZERO, Vector3.FORWARD, outside, 110.0, 20.0)
	)


func test_range_is_checked_as_well_as_angle() -> void:
	assert_false(
		PerceptionSolver.is_within_cone(
			Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 50.0, 110.0, 20.0
		)
	)


func test_a_full_circle_sees_everything_in_range() -> void:
	assert_true(
		PerceptionSolver.is_within_cone(
			Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 5.0, 360.0, 20.0
		)
	)


func test_visibility_scales_the_range_it_is_seen_from() -> void:
	assert_almost_eq(PerceptionSolver.effective_range(20.0, 1.0), 20.0)
	assert_almost_eq(PerceptionSolver.effective_range(20.0, 0.5), 10.0)
	assert_almost_eq(PerceptionSolver.effective_range(20.0, 0.0), 0.0)


func test_a_louder_noise_carries_further() -> void:
	assert_false(PerceptionSolver.noise_reaches(Vector3.ZERO, Vector3.FORWARD * 20.0, 15.0, 1.0))
	assert_true(PerceptionSolver.noise_reaches(Vector3.ZERO, Vector3.FORWARD * 20.0, 15.0, 2.0))


func test_a_silent_source_is_never_heard() -> void:
	assert_false(PerceptionSolver.noise_reaches(Vector3.ZERO, Vector3.ZERO, 15.0, 0.0))


func test_a_deaf_listener_never_hears() -> void:
	assert_false(PerceptionSolver.noise_reaches(Vector3.ZERO, Vector3.ZERO, 0.0, 10.0))


func test_urgency_puts_threat_first() -> void:
	# A distant dangerous thing outranks a nearby harmless one, or every guard
	# in the game charges the first rat it sees.
	assert_true(
		PerceptionSolver.urgency(5.0, 40.0, 0.0) > PerceptionSolver.urgency(1.0, 1.0, 0.0)
	)


func test_urgency_breaks_ties_on_nearness_then_freshness() -> void:
	assert_true(
		PerceptionSolver.urgency(3.0, 2.0, 0.0) > PerceptionSolver.urgency(3.0, 20.0, 0.0)
	)
	assert_true(
		PerceptionSolver.urgency(3.0, 5.0, 0.0) > PerceptionSolver.urgency(3.0, 5.0, 10.0)
	)
