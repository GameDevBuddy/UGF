class_name MovementProfile
extends Resource
## Reusable movement configuration: how fast, how quickly, how high.
##
## This is the profile pattern doing its job (rule 14). One
## [code]movement_human_standard.tres[/code] is shared by every civilian,
## guard, vendor and companion in a project; a heavier variant is a second
## resource, not a second class. Nothing here is per-instance, so hundreds of
## characters point at one of these (rule 2).
##
## Speeds are metres per second. Accelerations are metres per second squared.

@export_group("Speeds")
## Default ground speed.
@export var walk_speed: float = 4.0
## Ground speed while sprinting, when [member can_sprint] allows it.
@export var sprint_speed: float = 7.5
## Ground speed while crouched.
@export var crouch_speed: float = 1.8

@export_group("Acceleration")
## How hard the character accelerates toward the requested velocity on ground.
@export var acceleration: float = 40.0
## How hard it slows when nothing is requested. Separate from acceleration so
## responsive-but-not-slippery is expressible.
@export var deceleration: float = 55.0
## Acceleration while airborne, scaled by [member air_control].
@export var air_acceleration: float = 12.0
## How much of the requested direction applies in the air, 0 to 1. Zero is a
## committed jump; one is full mid-air steering.
@export_range(0.0, 1.0) var air_control: float = 0.35

@export_group("Jumping")
## Upward velocity applied on jump.
@export var jump_velocity: float = 5.0
## Downward acceleration. Positive; it is applied downward.
@export var gravity: float = 18.0
## Terminal velocity, so a long fall does not accumulate without limit.
@export var max_fall_speed: float = 45.0
## Grace period after leaving a ledge during which a jump still works.
##
## Without it, a jump input a frame or two late simply does nothing, which
## reads as the game having missed the press.
@export var coyote_time: float = 0.12
## How long a jump press is remembered while airborne, so a press just before
## landing fires on touchdown instead of being dropped.
@export var jump_buffer: float = 0.15

@export_group("Capabilities")
## Whether this character can sprint at all. A profile is how a character that
## simply cannot run is expressed, rather than a subclass (rule 5).
@export var can_sprint: bool = true
@export var can_crouch: bool = true
@export var can_jump: bool = true
## Whether sprinting is refused while crouched. Almost always true; a profile
## for something that scurries can say otherwise.
@export var sprint_blocked_while_crouching: bool = true


## The ground speed implied by a stance, honouring the capability flags.
func get_speed_for(sprinting: bool, crouching: bool) -> float:
	if crouching and can_crouch:
		if sprinting and can_sprint and not sprint_blocked_while_crouching:
			return sprint_speed
		return crouch_speed
	if sprinting and can_sprint:
		return sprint_speed
	return walk_speed


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if walk_speed <= 0.0:
		result.add_error(
			&"movement_profile.invalid_walk_speed",
			"walk_speed must be positive.",
			resource_path,
			"walk_speed"
		)
	if gravity < 0.0:
		result.add_error(
			&"movement_profile.negative_gravity",
			"gravity is applied downward and must not be negative.",
			resource_path,
			"gravity"
		)
	if can_sprint and sprint_speed < walk_speed:
		result.add_warning(
			&"movement_profile.slow_sprint",
			"sprint_speed is slower than walk_speed, so sprinting slows the character down.",
			resource_path,
			"sprint_speed"
		)
	if can_jump and jump_velocity <= 0.0:
		result.add_warning(
			&"movement_profile.no_jump_height",
			"can_jump is on but jump_velocity is not positive, so jumping does nothing.",
			resource_path,
			"jump_velocity"
		)
	if acceleration <= 0.0:
		result.add_error(
			&"movement_profile.invalid_acceleration",
			"acceleration must be positive or the character can never start moving.",
			resource_path,
			"acceleration"
		)
	return result
