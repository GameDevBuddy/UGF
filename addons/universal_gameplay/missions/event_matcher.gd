class_name EventMatcher
extends Resource
## One question asked of a [FrameworkEvent], by field name.
##
## [b]This is how the M9 exit gate is met.[/b] An objective that said
## [code]@export var target: CombatComponent[/code] would make Missions import
## Combat; one that reads a named field off whatever event arrived imports
## nothing. A kill objective and a purchase objective differ in an event name
## and a couple of matchers, not in code (rule 9, rule 32).
##
## The cost of that is honest and worth stating: field names are strings, so a
## typo is content that silently never matches rather than a compile error.
## [method validate] cannot catch it -- the event type is not known until one
## arrives -- so [MissionService] reports a matcher that has never matched when
## debug reporting is on.

enum Mode {
	## The field equals the value. Numbers compare across int and float.
	EQUALS,
	NOT_EQUALS,
	GREATER_OR_EQUAL,
	LESS_OR_EQUAL,
	## The field is a [Node] in the SceneTree group named by the value.
	IN_GROUP,
	## The field is an object with a [code]tags[/code] array containing the
	## value, or a [Node] whose components carry it.
	HAS_TAG,
	## The field is the entity the mission is for -- usually the player. What
	## turns "a bandit died" into "you killed a bandit".
	IS_SUBJECT,
	## The field is anything other than null. For "was there an instigator at
	## all".
	IS_PRESENT,
}

## Property or zero-argument method on the event: [code]choice_id[/code],
## [code]get_instigator[/code]. Properties are tried first.
@export var field: StringName = &""

@export var mode: Mode = Mode.EQUALS

## What the field is compared against. Ignored by
## [constant Mode.IS_SUBJECT] and [constant Mode.IS_PRESENT].
@export var value: Variant = null


## Whether this holds for [param event]. [param subject] is the entity the
## mission is for.
func matches(event: FrameworkEvent, subject: Node = null) -> bool:
	if event == null or field == &"":
		return false
	var actual := read(event)
	match mode:
		Mode.EQUALS:
			return _equal(actual, value)
		Mode.NOT_EQUALS:
			return not _equal(actual, value)
		Mode.GREATER_OR_EQUAL:
			return _as_number(actual) >= _as_number(value)
		Mode.LESS_OR_EQUAL:
			return _as_number(actual) <= _as_number(value)
		Mode.IN_GROUP:
			return actual is Node and (actual as Node).is_in_group(StringName(value))
		Mode.HAS_TAG:
			return _has_tag(actual, StringName(value))
		Mode.IS_SUBJECT:
			return subject != null and actual == subject
		Mode.IS_PRESENT:
			return actual != null
	return false


## Reads the field off an event: property first, then zero-argument method.
##
## Public because [ObjectiveDefinition] reads a count off an event the same
## way, and two spellings of "get this field" would drift apart.
func read(event: Object) -> Variant:
	if event == null or field == &"":
		return null
	for property in event.get_property_list():
		if property["name"] == String(field):
			return event.get(field)
	# Zero-argument methods only. has_method() says nothing about arity, and
	# calling a one-argument method with none is a runtime error rather than a
	# miss -- which would turn a mistyped field into a crash instead of an
	# objective that never progresses.
	for method in event.get_method_list():
		if method["name"] == String(field) and (method["args"] as Array).is_empty():
			return event.call(field)
	return null


func describe() -> String:
	match mode:
		Mode.IS_SUBJECT:
			return "%s is the mission's subject" % field
		Mode.IS_PRESENT:
			return "%s is present" % field
		Mode.IN_GROUP:
			return "%s is in group %s" % [field, str(value)]
		Mode.HAS_TAG:
			return "%s is tagged %s" % [field, str(value)]
	return "%s %s %s" % [field, _symbol(), str(value)]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if field == &"":
		result.add_error(
			&"matcher.no_field",
			"A matcher that names no field can never match anything.",
			resource_path,
			"field"
		)
	var needs_value := (
		mode != Mode.IS_SUBJECT and mode != Mode.IS_PRESENT
	)
	if needs_value and value == null:
		result.add_warning(
			&"matcher.no_value",
			(
				"Matcher on '%s' compares against nothing, which will only "
				+ "match a null field."
			) % field,
			resource_path,
			"value"
		)
	return result


## True when every matcher holds. Null entries are skipped rather than
## failing, so an empty slot does not silently stall an objective.
static func all_match(
	matchers: Array[EventMatcher], event: FrameworkEvent, subject: Node = null
) -> bool:
	for matcher in matchers:
		if matcher != null and not matcher.matches(event, subject):
			return false
	return true


# --- Internals ------------------------------------------------------------

func _equal(actual: Variant, expected: Variant) -> bool:
	if _is_number(actual) and _is_number(expected):
		return is_equal_approx(_as_number(actual), _as_number(expected))
	if typeof(actual) == TYPE_STRING_NAME or typeof(expected) == TYPE_STRING_NAME:
		# A designer writing "choice.accept" and content storing &"choice.accept"
		# mean the same thing, and refusing that is a trap.
		return String(actual) == String(expected)
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


## Tags may be the field itself (an event carrying an item's tags), live on the
## object the field points at, or live on one of an entity's components.
## Checked in that order, so "tagged bandit" works whether the tag is on the
## event payload, the definition or the [Perceivable].
func _has_tag(actual: Variant, tag: StringName) -> bool:
	if actual == null:
		return false
	# The field may be the tag list itself: an event carrying the item's tags
	# is the direct case, and casting an Array to Object would error.
	if actual is Array:
		return (actual as Array).has(tag)
	if not actual is Object:
		return false
	if _object_has_tag(actual as Object, tag):
		return true
	var node := actual as Node
	if node == null:
		return false
	for component in DefinitionBinder.collect_components(node):
		if _object_has_tag(component, tag):
			return true
	return false


func _object_has_tag(candidate: Object, tag: StringName) -> bool:
	if candidate == null:
		return false
	if not "tags" in candidate:
		return false
	var tags: Variant = candidate.get("tags")
	return tags is Array and (tags as Array).has(tag)


func _symbol() -> String:
	match mode:
		Mode.NOT_EQUALS:
			return "!="
		Mode.GREATER_OR_EQUAL:
			return ">="
		Mode.LESS_OR_EQUAL:
			return "<="
	return "=="
