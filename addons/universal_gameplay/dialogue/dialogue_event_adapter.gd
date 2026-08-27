class_name DialogueEventAdapter
extends FrameworkComponent
## Promotes a conversation's local signals to cross-feature facts on the bus.
##
## The same seam [HealthEventAdapter] is, and here for the same three reasons:
## the dialogue runtime stays testable with no bus in existence, the bus stays
## an optional dependency, and "is this conversation worth telling the whole
## game about?" becomes per-entity data rather than a hard-coded yes.
##
## [b]This is the half of the M8 exit gate that says "events emitted for
## choices".[/b] A mission subscribes to
## [constant GameplayNames.EVENT_DIALOGUE_CHOICE] and matches on a choice id or
## a tag; it never reads a [DialogueDefinition], never holds a
## [DialogueRuntime], and does not stop working when the NPC who offered the
## job is unloaded.

## Emitted after publication, for debug tooling watching the promotion happen.
signal dialogue_published(event: FrameworkEvent)

## The conversation to observe, wired at composition time (rule 20).
@export var dialogue: DialogueComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

## Whether this entity's conversations are facts the rest of the game hears.
## An ambient crowd barking one-liners can turn it off.
@export var publish_completion: bool = true

@export var publish_choices: bool = true

const CompletedEvent := preload(
	"res://addons/universal_gameplay/dialogue/dialogue_event.gd"
)
const ChoiceEvent := preload(
	"res://addons/universal_gameplay/dialogue/dialogue_choice_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if dialogue == null:
		dialogue = _find_dialogue()
	_bus = event_bus if event_bus != null else _find_bus()
	_register_events()
	if dialogue == null:
		return
	if not dialogue.conversation_finished.is_connected(_on_finished):
		dialogue.conversation_finished.connect(_on_finished)
	if not dialogue.choice_taken.is_connected(_on_choice):
		dialogue.choice_taken.connect(_on_choice)


func _exit_tree() -> void:
	if dialogue == null:
		return
	if dialogue.conversation_finished.is_connected(_on_finished):
		dialogue.conversation_finished.disconnect(_on_finished)
	if dialogue.choice_taken.is_connected(_on_choice):
		dialogue.choice_taken.disconnect(_on_choice)


func get_bus() -> Node:
	return _bus


## Injects the bus directly. For tests, and for a project running more than one.
func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	_register_events()


# --- Internals ------------------------------------------------------------

## Declares the two event names this module owns, so the bus can tell "nobody
## is listening" from "no module publishes this".
func _register_events() -> void:
	if _bus == null or not _bus.has_method("register_event"):
		return
	_bus.call("register_event", GameplayNames.EVENT_DIALOGUE_COMPLETED)
	_bus.call("register_event", GameplayNames.EVENT_DIALOGUE_CHOICE)


func _on_finished(outcome: StringName, runtime: DialogueRuntime) -> void:
	if not publish_completion or _bus == null or not _bus.has_method("publish"):
		return
	var definition := runtime.get_definition() if runtime != null else null
	var listener: Node = null
	if runtime != null and runtime.get_context() != null:
		listener = runtime.get_context().listener
	var event := CompletedEvent.create(
		definition.id if definition != null else &"", outcome, get_entity(), listener
	)
	_bus.call("publish", event)
	dialogue_published.emit(event)


func _on_choice(choice: DialogueChoice) -> void:
	if not publish_choices or _bus == null or not _bus.has_method("publish"):
		return
	var runtime := dialogue.get_runtime() if dialogue != null else null
	if runtime == null:
		return
	var definition := runtime.get_definition()
	var node := runtime.get_current_node()
	var listener: Node = null
	if runtime.get_context() != null:
		listener = runtime.get_context().listener
	var event := ChoiceEvent.create(
		definition.id if definition != null else &"",
		node.id if node != null else &"",
		choice,
		get_entity(),
		listener
	)
	_bus.call("publish", event)
	dialogue_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")


func _find_dialogue() -> DialogueComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is DialogueComponent:
			return component as DialogueComponent
	return null
