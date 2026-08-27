class_name TalkAction
extends InteractionAction
## Starts a conversation. The bridge between "press E on the NPC" and dialogue.
##
## An [InteractionAction] rather than anything dialogue-specific, so a
## conversation is reached through exactly the pipeline a door and a pickup
## use: one interaction resource on the NPC, and the M5 exit gate spends
## itself again rather than growing a second path.
##
## It lives in Dialogue rather than in Interaction because that is the
## direction that keeps both removable: a project with no Dialogue module never
## loads this file, and Interaction never learns that conversations exist
## (rule 10).

## Conversation to start regardless of what the target normally says. Blank
## uses the target's own [DialogueComponent].
@export var dialogue_override: DialogueDefinition


func can_execute(context: InteractionContext) -> FrameworkResult:
	var component := _find_dialogue(context)
	if component == null:
		return FrameworkResult.fail(
			&"talk.no_dialogue", "There is nobody here to talk to."
		)
	if component.is_talking():
		return FrameworkResult.fail(
			&"talk.already_talking", "This conversation is already running."
		)
	if dialogue_override == null and not component.can_talk(context.interactor):
		return FrameworkResult.fail(
			&"talk.nothing_to_say", "They have nothing to say right now."
		)
	return FrameworkResult.ok(null)


func execute(context: InteractionContext) -> FrameworkResult:
	var component := _find_dialogue(context)
	if component == null:
		return FrameworkResult.fail(
			&"talk.no_dialogue", "There is nobody here to talk to."
		)
	if dialogue_override != null:
		component.set_dialogue(dialogue_override)
	return component.talk(context.interactor)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if dialogue_override != null:
		result.merge(dialogue_override.validate())
	return result


func _find_dialogue(context: InteractionContext) -> DialogueComponent:
	if context == null or context.target == null:
		return null
	for component in DefinitionBinder.collect_components(context.target):
		if component is DialogueComponent:
			return component as DialogueComponent
	return null
