class_name DialogueComponent
extends FrameworkComponent
## The capability of being talked to.
##
## Hangs a [DialogueRuntime] off an NPC and wires it to whatever is around:
## the narrative service for flags, the interaction component for a "Talk"
## prompt, the input router for a context that suppresses walking while a
## conversation is up.
##
## [b]Thin on purpose.[/b] The conversation itself lives in the runtime, which
## needs no scene; this is the part that needs one. Splitting them is what lets
## a whole branching dialogue be tested in microseconds and what would let a
## project drive the same conversation from a cutscene, a terminal or a letter.

## Emitted when a conversation starts here.
signal conversation_started(runtime: DialogueRuntime)
## Emitted when one ends, with the outcome of the End node it reached.
signal conversation_finished(outcome: StringName, runtime: DialogueRuntime)
## Emitted per option taken, so a project can react without subscribing to the
## runtime it does not own.
signal choice_taken(choice: DialogueChoice)

## What this entity says. Takes precedence over the definition's.
@export var dialogue_override: DialogueDefinition

## Narrative state read and written by conditions and actions. Resolved from
## the core's service registry when not wired; null still runs conversations,
## it just gives them nothing to remember (rule 31).
@export var narrative: NarrativeStateService

## Input context pushed while a conversation is running, so walking and
## shooting stop without dialogue knowing what either of those are. Blank uses
## the standard dialogue context.
@export var input_context: InputContext

## Push an input context at all. Off for a conversation that plays over the top
## of live gameplay: a radio call, a companion barking.
@export var suppresses_control: bool = true

var _definition: DialogueDefinition = null
var _runtime: DialogueRuntime = null
var _router: InputRouter = null
var _pushed_context: InputContext = null
var _completed: Dictionary[StringName, bool] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_definition = _resolve_definition()
	if narrative == null:
		narrative = _resolve_narrative()


func _exit_tree() -> void:
	# A conversation whose speaker leaves the tree ends, rather than leaving an
	# input context pushed forever and the player unable to move.
	if is_talking():
		_runtime.stop(&"speaker_gone")


## Named get_dialogue rather than get_definition because
## [method FrameworkComponent.get_definition] already means the entity's
## definition, and GDScript will not let one name return two types anyway.
func get_dialogue() -> DialogueDefinition:
	return _definition


## The conversation in progress, or null.
func get_runtime() -> DialogueRuntime:
	return _runtime


func is_talking() -> bool:
	return _runtime != null and _runtime.is_running()


## Whether this entity has anything to say to [param listener] right now.
func can_talk(listener: Node = null) -> bool:
	if _definition == null or is_talking():
		return false
	if not _definition.repeatable and _completed.get(_definition.id, false):
		return false
	return _definition.is_available(make_context(listener))


## Builds the context a conversation would run in. Exposed because a caller
## needs it to ask whether a conversation is available before starting one.
func make_context(listener: Node = null) -> DialogueContext:
	return DialogueContext.create(get_entity(), listener, _definition, narrative)


## Starts a conversation with [param listener].
func talk(listener: Node = null) -> FrameworkResult:
	if _definition == null:
		return FrameworkResult.fail(
			&"dialogue.nothing_to_say", "This entity has no dialogue."
		)
	if is_talking():
		return FrameworkResult.fail(
			&"dialogue.already_talking", "This conversation is already running."
		)
	if not _definition.repeatable and _completed.get(_definition.id, false):
		return FrameworkResult.fail(
			&"dialogue.already_had", "This conversation has already been had."
		)

	var context := make_context(listener)
	if not _definition.is_available(context):
		return FrameworkResult.fail(
			&"dialogue.unavailable", "There is nothing to say right now."
		)

	_runtime = DialogueRuntime.new()
	_runtime.choice_made.connect(_on_choice_made)
	_runtime.finished.connect(_on_finished)

	var started := _runtime.start(_definition, context)
	if started.is_err():
		_runtime = null
		return started

	_push_input_context()
	conversation_started.emit(_runtime)
	return FrameworkResult.ok(_runtime)


## Ends a conversation early. What walking away calls.
func stop(outcome: StringName = &"aborted") -> FrameworkResult:
	if not is_talking():
		return FrameworkResult.fail(&"dialogue.not_talking", "Nobody is talking.")
	return _runtime.stop(outcome)


## Injects the input router directly. An injected one wins over the service
## registry, which is what split-screen needs: two players in two
## conversations must not share one context stack.
func set_router(router: InputRouter) -> void:
	_router = router


func get_router() -> InputRouter:
	return _router


## Hands this entity a different conversation. What a quest stage does when the
## same NPC should start saying something else.
func set_dialogue(definition: DialogueDefinition) -> void:
	if is_talking():
		_runtime.stop(&"dialogue_replaced")
	_definition = definition


## Whether a one-shot conversation has already been had.
func has_completed(dialogue_id: StringName) -> bool:
	return _completed.get(dialogue_id, false)


# --- Persistence ----------------------------------------------------------
#
# Which one-shot conversations have been had survives; a conversation in
# progress does not. Reloading into the middle of a sentence with a listener
# who may no longer exist is worse than starting it again.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var had: Array[String] = []
	for key in _completed:
		had.append(String(key))
	return {"completed": had}


func restore_state(data: Dictionary) -> void:
	_completed.clear()
	for key in data.get("completed", []):
		_completed[StringName(key)] = true


# --- Internals ------------------------------------------------------------

func _on_choice_made(choice: DialogueChoice, _context: DialogueContext) -> void:
	choice_taken.emit(choice)


func _on_finished(outcome: StringName, _context: DialogueContext) -> void:
	if _definition != null and not _definition.repeatable:
		_completed[_definition.id] = true
	_pop_input_context()
	var finished_runtime := _runtime
	_runtime = null
	conversation_finished.emit(outcome, finished_runtime)


func _push_input_context() -> void:
	if not suppresses_control:
		return
	if _router == null:
		_router = _resolve_router()
	if _router == null:
		return
	_pushed_context = input_context if input_context != null else InputContexts.dialogue()
	_router.push_context(_pushed_context)


func _pop_input_context() -> void:
	if _router == null or _pushed_context == null:
		return
	# By instance, not by id: two NPCs talking at once push contexts with the
	# same id, and removing by id would take whichever pushed last.
	_router.remove_context_instance(_pushed_context)
	_pushed_context = null


func _resolve_router() -> InputRouter:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_INPUT) as InputRouter


func _resolve_narrative() -> NarrativeStateService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_NARRATIVE) as NarrativeStateService


## Read by property name rather than by casting, so a terminal or a note with
## its own definition type can be talked to (rule 9).
func _resolve_definition() -> DialogueDefinition:
	if dialogue_override != null:
		return dialogue_override
	var definition := get_definition()
	if definition != null and "dialogue" in definition:
		var candidate: Variant = definition.get("dialogue")
		if candidate is DialogueDefinition:
			return candidate as DialogueDefinition
	return null
