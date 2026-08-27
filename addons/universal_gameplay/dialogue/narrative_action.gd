class_name NarrativeAction
extends DialogueAction
## Writes to the narrative state: raise a flag, set a variable, bump a counter,
## change how a faction feels.
##
## The mirror of [NarrativeCondition], and one resource for the same reason:
## four operations that differ only in which store they touch.

enum Operation {
	## Raises or clears a flag.
	SET_FLAG,
	## Assigns a variable.
	SET_VARIABLE,
	## Adds to a counter. Negative amounts subtract.
	INCREMENT_COUNTER,
	## Adjusts standing between two named parties.
	MODIFY_RELATIONSHIP,
	## Sets a value scoped to this conversation only, cleared when it ends.
	SET_LOCAL,
}

@export var operation: Operation = Operation.SET_FLAG

## The flag, variable or counter name, or the subject party of a relationship.
@export var key: StringName = &""

## The other party, for [constant Operation.MODIFY_RELATIONSHIP].
@export var other: StringName = &""

## What to set or add. A bool for a flag, a number for a counter or a
## relationship, anything for a variable.
@export var value: Variant = true


func execute(context: DialogueContext) -> FrameworkResult:
	if context == null or key == &"":
		return FrameworkResult.fail(
			&"narrative_action.no_key", "This action names nothing to change."
		)
	if operation == Operation.SET_LOCAL:
		context.locals[key] = value
		return FrameworkResult.ok(value)

	if context.narrative == null:
		# A conversation with consequences running in a project that installed
		# no narrative service is content that expects more than the build
		# provides. Reporting it beats pretending it worked.
		return FrameworkResult.fail(
			&"narrative_action.no_service",
			"There is no narrative state to write to."
		)

	match operation:
		Operation.SET_FLAG:
			context.narrative.set_flag(key, bool(value))
		Operation.SET_VARIABLE:
			context.narrative.set_variable(key, value)
		Operation.INCREMENT_COUNTER:
			context.narrative.increment(key, int(value))
		Operation.MODIFY_RELATIONSHIP:
			context.narrative.modify_relationship(key, other, float(value))
	return FrameworkResult.ok(value)


func describe() -> String:
	match operation:
		Operation.SET_VARIABLE:
			return "%s = %s" % [key, str(value)]
		Operation.INCREMENT_COUNTER:
			return "%s += %s" % [key, str(value)]
		Operation.MODIFY_RELATIONSHIP:
			return "%s towards %s %+.1f" % [key, other, float(value)]
		Operation.SET_LOCAL:
			return "local %s = %s" % [key, str(value)]
	return "%s = %s" % [key, str(bool(value))]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if key == &"":
		result.add_error(
			&"narrative_action.no_key",
			"A narrative action that names nothing changes nothing.",
			resource_path,
			"key"
		)
	if operation == Operation.MODIFY_RELATIONSHIP and other == &"":
		result.add_error(
			&"narrative_action.no_other_party",
			"A relationship action needs both parties.",
			resource_path,
			"other"
		)
	if operation == Operation.INCREMENT_COUNTER and int(value) == 0:
		result.add_warning(
			&"narrative_action.zero_increment",
			"Incrementing %s by zero does nothing." % key,
			resource_path,
			"value"
		)
	return result
