class_name DialogueViewModel
extends ViewModel
## What a conversation window draws.
##
## [b]This is the presenter M8 deliberately did not ship.[/b] That milestone
## left [DialogueRuntime] emitting signals and drew nothing, on the grounds
## that a dialogue box is a project's decision about its own look. That is
## still true — and it is also true that every project needs the same four
## things out of a running conversation, which is what this is.

## Who is speaking, as authored.
var speaker: String = ""

## What they said.
var line: String = ""

## The options, if the conversation is waiting on one. Each row carries the
## text, whether it is selectable, and why not when it is not — so a greyed-out
## option can say "Requires 50 credits" rather than simply vanishing.
var choices: Array[Dictionary] = []

## Whether the conversation is waiting for the player to pick.
var awaiting_choice: bool = false

## Whether it is still running at all.
var running: bool = false

## The conversation's id, for a project keying portraits or music off it.
var dialogue_id: StringName = &""


func has_choices() -> bool:
	return not choices.is_empty()


func get_choice(index: int) -> Dictionary:
	if index < 0 or index >= choices.size():
		return {}
	return choices[index]


func is_choice_available(index: int) -> bool:
	return bool(get_choice(index).get("available", false))


## Only the options the player can actually pick. What a project drawing a
## short list uses, where one drawing greyed-out rows uses [member choices].
func get_available_choices() -> Array[Dictionary]:
	return choices.filter(
		func(choice: Dictionary) -> bool: return bool(choice.get("available", false))
	)


func to_dictionary() -> Dictionary:
	var data := super()
	data.merge({
		"dialogue_id": dialogue_id,
		"speaker": speaker,
		"line": line,
		"choices": choices.duplicate(true),
		"awaiting_choice": awaiting_choice,
		"running": running,
	})
	return data
