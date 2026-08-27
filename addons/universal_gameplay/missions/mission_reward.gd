class_name MissionReward
extends Resource
## Something a mission gives back.
##
## The "reward hooks" of Implementation Plan 38, as resources rather than a
## hard-coded list: a project that pays in reputation, in unlocked map markers
## or in a phone call from a character extends this and the framework needs no
## case for it (rule 24).
##
## A reward that cannot be granted reports rather than throwing. A mission that
## completed should stay completed even if the player's bag was full.

## Grants the reward. [param subject] is who the mission was for.
func grant(_runtime: MissionRuntime) -> FrameworkResult:
	return FrameworkResult.ok(null)


## Player-facing line for a completion summary: "250 gold".
func describe() -> String:
	return ""


func validate() -> ValidationResult:
	return ValidationResult.new()


## Grants every reward in order, collecting what failed. Nothing stops the
## mission completing.
static func grant_all(
	rewards: Array[MissionReward], runtime: MissionRuntime
) -> Array[FrameworkResult]:
	var failures: Array[FrameworkResult] = []
	for reward in rewards:
		if reward == null:
			continue
		var result := reward.grant(runtime)
		if result.is_err():
			failures.append(result)
	return failures
