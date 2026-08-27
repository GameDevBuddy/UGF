extends FrameworkTestCase
## Covers VehicleSolver and HandlingProfile: the driving maths, with no node,
## no body and no frame.
##
## Every one of these would need a physics world and a stopwatch if the
## handling lived inside a [VehicleBody3D], which is the whole argument for
## rule 33.

var profile: HandlingProfile = null


func before_each() -> void:
	profile = VehicleFixtures.handling()


# --- Speed ----------------------------------------------------------------

func test_throttle_accelerates() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(0.0, 1.0, 0.0, false, profile, 1.0), 10.0)


func test_acceleration_stops_at_the_ceiling() -> void:
	var speed := 0.0
	for step in 20:
		speed = VehicleSolver.solve_speed(speed, 1.0, 0.0, false, profile, 1.0)
	assert_almost_eq(speed, profile.max_speed)


func test_a_vehicle_already_over_its_ceiling_coasts_back_rather_than_snapping() -> void:
	# An upgrade coming off, a slope, a shove. Snapping to the limit is a
	# teleport, and a teleport is what a network client sees as a rubber band.
	var speed := VehicleSolver.solve_speed(45.0, 1.0, 0.0, false, profile, 0.1)
	assert_almost_eq(speed, 45.0)
	assert_true(speed <= 45.0)


func test_coasting_slows_down() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(20.0, 0.0, 0.0, false, profile, 1.0), 16.0)


func test_drag_never_pulls_through_zero() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(1.0, 0.0, 0.0, false, profile, 100.0), 0.0)


func test_braking_is_stronger_than_drag() -> void:
	# A short step on purpose. Over a whole second every one of these forces
	# reaches zero, and "0 < 0" is a comparison that proves nothing.
	var coasting := VehicleSolver.solve_speed(20.0, 0.0, 0.0, false, profile, 0.2)
	var braking := VehicleSolver.solve_speed(20.0, 0.0, 1.0, false, profile, 0.2)
	assert_true(braking < coasting, "%f should be below %f" % [braking, coasting])
	assert_true(braking > 0.0, "and neither should have bottomed out")


func test_the_handbrake_is_stronger_than_the_brake() -> void:
	var brake := VehicleSolver.solve_speed(20.0, 0.0, 1.0, false, profile, 0.2)
	var handbrake := VehicleSolver.solve_speed(20.0, 0.0, 1.0, true, profile, 0.2)
	assert_true(handbrake < brake, "%f should be below %f" % [handbrake, brake])
	assert_true(handbrake > 0.0, "and neither should have bottomed out")


func test_braking_never_reverses_you_through_the_stop() -> void:
	# A car braking hard from walking pace stops. It does not start reversing,
	# which is what a naive "subtract force" does at the wrong delta.
	assert_almost_eq(VehicleSolver.solve_speed(2.0, 0.0, 1.0, false, profile, 10.0), 0.0)


func test_braking_while_reversing_also_stops_you() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(-6.0, 0.0, 1.0, false, profile, 10.0), 0.0)


func test_the_brake_works_with_no_throttle_input_at_all() -> void:
	assert_true(VehicleSolver.solve_speed(20.0, 0.0, 0.5, false, profile, 1.0) < 20.0)


func test_reverse_has_its_own_lower_ceiling() -> void:
	var speed := 0.0
	for step in 20:
		speed = VehicleSolver.solve_speed(speed, -1.0, 0.0, false, profile, 1.0)
	assert_almost_eq(speed, -profile.max_reverse_speed)


func test_asking_for_reverse_while_moving_forward_brakes_first() -> void:
	# Pressing back at 20 m/s slows you down. It does not flip the vehicle into
	# reverse at 20 m/s, which is the single most common handling bug.
	var speed := VehicleSolver.solve_speed(20.0, -1.0, 0.0, false, profile, 0.5)
	assert_true(speed < 20.0 and speed > 0.0, "got %f" % speed)


func test_asking_for_forward_while_reversing_brakes_first() -> void:
	var speed := VehicleSolver.solve_speed(-6.0, 1.0, 0.0, false, profile, 0.1)
	assert_true(speed > -6.0 and speed < 0.0, "got %f" % speed)


func test_a_zero_delta_changes_nothing() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(12.0, 1.0, 0.0, false, profile, 0.0), 12.0)


func test_a_missing_profile_changes_nothing() -> void:
	assert_almost_eq(VehicleSolver.solve_speed(12.0, 1.0, 0.0, false, null, 1.0), 12.0)


# --- Steering -------------------------------------------------------------

func test_a_stationary_vehicle_does_not_turn() -> void:
	# The pirouette-on-the-spot bug: the tell of handling written straight into
	# a physics callback.
	assert_almost_eq(VehicleSolver.solve_steering_authority(0.0, profile), 0.0)
	assert_almost_eq(VehicleSolver.solve_heading(0.0, 0.0, 1.0, profile, 1.0), 0.0)


func test_steering_authority_falls_off_with_speed() -> void:
	var slow := VehicleSolver.solve_steering_authority(2.0, profile)
	var fast := VehicleSolver.solve_steering_authority(25.0, profile)
	assert_true(slow > fast, "%f should exceed %f" % [slow, fast])
	assert_true(fast >= profile.minimum_steering)


func test_steering_authority_bottoms_out_rather_than_vanishing() -> void:
	assert_almost_eq(
		VehicleSolver.solve_steering_authority(200.0, profile), profile.minimum_steering
	)


func test_a_profile_with_no_falloff_steers_the_same_at_any_speed() -> void:
	# What a tank or a hovercraft wants.
	profile.steering_falloff = 0.0
	assert_almost_eq(VehicleSolver.solve_steering_authority(2.0, profile), 1.0)
	assert_almost_eq(VehicleSolver.solve_steering_authority(200.0, profile), 1.0)


func test_steering_turns_the_heading() -> void:
	var heading := VehicleSolver.solve_heading(0.0, 10.0, 1.0, profile, 1.0)
	assert_true(heading > 0.0, "got %f" % heading)


func test_reversing_inverts_the_turn() -> void:
	# A car backing up with the wheel left goes right. Every driver knows it
	# and every naive implementation gets it wrong.
	var forward := VehicleSolver.solve_heading(0.0, 10.0, 1.0, profile, 0.5)
	var backward := VehicleSolver.solve_heading(0.0, -6.0, 1.0, profile, 0.5)
	assert_true(forward > 0.0 and backward < 0.0, "%f and %f" % [forward, backward])


func test_the_heading_wraps_rather_than_winding_up() -> void:
	profile.steering_rate = 10.0
	var heading := 3.0
	for step in 10:
		heading = VehicleSolver.solve_heading(heading, 10.0, 1.0, profile, 1.0)
		assert_true(heading >= -PI and heading <= PI, "escaped to %f" % heading)


# --- Velocity -------------------------------------------------------------

func test_velocity_points_where_the_vehicle_does() -> void:
	var north := VehicleSolver.solve_velocity(10.0, 0.0)
	assert_almost_eq(north.z, 10.0)
	assert_almost_eq(north.x, 0.0)
	var east := VehicleSolver.solve_velocity(10.0, PI / 2.0)
	assert_almost_eq(east.x, 10.0)


func test_velocity_leaves_the_vertical_alone() -> void:
	# Gravity and slopes belong to the body, not to handling.
	assert_almost_eq(VehicleSolver.solve_velocity(30.0, 1.2).y, 0.0)


func test_reversing_velocity_points_backwards() -> void:
	assert_almost_eq(VehicleSolver.solve_velocity(-5.0, 0.0).z, -5.0)


# --- Fuel -----------------------------------------------------------------

func test_full_throttle_burns_the_profile_rate() -> void:
	assert_almost_eq(VehicleSolver.solve_fuel_use(1.0, true, profile, 2.0), 2.0)


func test_idling_still_burns_fuel() -> void:
	# A car left running outside a bank empties eventually, which is the point
	# of leaving it running.
	var idle := VehicleSolver.solve_fuel_use(0.0, true, profile, 1.0)
	assert_almost_eq(idle, profile.fuel_per_second * profile.idle_fuel_fraction)
	assert_true(idle > 0.0)


func test_a_stopped_engine_burns_nothing() -> void:
	assert_almost_eq(VehicleSolver.solve_fuel_use(1.0, false, profile, 10.0), 0.0)


func test_reversing_burns_fuel_too() -> void:
	assert_almost_eq(VehicleSolver.solve_fuel_use(-1.0, true, profile, 2.0), 2.0)


# --- Reporting ------------------------------------------------------------

func test_the_speed_fraction_is_measured_against_the_right_ceiling() -> void:
	# Reverse is measured against the reverse ceiling, so a car flat out
	# backwards reads as flat out rather than a quarter throttle.
	assert_almost_eq(VehicleSolver.get_speed_fraction(15.0, profile), 0.5)
	assert_almost_eq(VehicleSolver.get_speed_fraction(-8.0, profile), 1.0)


func test_the_speed_fraction_is_capped() -> void:
	assert_almost_eq(VehicleSolver.get_speed_fraction(300.0, profile), 1.0)


# --- Validation -----------------------------------------------------------

func test_reversing_faster_than_driving_is_a_warning() -> void:
	profile.max_reverse_speed = 60.0
	assert_true(profile.validate().has_warnings())


func test_brakes_weaker_than_drag_are_a_warning() -> void:
	profile.braking = 1.0
	assert_true(profile.validate().has_warnings())


func test_a_sensible_profile_validates_clean() -> void:
	assert_false(profile.validate().has_errors())
	assert_false(profile.validate().has_warnings())
