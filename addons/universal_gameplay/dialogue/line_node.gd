class_name LineNode
extends DialogueNode
## Somebody says something, and the conversation waits.
##
## The commonest node by a wide margin, and the only one that produces text a
## presenter shows.

## Who is speaking, as a semantic name rather than a node reference: a line
## belongs to a conversation, not to a scene (rule 32). Blank means the
## conversation's own default speaker.
@export var speaker: StringName = &""

## What they say. Free text, and the one field a localisation pass touches.
@export_multiline var text: String = ""

## Semantic tags a presenter matches on: [code]line.shout[/code],
## [code]line.whisper[/code]. Not an enum Core would have to own.
@export var tags: Array[StringName] = []


func waits_for_input() -> bool:
	return true


func validate() -> ValidationResult:
	var result := super()
	if text.is_empty():
		result.add_warning(
			&"line.no_text",
			"Line '%s' has no text, so it will show an empty box." % id,
			resource_path,
			"text"
		)
	return result
