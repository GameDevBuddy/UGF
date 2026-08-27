class_name PerceptionProfile
extends Resource
## What an entity can notice, and how long it stays noticed.
##
## Shared design-time data, so every guard in the game sees the same distance
## and forgets at the same rate without any of them holding their own copy
## (rule 11, rule 16). A civilian and a sniper are this resource with different
## numbers, not two scripts.

@export_group("Sight")
## Metres this entity can see. Zero blinds it, which is a legitimate state for
## something that only hears.
@export_range(0.0, 200.0, 0.1, "or_greater") var sight_range: float = 20.0

## Full field of view in degrees. 360 sees behind itself, which is right for a
## security camera and wrong for a person.
@export_range(0.0, 360.0, 1.0) var sight_angle: float = 110.0

## Seconds a target must stay in view before it is noticed. Zero notices
## instantly; anything above it is the reaction time that makes sneaking past
## a guard possible.
@export_range(0.0, 10.0, 0.01) var notice_time: float = 0.4

@export_group("Hearing")
## Metres a sound of loudness one carries. Louder sounds carry further.
@export_range(0.0, 200.0, 0.1, "or_greater") var hearing_range: float = 15.0

@export_group("Memory")
## Seconds a target stays remembered after it was last perceived. The whole of
## "search the last place you saw them" is this number being above zero.
@export_range(0.0, 300.0, 0.1, "or_greater") var memory_duration: float = 8.0

## Seconds between sweeps. Perception does not need to be frame-accurate, and
## a scan every frame is the permanent per-frame work rule 26 warns about.
@export_range(0.0, 2.0, 0.01) var scan_interval: float = 0.2

@export_group("Line of sight")
## Whether sight is blocked by geometry. Off is cheaper and right for a
## top-down game with no occluders.
@export var requires_line_of_sight: bool = true

## Metres above the entity's origin that its eyes are.
@export_range(0.0, 5.0, 0.01) var eye_height: float = 1.6


func can_see_at_all() -> bool:
	return sight_range > 0.0 and sight_angle > 0.0


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if not can_see_at_all() and hearing_range <= 0.0:
		result.add_warning(
			&"perception.senseless",
			"This profile can neither see nor hear, so it will never notice anything.",
			resource_path,
			"sight_range"
		)
	if memory_duration <= 0.0 and notice_time > 0.0:
		result.add_warning(
			&"perception.forgets_instantly",
			(
				"Targets are forgotten the moment they leave view, so an entity "
				+ "with a notice time will never finish noticing anything that moves."
			),
			resource_path,
			"memory_duration"
		)
	return result
