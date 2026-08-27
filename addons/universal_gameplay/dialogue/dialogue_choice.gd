class_name DialogueChoice
extends Resource
## One thing the player can say.
##
## Conditions decide whether it is offered at all; actions run only if it is
## actually picked. That split is the whole reason conditions must be free of
## side effects -- a condition on an option nobody chose still ran.

## Stable identity, so "which option did they take" survives the option list
## being reordered, and so an event carries something a mission can match on.
@export var id: StringName = &""

## What the option reads as.
@export_multiline var text: String = ""

## Everything that must hold for this option to appear.
@export var conditions: Array[DialogueCondition] = []

## Run when this option is chosen, and not otherwise.
@export var actions: Array[DialogueAction] = []

## Node the conversation goes to. Blank ends it.
@export var next: StringName = &""

## Show the option greyed out when its conditions fail, rather than hiding it.
## "[Persuade] (requires 60 Speech)" is a better conversation than an option
## the player never learns existed.
@export var show_when_unavailable: bool = false

## Reason shown when it is unavailable. Blank falls back to the option's text.
@export_multiline var unavailable_text: String = ""

## Semantic tags a presenter or a mission matches on: [code]choice.hostile[/code].
@export var tags: Array[StringName] = []


func is_available(context: DialogueContext) -> bool:
	return DialogueCondition.all_hold(conditions, context)


## Whether this appears in the list at all, available or not.
func is_visible(context: DialogueContext) -> bool:
	return show_when_unavailable or is_available(context)


func get_display_text(context: DialogueContext) -> String:
	if is_available(context) or unavailable_text.is_empty():
		return text
	return unavailable_text


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if id == &"":
		result.add_warning(
			&"choice.no_id",
			"Choice '%s' has no id, so events about it cannot be matched on." % text,
			resource_path,
			"id"
		)
	if text.is_empty():
		result.add_error(
			&"choice.no_text",
			"A choice with no text is an option the player cannot read.",
			resource_path,
			"text"
		)
	if show_when_unavailable and unavailable_text.is_empty():
		result.add_info(
			&"choice.no_unavailable_text",
			(
				"Choice '%s' is shown when unavailable but says nothing about "
				+ "why, so it will read as an option that simply does nothing."
			) % text,
			resource_path,
			"unavailable_text"
		)
	for condition in conditions:
		if condition != null:
			result.merge(condition.validate())
	for action in actions:
		if action != null:
			result.merge(action.validate())
	return result
