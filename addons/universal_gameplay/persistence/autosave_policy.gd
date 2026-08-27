class_name AutosavePolicy
extends Resource
## When to save without being asked, and how many of those to keep.
##
## Data rather than code, because "every five minutes" and "on every mission
## completion" and "never" are three settings of one thing (rule 11, rule 24).

## Seconds between automatic saves. Zero never saves on a timer.
@export_range(0.0, 7200.0, 1.0, "or_greater") var interval: float = 300.0

## Bus events that trigger a save: [code]mission_completed[/code],
## [code]area_entered[/code]. Event names rather than a coupling to whatever
## publishes them (rule 32).
@export var trigger_events: Array[StringName] = []

## How many autosaves to keep. Older ones are rotated out, so a corrupted
## autosave never costs a player their whole run — the previous one is still
## there.
@export_range(1, 20) var slot_count: int = 3

## Prefix for the rotating slots: [code]autosave_0[/code],
## [code]autosave_1[/code].
@export var slot_prefix: String = "autosave"

## Shortest gap between two autosaves regardless of triggers, so completing
## three objectives in one room does not write three saves.
@export_range(0.0, 600.0, 1.0, "or_greater") var minimum_gap: float = 30.0

## Whether autosaving happens at all. What a hardcore mode and a debug toggle
## move.
@export var enabled: bool = true


func saves_on_a_timer() -> bool:
	return enabled and interval > 0.0


func saves_on_events() -> bool:
	return enabled and not trigger_events.is_empty()


func triggers_on(event_name: StringName) -> bool:
	return enabled and trigger_events.has(event_name)


## The slot to write the [param index]-th autosave to. Rotates, so the oldest
## is the one overwritten.
func get_slot_id(index: int) -> StringName:
	return StringName("%s_%d" % [slot_prefix, posmod(index, maxi(1, slot_count))])


func get_slot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for index in maxi(1, slot_count):
		ids.append(get_slot_id(index))
	return ids


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if enabled and not saves_on_a_timer() and not saves_on_events():
		result.add_warning(
			&"autosave.never",
			(
				"Autosaving is on but has neither an interval nor a trigger "
				+ "event, so it never fires."
			),
			resource_path,
			"interval"
		)
	if minimum_gap > interval and saves_on_a_timer():
		result.add_warning(
			&"autosave.gap_exceeds_interval",
			(
				"The minimum gap of %.0fs is longer than the %.0fs interval, so "
				+ "the interval is not what paces autosaves."
			) % [minimum_gap, interval],
			resource_path,
			"minimum_gap"
		)
	if slot_count == 1:
		result.add_info(
			&"autosave.single_slot",
			(
				"With one autosave slot, a corrupted or badly-timed autosave "
				+ "costs the whole run. Two is the cheapest insurance there is."
			),
			resource_path,
			"slot_count"
		)
	return result
