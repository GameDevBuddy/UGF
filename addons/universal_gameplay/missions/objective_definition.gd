class_name ObjectiveDefinition
extends FrameworkDefinition
## One thing a mission asks for.
##
## [b]One definition, fourteen kinds.[/b] Implementation Plan 19 lists Kill,
## AcquireItem, TalkTo, ReachArea, SurviveDuration and nine more. They are not
## fourteen classes here, because they differ in which event they count and
## what they require of it -- and both of those are data (rule 11, rule 23).
## A kill objective is [code]actor_died[/code] with a matcher on the
## instigator; an acquire objective is [code]item_acquired[/code] with a
## matcher on the item id. Adding a fifteenth kind creates a
## [code].tres[/code] and no GDScript.
##
## [b]It names no types from other modules.[/b] That is the M9 exit gate: an
## objective that reacts to combat, inventory and dialogue while importing none
## of them (rule 9). The price is that field names are strings, which
## [EventMatcher] documents.

## What this is asking for, for presentation: an icon, a sort order, a tracker
## line. Vocabulary, not behaviour -- the framework does nothing with it.
@export var kind: StringName = &"objective.custom"

## Player-facing line: "Kill 5 bandits". Blank falls back to the display name.
@export_multiline var description: String = ""

@export_group("Progress")
## Bus event this counts. Blank makes the objective progress only through
## [member duration] or an explicit call, which is what a scripted objective
## a cutscene completes wants.
@export var event_name: StringName = &""

## Everything the event must satisfy to count.
@export var matchers: Array[EventMatcher] = []

## How much is needed. Five bandits, ten planks, one conversation.
@export_range(1, 99999) var required_count: int = 1

## Field on the event carrying how much this occurrence is worth: a stack of
## ten arrives as one event worth ten. Blank counts one per event.
@export var count_field: StringName = &""

## Seconds this objective must survive for. Above zero makes it a timed
## objective: progress is elapsed time and events do not advance it.
@export_range(0.0, 86400.0, 0.1, "or_greater") var duration: float = 0.0

@export_group("Failure")
## Bus event that fails this objective. The escort that dies, the alarm that
## is raised.
@export var failure_event_name: StringName = &""

@export var failure_matchers: Array[EventMatcher] = []

@export_group("Behaviour")
## A failed optional objective does not fail its mission. Bonus objectives and
## "without being seen" flourishes.
@export var optional: bool = false

## Not shown in a tracker until it is active. For a twist nobody should read
## in the quest log first.
@export var hidden: bool = false


func get_description() -> String:
	if not description.is_empty():
		return description
	if not display_name.is_empty():
		return display_name
	return String(id)


func is_timed() -> bool:
	return duration > 0.0


func can_fail() -> bool:
	return failure_event_name != &""


## Whether [param event] counts towards this objective.
func matches(event: FrameworkEvent, subject: Node = null) -> bool:
	if event_name == &"" or event == null:
		return false
	if event.get_event_name() != event_name:
		return false
	return EventMatcher.all_match(matchers, event, subject)


## Whether [param event] fails this objective.
func matches_failure(event: FrameworkEvent, subject: Node = null) -> bool:
	if not can_fail() or event == null:
		return false
	if event.get_event_name() != failure_event_name:
		return false
	return EventMatcher.all_match(failure_matchers, event, subject)


## How much one occurrence is worth. Reads [member count_field] off the event
## when there is one, so a stack of ten arrows counts as ten.
func get_count_for(event: FrameworkEvent) -> int:
	if count_field == &"":
		return 1
	var reader := EventMatcher.new()
	reader.field = count_field
	var raw: Variant = reader.read(event)
	if raw == null:
		return 1
	var kind_of := typeof(raw)
	if kind_of == TYPE_INT or kind_of == TYPE_FLOAT:
		return maxi(1, int(raw))
	return 1


func validate() -> ValidationResult:
	var result := super()
	if description.is_empty() and display_name.is_empty():
		result.add_warning(
			&"objective.no_description",
			"%s has nothing to show a player." % get_debug_name(),
			resource_path,
			"description"
		)
	if event_name == &"" and not is_timed():
		result.add_warning(
			&"objective.no_progress_source",
			(
				"%s counts no event and has no duration, so nothing can "
				+ "complete it except an explicit call."
			) % get_debug_name(),
			resource_path,
			"event_name"
		)
	if is_timed() and event_name != &"":
		result.add_warning(
			&"objective.timed_and_counted",
			(
				"%s has both a duration and an event to count; the duration "
				+ "wins and the event is ignored."
			) % get_debug_name(),
			resource_path,
			"duration"
		)
	if is_timed() and required_count > 1:
		result.add_warning(
			&"objective.timed_with_count",
			"%s is timed, so its required count is unused." % get_debug_name(),
			resource_path,
			"required_count"
		)
	if failure_event_name != &"" and failure_event_name == event_name:
		result.add_warning(
			&"objective.same_event_both_ways",
			(
				"%s counts and fails on the same event; the failure is checked "
				+ "first, so it can never make progress."
			) % get_debug_name(),
			resource_path,
			"failure_event_name"
		)
	for matcher in matchers + failure_matchers:
		if matcher != null:
			result.merge(matcher.validate())
	return result
