class_name NarrativeReward
extends MissionReward
## Pays in story: a flag raised, a counter bumped, standing shifted.
##
## The commonest reward in practice, and the one that needs no other module:
## unlocking the next mission, marking the deed done, making the town like you.

enum Operation {
	SET_FLAG,
	INCREMENT_COUNTER,
	MODIFY_RELATIONSHIP,
	SET_VARIABLE,
}

@export var operation: Operation = Operation.SET_FLAG

## The flag, variable or counter name, or the subject party of a relationship.
@export var key: StringName = &""

## The other party, for [constant Operation.MODIFY_RELATIONSHIP].
@export var other: StringName = &""

@export var value: Variant = true


func grant(runtime: MissionRuntime) -> FrameworkResult:
	if key == &"":
		return FrameworkResult.fail(
			&"reward.no_key", "This reward names nothing to change."
		)
	var narrative := runtime.narrative if runtime != null else null
	if narrative == null:
		return FrameworkResult.fail(
			&"reward.no_narrative", "There is no narrative state to write to."
		)

	match operation:
		Operation.SET_FLAG:
			narrative.set_flag(key, bool(value))
		Operation.INCREMENT_COUNTER:
			narrative.increment(key, int(value))
		Operation.MODIFY_RELATIONSHIP:
			narrative.modify_relationship(key, other, float(value))
		Operation.SET_VARIABLE:
			narrative.set_variable(key, value)
	return FrameworkResult.ok(value)


func describe() -> String:
	match operation:
		Operation.INCREMENT_COUNTER:
			return "%s +%s" % [key, str(value)]
		Operation.MODIFY_RELATIONSHIP:
			return "%s towards %s %+.1f" % [key, other, float(value)]
		Operation.SET_VARIABLE:
			return "%s = %s" % [key, str(value)]
	return str(key)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if key == &"":
		result.add_error(
			&"narrative_reward.no_key",
			"A narrative reward that names nothing gives nothing.",
			resource_path,
			"key"
		)
	if operation == Operation.MODIFY_RELATIONSHIP and other == &"":
		result.add_error(
			&"narrative_reward.no_other_party",
			"A relationship reward needs both parties.",
			resource_path,
			"other"
		)
	return result
