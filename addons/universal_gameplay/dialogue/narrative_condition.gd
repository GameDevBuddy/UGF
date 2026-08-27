class_name NarrativeCondition
extends DialogueCondition
## Asks the narrative state a question: is this flag raised, is this counter
## high enough, does this faction like us.
##
## One resource with a subject and a comparison rather than four condition
## classes, because the four differ in which store they read and in nothing
## else (rule 23).

enum Subject {
	## A fact that either happened or did not.
	FLAG,
	## A named value.
	VARIABLE,
	## A tally.
	COUNTER,
	## How one named party feels about another.
	RELATIONSHIP,
}

enum Comparison {
	EQUAL,
	NOT_EQUAL,
	GREATER,
	GREATER_OR_EQUAL,
	LESS,
	LESS_OR_EQUAL,
}

@export var subject: Subject = Subject.FLAG

## What is being asked about: the flag, variable or counter name, or the
## subject party of a relationship.
@export var key: StringName = &""

## The other party, for [constant Subject.RELATIONSHIP]. Ignored otherwise.
@export var other: StringName = &""

@export var comparison: Comparison = Comparison.EQUAL

## What it is compared against. For a flag, a bool; for a counter or a
## relationship, a number.
@export var value: Variant = true


func evaluate(context: DialogueContext) -> bool:
	if context == null or key == &"":
		return false
	match subject:
		Subject.FLAG:
			return _compare(context.get_flag(key), value)
		Subject.VARIABLE:
			return _compare(context.get_variable(key), value)
		Subject.COUNTER:
			return _compare(context.get_counter(key), value)
		Subject.RELATIONSHIP:
			var standing := 0.0
			if context.narrative != null:
				standing = context.narrative.get_relationship(key, other)
			return _compare(standing, value)
	return false


func describe() -> String:
	if subject == Subject.RELATIONSHIP:
		return "%s towards %s %s %s" % [key, other, _symbol(), str(value)]
	return "%s %s %s" % [key, _symbol(), str(value)]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if key == &"":
		result.add_error(
			&"narrative_condition.no_key",
			"A narrative condition that names nothing can never be answered.",
			resource_path,
			"key"
		)
	if subject == Subject.RELATIONSHIP and other == &"":
		result.add_error(
			&"narrative_condition.no_other_party",
			"A relationship condition needs both parties.",
			resource_path,
			"other"
		)
	if subject == Subject.FLAG and typeof(value) != TYPE_BOOL:
		result.add_warning(
			&"narrative_condition.flag_compared_to_non_bool",
			"A flag is true or false; comparing it to %s will not do what it looks like." % str(value),
			resource_path,
			"value"
		)
	var ordered := comparison != Comparison.EQUAL and comparison != Comparison.NOT_EQUAL
	if subject == Subject.FLAG and ordered:
		result.add_warning(
			&"narrative_condition.ordered_flag",
			"A flag has no ordering, so a greater/less comparison on one is meaningless.",
			resource_path,
			"comparison"
		)
	return result


# --- Internals ------------------------------------------------------------

func _compare(actual: Variant, expected: Variant) -> bool:
	match comparison:
		Comparison.EQUAL:
			return _equal(actual, expected)
		Comparison.NOT_EQUAL:
			return not _equal(actual, expected)
		Comparison.GREATER:
			return _as_number(actual) > _as_number(expected)
		Comparison.GREATER_OR_EQUAL:
			return _as_number(actual) >= _as_number(expected)
		Comparison.LESS:
			return _as_number(actual) < _as_number(expected)
		Comparison.LESS_OR_EQUAL:
			return _as_number(actual) <= _as_number(expected)
	return false


## Equality across types that a designer would call equal: a counter of 3 and
## an authored 3.0 are the same answer, and refusing that is a trap nobody
## enjoys finding in a shipped conversation.
func _equal(actual: Variant, expected: Variant) -> bool:
	if _is_number(actual) and _is_number(expected):
		return is_equal_approx(_as_number(actual), _as_number(expected))
	if typeof(actual) == TYPE_NIL or typeof(expected) == TYPE_NIL:
		return typeof(actual) == typeof(expected)
	return actual == expected


func _is_number(v: Variant) -> bool:
	var kind := typeof(v)
	return kind == TYPE_INT or kind == TYPE_FLOAT or kind == TYPE_BOOL


func _as_number(v: Variant) -> float:
	match typeof(v):
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_INT, TYPE_FLOAT:
			return float(v)
	return 0.0


func _symbol() -> String:
	match comparison:
		Comparison.NOT_EQUAL:
			return "!="
		Comparison.GREATER:
			return ">"
		Comparison.GREATER_OR_EQUAL:
			return ">="
		Comparison.LESS:
			return "<"
		Comparison.LESS_OR_EQUAL:
			return "<="
	return "=="
