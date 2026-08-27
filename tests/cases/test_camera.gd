extends FrameworkTestCase
## Covers CameraSolver and CameraAdapter: look clamping, boom placement, and
## the fact that a camera-less entity still knows which way it is facing.

var entity: Node3D = null
var adapter: CameraAdapter = null
var profile: CameraProfile = null


func before_each() -> void:
	entity = add_test_node(Node3D.new()) as Node3D
	profile = CameraProfile.new()
	profile.mode = CameraProfile.Mode.THIRD_PERSON
	profile.boom_length = 4.0
	profile.pivot_height = 1.6
	profile.sensitivity = 0.01
	profile.pitch_min_degrees = -60.0
	profile.pitch_max_degrees = 60.0
	profile.fov = 70.0
	profile.sprint_fov = 80.0
	profile.fov_blend_speed = 100.0
	adapter = CameraAdapter.new()
	adapter.profile_override = profile
	entity.add_child(adapter)


func _initialise() -> void:
	adapter.initialize(EntityContext.create(entity))


# --- Solver ---------------------------------------------------------------

func test_looking_up_raises_pitch() -> void:
	var angles := CameraSolver.apply_look(0.0, 0.0, Vector2(0.0, -10.0), profile)
	assert_true(angles[1] > 0.0)


func test_invert_y_reverses_it() -> void:
	profile.invert_y = true
	var angles := CameraSolver.apply_look(0.0, 0.0, Vector2(0.0, -10.0), profile)
	assert_true(angles[1] < 0.0)


func test_pitch_is_clamped_at_the_top() -> void:
	var angles := CameraSolver.apply_look(0.0, 0.0, Vector2(0.0, -100000.0), profile)
	assert_almost_eq(angles[1], profile.get_pitch_max(), 0.0001)


func test_pitch_is_clamped_at_the_bottom() -> void:
	var angles := CameraSolver.apply_look(0.0, 0.0, Vector2(0.0, 100000.0), profile)
	assert_almost_eq(angles[1], profile.get_pitch_min(), 0.0001)


func test_yaw_is_not_clamped() -> void:
	# Wrapping here would make a continuous spin read as a jump to anything
	# watching the value.
	var angles := CameraSolver.apply_look(0.0, 0.0, Vector2(100000.0, 0.0), profile)
	assert_true(absf(angles[0]) > TAU)


func test_sensitivity_scales_the_input() -> void:
	profile.sensitivity = 0.02
	var fast := CameraSolver.apply_look(0.0, 0.0, Vector2(10.0, 0.0), profile)
	profile.sensitivity = 0.01
	var slow := CameraSolver.apply_look(0.0, 0.0, Vector2(10.0, 0.0), profile)
	assert_almost_eq(fast[0], slow[0] * 2.0, 0.0001)


func test_a_null_profile_leaves_the_angles_alone() -> void:
	var angles := CameraSolver.apply_look(1.0, 0.5, Vector2(50.0, 50.0), null)
	assert_almost_eq(angles[0], 1.0)
	assert_almost_eq(angles[1], 0.5)


func test_a_third_person_boom_sits_behind_the_pivot() -> void:
	var offset := CameraSolver.solve_camera_offset(profile)
	assert_almost_eq(offset.z, 4.0, 0.0001, "+Z is behind in Godot")
	assert_almost_eq(offset.y, 0.0, 0.0001)


func test_the_boom_is_a_fixed_arm_and_the_pivot_does_the_swinging() -> void:
	# The pitch pivot is already rotated by pitch. A boom that swung with it as
	# well would apply the rotation twice: the camera would rise at double the
	# rate the view tilted, and looking down would put it behind the head.
	var yaw_pivot := Node3D.new()
	var pitch_pivot := Node3D.new()
	var camera := Camera3D.new()
	entity.add_child(yaw_pivot)
	yaw_pivot.add_child(pitch_pivot)
	pitch_pivot.add_child(camera)
	adapter.yaw_pivot = yaw_pivot
	adapter.pitch_pivot = pitch_pivot
	adapter.camera = camera
	_initialise()

	var level_position := camera.position
	adapter.set_look(0.0, -0.5)

	assert_eq(camera.position, level_position, "the arm did not change length")
	assert_almost_eq(pitch_pivot.rotation.x, -0.5, 0.0001, "the pivot tilted instead")
	assert_true(
		camera.global_position.y > pitch_pivot.global_position.y,
		"and the pivot alone raised the camera, which is what looking down wants"
	)


func test_a_first_person_camera_sits_at_the_pivot() -> void:
	profile.mode = CameraProfile.Mode.FIRST_PERSON
	var offset := CameraSolver.solve_camera_offset(profile)
	assert_almost_eq(offset.z, 0.0)
	assert_almost_eq(offset.y, 0.0)


func test_the_shoulder_offset_applies_in_both_modes() -> void:
	profile.shoulder_offset = 0.6
	assert_almost_eq(CameraSolver.solve_camera_offset(profile).x, 0.6, 0.0001)
	profile.mode = CameraProfile.Mode.FIRST_PERSON
	assert_almost_eq(CameraSolver.solve_camera_offset(profile).x, 0.6, 0.0001)


func test_the_pivot_sits_at_eye_height() -> void:
	assert_almost_eq(CameraSolver.solve_pivot_offset(profile).y, 1.6, 0.0001)


func test_fov_blends_toward_the_sprint_value() -> void:
	var blended := CameraSolver.solve_fov(70.0, true, profile, 0.05)
	assert_almost_eq(blended, 75.0, 0.0001, "100 deg/s for 0.05s")


func test_fov_blend_stops_at_the_target() -> void:
	assert_almost_eq(CameraSolver.solve_fov(70.0, true, profile, 10.0), 80.0, 0.0001)


func test_a_zero_blend_speed_snaps() -> void:
	profile.fov_blend_speed = 0.0
	assert_almost_eq(CameraSolver.solve_fov(70.0, true, profile, 0.05), 80.0)


func test_the_movement_basis_uses_yaw_only() -> void:
	# Pitch must not tilt movement, or looking at the sky walks you backwards.
	var basis := CameraSolver.get_movement_basis(PI * 0.5)
	var forward := -basis.z
	assert_almost_eq(forward.y, 0.0, 0.0001)
	assert_almost_eq(forward.x, -1.0, 0.0001)


# --- Adapter --------------------------------------------------------------

func test_the_adapter_clamps_what_it_is_given() -> void:
	_initialise()
	adapter.set_look(0.0, 10.0)
	assert_almost_eq(adapter.get_pitch(), profile.get_pitch_max(), 0.0001)


func test_look_changes_are_announced() -> void:
	_initialise()
	var seen: Array = []
	adapter.look_changed.connect(
		func(yaw: float, pitch: float) -> void: seen.append([yaw, pitch])
	)
	adapter.set_look(0.5, 0.2)
	adapter.set_look(0.5, 0.2)
	assert_size(seen, 1, "an unchanged look is not a change")


func test_add_look_accumulates() -> void:
	_initialise()
	adapter.add_look(Vector2(10.0, 0.0))
	var first := adapter.get_yaw()
	adapter.add_look(Vector2(10.0, 0.0))
	assert_almost_eq(adapter.get_yaw(), first * 2.0, 0.0001)


func test_the_adapter_drives_the_rig_it_was_given() -> void:
	var yaw_pivot := Node3D.new()
	var pitch_pivot := Node3D.new()
	entity.add_child(yaw_pivot)
	yaw_pivot.add_child(pitch_pivot)
	adapter.yaw_pivot = yaw_pivot
	adapter.pitch_pivot = pitch_pivot
	_initialise()

	adapter.set_look(0.3, 0.2)
	assert_almost_eq(yaw_pivot.rotation.y, 0.3, 0.0001)
	assert_almost_eq(pitch_pivot.rotation.x, 0.2, 0.0001)


func test_a_camera_less_entity_still_tracks_where_it_is_looking() -> void:
	# What lets one character scene serve the player and every NPC in the
	# game: no camera nodes, and the facing is still correct.
	_initialise()
	adapter.set_look(PI * 0.5, 0.4)
	var forward := -adapter.get_movement_basis().z
	assert_almost_eq(forward.x, -1.0, 0.0001)
	assert_almost_eq(forward.y, 0.0, 0.0001, "pitch does not reach movement")


func test_the_adapter_is_inert_without_a_profile() -> void:
	var bare := CameraAdapter.new()
	entity.add_child(bare)
	bare.initialize(EntityContext.create(entity))
	bare.add_look(Vector2(100.0, 100.0))
	assert_almost_eq(bare.get_yaw(), 0.0)
	assert_null(bare.get_profile())


func test_the_profile_comes_from_the_definition() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.player"
	definition.camera = profile
	var from_data := CameraAdapter.new()
	entity.add_child(from_data)
	from_data.initialize(EntityContext.create(entity, definition))
	assert_eq(from_data.get_profile(), profile)


func test_ticking_blends_fov_toward_sprinting() -> void:
	var camera := Camera3D.new()
	entity.add_child(camera)
	adapter.camera = camera

	var movement := MovementComponent.new()
	var movement_profile := MovementProfile.new()
	movement.profile_override = movement_profile
	entity.add_child(movement)
	movement.initialize(EntityContext.create(entity))
	adapter.movement = movement
	_initialise()

	movement.set_sprinting(true)
	movement.tick(0.05)
	adapter.tick(0.05)
	assert_true(adapter.get_fov() > 70.0)
	assert_almost_eq(camera.fov, adapter.get_fov(), 0.0001)


func test_ticking_without_a_camera_does_nothing_bad() -> void:
	_initialise()
	adapter.tick(0.05)
	assert_almost_eq(adapter.get_fov(), 70.0)


# --- Profile validation ---------------------------------------------------

func test_a_sensible_profile_validates_clean() -> void:
	var result := profile.validate()
	assert_false(result.has_errors(), result.format_report())


func test_inverted_pitch_limits_are_an_error() -> void:
	profile.pitch_min_degrees = 80.0
	assert_true(profile.validate().has_errors())


func test_zero_sensitivity_is_an_error() -> void:
	profile.sensitivity = 0.0
	assert_true(profile.validate().has_errors())


func test_an_impossible_fov_is_an_error() -> void:
	profile.fov = 200.0
	assert_true(profile.validate().has_errors())


func test_a_third_person_profile_with_no_boom_is_a_warning() -> void:
	profile.boom_length = 0.0
	var result := profile.validate()
	assert_false(result.has_errors())
	assert_true(result.has_warnings())
