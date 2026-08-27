class_name InteractionDefinition
extends FrameworkDefinition
## One thing that can be done to something: open, loot, talk, enter, hack.
##
## A target offers a list of these and the framework picks whichever is
## available. That list is why the exit gate for this milestone is four
## different objects on one pipeline: a door offers "Open"; a corpse offers
## "Search"; an NPC offers "Talk"; a car offers "Enter" and "Open Boot". None of
## them is a special case in code -- they are four [code].tres[/code] files
## (rule 11, rule 15).
##
## [b]Duration is the whole of "timed interactions".[/b] Zero completes on the
## press; anything else is a hold, and the interactor reports progress while it
## runs. There is no separate held-interaction type, because there is no
## behaviour a second type would add.

## Semantic verb, for presentation and for analytics: [code]verb.open[/code].
## Distinct from [member prompt], which is prose and localisable.
@export var verb: StringName = &""

## Player-facing line: "Open Door". Blank falls back to the display name.
@export var prompt: String = ""

@export_group("Timing")
## Seconds the interactor must hold. Zero completes immediately.
@export_range(0.0, 60.0, 0.01, "or_greater") var duration: float = 0.0

## Whether releasing or moving away cancels a timed interaction in progress.
## Off makes it a commitment: once begun it finishes.
@export var interruptible: bool = true

## Seconds before this can be used again. Zero means no cooldown.
@export_range(0.0, 600.0, 0.01, "or_greater") var cooldown: float = 0.0

## Whether this can be used more than once at all. Off is a one-shot: a lever
## that welds itself, a note that is read and gone.
@export var repeatable: bool = true

@export_group("Availability")
## Everything that must hold before this is offered.
@export var requirements: Array[InteractionRequirement] = []

## Offered first when several interactions are available. Higher wins.
@export var priority: int = 0

## Offer this even when its requirements are unmet, so the prompt can read
## "Locked" rather than the door appearing to be scenery. The interaction still
## refuses to run.
@export var show_when_unavailable: bool = false

@export_group("Effect")
## What happens on completion. Null is the common case: something connects to
## [signal InteractionComponent.interaction_completed] instead (rule 7).
@export var action: InteractionAction


func get_prompt() -> String:
	if not prompt.is_empty():
		return prompt
	if not display_name.is_empty():
		return display_name
	return String(verb)


func is_timed() -> bool:
	return duration > 0.0


func has_cooldown() -> bool:
	return cooldown > 0.0


func validate() -> ValidationResult:
	var result := super()
	if prompt.is_empty() and display_name.is_empty():
		result.add_warning(
			&"interaction.no_prompt",
			(
				"%s has neither a prompt nor a display name, so its prompt will "
				+ "be its verb or nothing at all."
			) % get_debug_name(),
			resource_path,
			"prompt"
		)
	if duration < 0.0:
		result.add_error(
			&"interaction.negative_duration",
			"%s has a negative duration and could never complete." % get_debug_name(),
			resource_path,
			"duration"
		)
	if cooldown < 0.0:
		result.add_error(
			&"interaction.negative_cooldown",
			"%s has a negative cooldown." % get_debug_name(),
			resource_path,
			"cooldown"
		)
	if not repeatable and has_cooldown():
		result.add_warning(
			&"interaction.cooldown_on_one_shot",
			(
				"%s is not repeatable, so its cooldown will never be waited "
				+ "out."
			) % get_debug_name(),
			resource_path,
			"cooldown"
		)
	for requirement in requirements:
		if requirement == null:
			result.add_warning(
				&"interaction.null_requirement",
				"%s has an empty requirement slot." % get_debug_name(),
				resource_path,
				"requirements"
			)
			continue
		result.merge(requirement.validate())
	if action != null:
		result.merge(action.validate())
	return result
