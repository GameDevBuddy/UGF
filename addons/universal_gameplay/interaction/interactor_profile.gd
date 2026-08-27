class_name InteractorProfile
extends Resource
## How far something can reach and how it finds what to reach for.
##
## A shared sub-resource rather than exported values on the component, for the
## same reason [MovementProfile] is: every guard in the game reaches the same
## distance, and that number should be authored once (rule 11, rule 16).

## Metres within which a target can be used. Generous by default: an
## interaction that is refused because the player is four centimetres too far
## away reads as a bug.
@export_range(0.0, 50.0, 0.01, "or_greater") var reach: float = 2.5

@export_group("Focus")
## Scan for a target automatically. Off when something else owns focus -- an
## Area3D on the character, a reticle raycast -- which is the cheaper and more
## accurate arrangement in a busy scene.
@export var auto_focus: bool = true

## Seconds between scans. Focus does not need to be frame-accurate, and a scan
## every frame is exactly the permanent per-frame work rule 26 warns about.
@export_range(0.0, 1.0, 0.01) var focus_interval: float = 0.15

@export_group("Timed interactions")
## Abandon a timed interaction when the target leaves reach. Off lets an
## interaction survive the interactor being shoved, which suits a cutscene-like
## use; on is the usual behaviour.
@export var cancel_when_out_of_reach: bool = true


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if reach <= 0.0:
		result.add_warning(
			&"interactor_profile.no_reach",
			(
				"A reach of zero means nothing can ever be interacted with "
				+ "unless it is exactly underfoot."
			),
			resource_path,
			"reach"
		)
	if auto_focus and focus_interval <= 0.0:
		result.add_warning(
			&"interactor_profile.scan_every_frame",
			(
				"A focus interval of zero scans every interactable in the world "
				+ "every frame."
			),
			resource_path,
			"focus_interval"
		)
	return result
