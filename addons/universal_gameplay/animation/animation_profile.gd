class_name AnimationProfile
extends Resource
## Maps semantic gameplay state to [AnimationTree] parameters.
##
## The indirection is the point. Without it, gameplay code writes
## [code]"parameters/locomotion/blend_position"[/code] into an
## [AnimationTree] and the framework is now married to one rig's blend-tree
## layout. With it, gameplay says "speed ratio is 0.6" and a resource says
## where that number goes -- so a second character with a different tree is a
## second profile, not a second controller (rule 11).
##
## Every parameter path is optional. An unset path is simply not written,
## which is how a character with a two-state tree and a character with a full
## blend space share one adapter.

@export_group("Parameters")
## Path receiving [method MovementComponent.get_speed_ratio], 0 to 1.
@export var speed_parameter: String = ""
## Path receiving planar speed in metres per second, for trees blending on
## real speed rather than a normalised ratio.
@export var speed_metres_parameter: String = ""
## Path receiving true while airborne.
@export var airborne_parameter: String = ""
## Path receiving true while crouched.
@export var crouch_parameter: String = ""
## Path receiving true while sprinting.
@export var sprint_parameter: String = ""
## Path receiving true while moving under the entity's own power.
@export var moving_parameter: String = ""

@export_group("One-shots")
## Path of a one-shot request fired on jump, e.g.
## [code]parameters/jump/request[/code].
@export var jump_request_parameter: String = ""
## Path of a one-shot request fired on landing.
@export var land_request_parameter: String = ""
## Landing speed below which the landing one-shot is skipped, so stepping off
## a kerb does not play a heavy landing.
@export var land_request_min_speed: float = 4.0

@export_group("Blending")
## How fast the speed parameter moves toward its target, in units per second.
## Zero writes the value directly, letting the tree do its own smoothing.
@export var speed_blend_rate: float = 0.0


## Every configured parameter path, for validation and debug output.
func get_configured_parameters() -> Array[String]:
	var configured: Array[String] = []
	for path in [
		speed_parameter,
		speed_metres_parameter,
		airborne_parameter,
		crouch_parameter,
		sprint_parameter,
		moving_parameter,
		jump_request_parameter,
		land_request_parameter,
	]:
		if not path.is_empty():
			configured.append(path)
	return configured


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if get_configured_parameters().is_empty():
		result.add_warning(
			&"animation_profile.no_parameters",
			"This profile maps no parameters, so it drives nothing.",
			resource_path,
			"speed_parameter"
		)
	if speed_blend_rate < 0.0:
		result.add_error(
			&"animation_profile.negative_blend_rate",
			"speed_blend_rate must not be negative.",
			resource_path,
			"speed_blend_rate"
		)
	return result
