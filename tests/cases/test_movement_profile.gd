extends FrameworkTestCase
## Covers MovementProfile: the speed a stance resolves to, and the validation
## that catches a profile which would silently misbehave.

var profile: MovementProfile = null


func before_each() -> void:
	profile = MovementProfile.new()
	profile.walk_speed = 4.0
	profile.sprint_speed = 8.0
	profile.crouch_speed = 2.0


func test_default_stance_walks() -> void:
	assert_almost_eq(profile.get_speed_for(false, false), 4.0)


func test_sprinting_is_faster() -> void:
	assert_almost_eq(profile.get_speed_for(true, false), 8.0)


func test_crouching_is_slower() -> void:
	assert_almost_eq(profile.get_speed_for(false, true), 2.0)


func test_a_profile_that_cannot_sprint_walks_instead() -> void:
	# Wanting to sprint and being able to are different questions, and a
	# character that simply cannot run is a profile, not a subclass (rule 5).
	profile.can_sprint = false
	assert_almost_eq(profile.get_speed_for(true, false), 4.0)


func test_a_profile_that_cannot_crouch_ignores_crouching() -> void:
	profile.can_crouch = false
	assert_almost_eq(profile.get_speed_for(false, true), 4.0)


func test_crouching_blocks_sprinting_by_default() -> void:
	assert_almost_eq(profile.get_speed_for(true, true), 2.0)


func test_a_profile_may_allow_sprinting_while_crouched() -> void:
	profile.sprint_blocked_while_crouching = false
	assert_almost_eq(profile.get_speed_for(true, true), 8.0)


func test_a_sensible_profile_validates_clean() -> void:
	var result := profile.validate()
	assert_false(result.has_errors(), result.format_report())
	assert_false(result.has_warnings(), result.format_report())


func test_zero_walk_speed_is_an_error() -> void:
	profile.walk_speed = 0.0
	assert_true(profile.validate().has_errors())


func test_zero_acceleration_is_an_error() -> void:
	# Acceleration of zero means the character can never start moving, which
	# reads in play as the input being broken.
	profile.acceleration = 0.0
	var result := profile.validate()
	assert_true(result.has_errors())
	assert_true(result.format_report().contains("never start moving"))


func test_negative_gravity_is_an_error() -> void:
	profile.gravity = -9.8
	assert_true(profile.validate().has_errors())


func test_a_sprint_slower_than_a_walk_is_a_warning() -> void:
	# Not an error: it is expressible, just almost certainly a typo.
	profile.sprint_speed = 1.0
	var result := profile.validate()
	assert_false(result.has_errors())
	assert_true(result.has_warnings())


func test_a_slow_sprint_is_not_flagged_when_sprinting_is_off() -> void:
	profile.can_sprint = false
	profile.sprint_speed = 1.0
	assert_false(profile.validate().has_warnings())


func test_jumping_with_no_height_is_a_warning() -> void:
	profile.jump_velocity = 0.0
	var result := profile.validate()
	assert_true(result.has_warnings())
	assert_true(result.format_report().contains("jumping does nothing"))
