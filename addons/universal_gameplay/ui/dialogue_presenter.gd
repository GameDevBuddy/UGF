class_name DialoguePresenter
extends Presenter
## Publishes a running conversation as text and a list of options.
##
## [b]It cannot advance the conversation.[/b] A widget draws the model and
## calls [method DialogueRuntime.choose] on the runtime the project already
## holds; the presenter is one-way by construction, which is the point of the
## M17 exit gate. A dialogue box that could pick for you is a dialogue box that
## eventually will.

## The conversation to show. Found among this entity's own components when not
## wired — though a HUD usually points it at whoever the player is talking to.
@export var dialogue: DialogueComponent

## Whether unavailable options appear in the model at all. On draws them
## greyed with their reason, which is what makes a locked option legible
## rather than merely absent.
@export var include_unavailable: bool = true

var _runtime: DialogueRuntime = null


func observe() -> void:
	if dialogue == null:
		dialogue = _find(DialogueComponent) as DialogueComponent
	_watch(dialogue, &"conversation_started", _on_started)
	_watch(dialogue, &"conversation_finished", _on_finished)
	_attach(dialogue.get_runtime() if dialogue != null else null)


func stop_observing() -> void:
	_unwatch(dialogue, &"conversation_started", _on_started)
	_unwatch(dialogue, &"conversation_finished", _on_finished)
	_attach(null)


## Points this window at a different speaker. What walking up to a new NPC
## calls.
func show_dialogue(component: DialogueComponent) -> void:
	stop_observing()
	dialogue = component
	observe()
	refresh()


func get_runtime() -> DialogueRuntime:
	return _runtime


func build() -> ViewModel:
	var model := DialogueViewModel.new()
	if _runtime == null:
		return model
	model.present = true
	model.running = _runtime.is_running()
	if not model.running:
		return model

	var definition := _runtime.get_definition()
	model.dialogue_id = definition.id if definition != null else &""
	model.speaker = String(_runtime.get_current_speaker())

	var line := _runtime.get_current_line()
	if line != null:
		model.line = line.text

	model.awaiting_choice = _runtime.is_awaiting_choice()
	if model.awaiting_choice:
		model.choices = _build_choices()
	return model


# --- Internals ------------------------------------------------------------

## Rows rather than [DialogueChoice] resources.
##
## The index is carried explicitly because a widget picks by index and the
## unavailable rows may or may not be in the list — deriving it from the row's
## position would be right until the first project turned
## [member include_unavailable] off.
func _build_choices() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var context := _runtime.get_context()
	var options := _runtime.get_choices()
	for index in options.size():
		var choice := options[index]
		var available := choice.is_available(context)
		if not available and not include_unavailable:
			continue
		rows.append({
			"index": index,
			"id": choice.id,
			"text": choice.get_display_text(context),
			"available": available,
			"tags": choice.tags.duplicate(),
		})
	return rows


## Follows the runtime, which is created per conversation rather than living
## on the component. Re-attaching on every start is why a presenter survives
## one NPC being talked to twice.
func _attach(runtime: DialogueRuntime) -> void:
	if _runtime == runtime:
		return
	_unwatch(_runtime, &"line_shown", _on_line)
	_unwatch(_runtime, &"choices_offered", _on_choices)
	_unwatch(_runtime, &"choice_made", _on_choice_made)
	_runtime = runtime
	_watch(_runtime, &"line_shown", _on_line)
	_watch(_runtime, &"choices_offered", _on_choices)
	_watch(_runtime, &"choice_made", _on_choice_made)


func _on_started(runtime: DialogueRuntime) -> void:
	_attach(runtime)
	refresh()


func _on_finished(_outcome: StringName, _runtime: DialogueRuntime) -> void:
	refresh()
	_attach(null)


func _on_line(_node: LineNode, _context: DialogueContext) -> void:
	refresh()


func _on_choices(_node: ChoiceNode, _choices: Array[DialogueChoice]) -> void:
	refresh()


func _on_choice_made(_choice: DialogueChoice, _context: DialogueContext) -> void:
	refresh()
