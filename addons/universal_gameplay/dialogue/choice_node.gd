class_name ChoiceNode
extends DialogueNode
## The conversation stops and the player picks.
##
## What makes a conversation branching rather than a cutscene, and the node
## that produces the cross-feature event the M8 exit gate asks for: a mission
## that turns on which answer was given subscribes to the choice, and never
## reads the dialogue's internals to do it.

## Optional line shown above the options: the question being answered.
@export_multiline var prompt: String = ""

## Who is asking. Blank means the conversation's default speaker.
@export var speaker: StringName = &""

@export var choices: Array[DialogueChoice] = []


func waits_for_input() -> bool:
	return true


## The options to show, in authored order. Excludes anything whose conditions
## fail unless it asked to be shown anyway.
func get_visible_choices(context: DialogueContext) -> Array[DialogueChoice]:
	var visible: Array[DialogueChoice] = []
	for choice in choices:
		if choice != null and choice.is_visible(context):
			visible.append(choice)
	return visible


## The options that can actually be taken.
func get_available_choices(context: DialogueContext) -> Array[DialogueChoice]:
	var available: Array[DialogueChoice] = []
	for choice in choices:
		if choice != null and choice.is_available(context):
			available.append(choice)
	return available


func find_choice(choice_id: StringName) -> DialogueChoice:
	for choice in choices:
		if choice != null and choice.id == choice_id:
			return choice
	return null


func validate() -> ValidationResult:
	var result := super()
	if choices.is_empty():
		result.add_error(
			&"choice_node.no_choices",
			"Choice node '%s' offers nothing, so the conversation would stall on it." % id,
			resource_path,
			"choices"
		)
	var seen: Dictionary[StringName, bool] = {}
	for choice in choices:
		if choice == null:
			result.add_warning(
				&"choice_node.empty_slot",
				"Choice node '%s' has an empty option slot." % id,
				resource_path,
				"choices"
			)
			continue
		if choice.id != &"" and seen.has(choice.id):
			result.add_error(
				&"choice_node.duplicate_choice_id",
				(
					"Choice node '%s' has two options with id '%s', so an event "
					+ "about one is indistinguishable from the other."
				) % [id, choice.id],
				resource_path,
				"choices"
			)
		seen[choice.id] = true
		result.merge(choice.validate())
	return result


func get_outgoing() -> Array[StringName]:
	var out := super()
	for choice in choices:
		if choice != null and choice.next != &"":
			out.append(choice.next)
	return out
