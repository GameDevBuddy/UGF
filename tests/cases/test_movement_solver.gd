extends FrameworkTestCase
## Covers MovementSolver: all of the movement maths, with no node, no physics
## server and no frame.
##
## This suite is the argument for splitting the solver out of the component.
## Every question here -- does sprinting go faster, does a jump one frame after
## a ledge still fire, does terminal velocity hold -- would otherwise only be
## answerable by playing the game and guessing.

var profile: MovementProfile = null


func before_each() -> void:
	profile = MovementProfile.new()
	profile.walk_speed = 4.0
	profile.sprint_speed = 8.0
	profile.crouch_speed = 2.0
	profile.acceleration = 40.0
	profile.deceleration = 55.0
	profile.air_acceleration = 12.0
	profile.air_control = 0.5
	profile.jump_velocity = 5.0
	profile.gravity = 18.0
	profile.max_fall_speed = 45.0
	profile.coyote_time = 0.12
	profile.jump_buffer = 0.15


func _forward(sprint: bool = false, crouch: bool = false) -> MovementIntent:
	return MovementIntent.create(Vector3.FORWARD, sprint, crouch)


# --- Planar velocity ------------------------------------------------------

func test_accelerates_toward_the_requested_direction() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, _forward(), profile, true, 0.05
	)
	# 40 m/s^2 for 0.05s is 2 m/s, short of the 4 m/s target.
	assert_almost_eq(velocity.length(), 2.0, 0.0001)
	assert_almost_eq(velocity.z, -2.0, 0.0001, "forward is -Z")


func test_acceleration_stops_at_the_target_speed() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, _forward(), profile, true, 1.0
	)
	assert_almost_eq(velocity.length(), 4.0, 0.0001, "a long frame does not overshoot")


func test_sprinting_targets_the_sprint_speed() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, _forward(true), profile, true, 1.0
	)
	assert_almost_eq(velocity.length(), 8.0, 0.0001)


func test_crouching_targets_the_crouch_speed() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, _forward(false, true), profile, true, 1.0
	)
	assert_almost_eq(velocity.length(), 2.0, 0.0001)


func test_decelerates_when_nothing_is_requested() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3(4.0, 0.0, 0.0), MovementIntent.new(), profile, true, 0.05
	)
	# 55 m/s^2 for 0.05s is 2.75 m/s off a 4 m/s velocity.
	assert_almost_eq(velocity.x, 1.25, 0.0001)


func test_deceleration_stops_at_zero() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3(4.0, 0.0, 0.0), MovementIntent.new(), profile, true, 1.0
	)
	assert_eq(velocity, Vector3.ZERO, "it does not reverse through zero")


func test_a_diagonal_is_not_faster_than_a_straight_line() -> void:
	var diagonal := MovementIntent.create(Vector3(1.0, 0.0, -1.0))
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, diagonal, profile, true, 1.0
	)
	assert_almost_eq(velocity.length(), 4.0, 0.0001)


func test_an_oversized_direction_is_normalised() -> void:
	var shove := MovementIntent.create(Vector3(0.0, 0.0, -100.0))
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, shove, profile, true, 1.0
	)
	assert_almost_eq(velocity.length(), 4.0, 0.0001)


func test_vertical_intent_does_not_become_horizontal_speed() -> void:
	var upward := MovementIntent.create(Vector3.UP)
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, upward, profile, true, 1.0
	)
	assert_eq(velocity, Vector3.ZERO)


func test_air_control_scales_acceleration() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3.ZERO, _forward(), profile, false, 0.1
	)
	# 12 m/s^2 at half control for 0.1s is 0.6 m/s.
	assert_almost_eq(velocity.length(), 0.6, 0.0001)


func test_no_air_control_means_a_committed_jump() -> void:
	profile.air_control = 0.0
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3(3.0, 0.0, 0.0), _forward(), profile, false, 0.1
	)
	assert_almost_eq(velocity.x, 3.0, 0.0001, "momentum is kept, steering is not")


func test_a_null_profile_leaves_the_planar_velocity_alone() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3(1.0, 2.0, 3.0), _forward(), null, true, 0.1
	)
	assert_eq(velocity, Vector3(1.0, 0.0, 3.0))


func test_a_zero_delta_changes_nothing() -> void:
	var velocity := MovementSolver.solve_planar_velocity(
		Vector3(1.0, 0.0, 3.0), _forward(), profile, true, 0.0
	)
	assert_eq(velocity, Vector3(1.0, 0.0, 3.0))


# --- Vertical velocity ----------------------------------------------------

func test_gravity_pulls_down_while_airborne() -> void:
	var y := MovementSolver.solve_vertical_velocity(Vector3.ZERO, profile, false, 0.1)
	assert_almost_eq(y, -1.8, 0.0001)


func test_falling_is_clamped_to_terminal_velocity() -> void:
	var y := MovementSolver.solve_vertical_velocity(
		Vector3(0.0, -100.0, 0.0), profile, false, 0.1
	)
	assert_almost_eq(y, -45.0, 0.0001)


func test_grounded_velocity_keeps_a_small_downward_bias() -> void:
	# Zero here makes a character skip over every seam in the floor.
	var y := MovementSolver.solve_vertical_velocity(Vector3.ZERO, profile, true, 0.1)
	assert_true(y < 0.0)
	assert_true(y > -1.0, "a bias, not a fall")


func test_rising_off_the_ground_is_not_clamped_to_the_bias() -> void:
	# The frame a jump fires the body is still reported on the floor.
	var y := MovementSolver.solve_vertical_velocity(
		Vector3(0.0, 5.0, 0.0), profile, true, 0.1
	)
	assert_almost_eq(y, 5.0 - 1.8, 0.0001)


# --- Jumping --------------------------------------------------------------

func test_a_grounded_jump_fires() -> void:
	assert_true(MovementSolver.can_jump(profile, true, 0.0, 0.0))


func test_a_jump_with_no_press_does_not_fire() -> void:
	assert_false(MovementSolver.can_jump(profile, true, 0.0, -1.0))


func test_coyote_time_allows_a_jump_just_after_a_ledge() -> void:
	assert_true(MovementSolver.can_jump(profile, false, 0.1, 0.0))


func test_coyote_time_expires() -> void:
	assert_false(MovementSolver.can_jump(profile, false, 0.2, 0.0))


func test_a_buffered_press_survives_until_landing() -> void:
	assert_true(MovementSolver.can_jump(profile, true, 0.0, 0.14))


func test_a_stale_press_is_not_honoured() -> void:
	# Otherwise a press during a long fall fires seconds later, on landing.
	assert_false(MovementSolver.can_jump(profile, true, 0.0, 0.5))


func test_a_profile_that_cannot_jump_does_not() -> void:
	profile.can_jump = false
	assert_false(MovementSolver.can_jump(profile, true, 0.0, 0.0))


func test_a_profile_with_no_jump_height_does_not_jump() -> void:
	profile.jump_velocity = 0.0
	assert_false(MovementSolver.can_jump(profile, true, 0.0, 0.0))


func test_a_null_profile_never_jumps() -> void:
	assert_false(MovementSolver.can_jump(null, true, 0.0, 0.0))


func test_apply_jump_replaces_vertical_velocity() -> void:
	# Replaces rather than adds, so jumping while already rising cannot
	# compound into a double-height jump.
	var velocity := MovementSolver.apply_jump(Vector3(1.0, 3.0, 2.0), profile)
	assert_almost_eq(velocity.y, 5.0)
	assert_almost_eq(velocity.x, 1.0, 0.0001, "horizontal momentum is kept")
	assert_almost_eq(velocity.z, 2.0, 0.0001)


# --- Stance ---------------------------------------------------------------

func test_stance_passes_through_what_the_profile_allows() -> void:
	var stance := MovementSolver.resolve_stance(_forward(true, false), profile)
	assert_eq(stance, [true, false])


func test_stance_vetoes_sprinting_when_the_profile_cannot() -> void:
	profile.can_sprint = false
	var stance := MovementSolver.resolve_stance(_forward(true, false), profile)
	assert_eq(stance, [false, false])


func test_stance_vetoes_sprinting_while_crouched() -> void:
	var stance := MovementSolver.resolve_stance(_forward(true, true), profile)
	assert_eq(stance, [false, true], "crouching wins")


func test_a_null_profile_resolves_to_no_stance() -> void:
	assert_eq(MovementSolver.resolve_stance(_forward(true, true), null), [false, false])
