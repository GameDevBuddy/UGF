class_name CameraProfile
extends Resource
## Reusable camera configuration for one view mode.
##
## Camera feel is content, not code (rule 11). Changing a game from
## over-the-shoulder to top-down, or making the aim camera pull in tighter,
## should be a resource edit. A profile per view mode, shared by every
## character that uses it.

enum Mode {
	## Camera sits at the pivot. [member boom_length] is ignored.
	FIRST_PERSON,
	## Camera sits behind the pivot at [member boom_length].
	THIRD_PERSON,
}

@export var mode: Mode = Mode.THIRD_PERSON

@export_group("Framing")
## Distance behind the pivot in third person, in metres.
@export var boom_length: float = 4.0
## Height of the pivot above the entity's origin.
@export var pivot_height: float = 1.6
## Lateral offset, for an over-the-shoulder framing. Positive is right.
@export var shoulder_offset: float = 0.0

@export_group("Look")
## Radians per unit of look input.
@export var sensitivity: float = 0.003
## Lowest pitch, in degrees. Negative looks down.
@export var pitch_min_degrees: float = -75.0
## Highest pitch, in degrees.
@export var pitch_max_degrees: float = 70.0
## Invert vertical look.
@export var invert_y: bool = false

@export_group("Field of view")
@export var fov: float = 70.0
## FOV while sprinting, for the speed cue. Equal to [member fov] disables it.
@export var sprint_fov: float = 78.0
## How fast the FOV moves between the two, in degrees per second.
@export var fov_blend_speed: float = 90.0


func get_pitch_min() -> float:
	return deg_to_rad(pitch_min_degrees)


func get_pitch_max() -> float:
	return deg_to_rad(pitch_max_degrees)


func is_first_person() -> bool:
	return mode == Mode.FIRST_PERSON


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if pitch_min_degrees >= pitch_max_degrees:
		result.add_error(
			&"camera_profile.inverted_pitch_limits",
			"pitch_min_degrees must be below pitch_max_degrees.",
			resource_path,
			"pitch_min_degrees"
		)
	if mode == Mode.THIRD_PERSON and boom_length <= 0.0:
		result.add_warning(
			&"camera_profile.no_boom",
			"A third-person profile with no boom length sits inside the character.",
			resource_path,
			"boom_length"
		)
	if sensitivity <= 0.0:
		result.add_error(
			&"camera_profile.invalid_sensitivity",
			"sensitivity must be positive or looking around does nothing.",
			resource_path,
			"sensitivity"
		)
	if fov <= 0.0 or fov >= 180.0:
		result.add_error(
			&"camera_profile.invalid_fov",
			"fov must be between 0 and 180 degrees.",
			resource_path,
			"fov"
		)
	return result
