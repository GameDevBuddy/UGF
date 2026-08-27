class_name InteractionEventAdapter
extends FrameworkComponent
## Promotes a finished interaction to a cross-feature fact.
##
## The same seam [HealthEventAdapter] is. Interaction shipped in M5 without one
## because nothing was listening; the plan's InteractWith objective is the
## first thing that needs to hear about it, and the answer is an adapter rather
## than Interaction learning what a mission is (rule 10).
##
## [b]Not every interaction is worth announcing.[/b] A world full of doors and
## drawers publishing every open to the whole game is noise, which is why the
## promotion is a component: whether this particular thing's use is a fact the
## rest of the game hears is per-entity data.

signal interaction_published(event: FrameworkEvent)

## The interaction to observe, wired at composition time (rule 20).
@export var interaction: InteractionComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

@export var publish_completions: bool = true

const CompletedEvent := preload(
	"res://addons/universal_gameplay/interaction/interaction_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if interaction == null:
		interaction = _find_interaction()
	_bus = event_bus if event_bus != null else _find_bus()
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_INTERACTION_COMPLETED)
	if interaction != null and not interaction.interaction_completed.is_connected(_on_completed):
		interaction.interaction_completed.connect(_on_completed)


func _exit_tree() -> void:
	if interaction != null and interaction.interaction_completed.is_connected(_on_completed):
		interaction.interaction_completed.disconnect(_on_completed)


func get_bus() -> Node:
	return _bus


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_INTERACTION_COMPLETED)


## Published only for interactions that actually succeeded.
##
## The signal fires with the result attached because a caller may want to know
## about a refusal too, but a failed interaction is not a fact -- a mission
## counting "doors opened" must not count a door that stayed shut.
func _on_completed(context: InteractionContext, result: FrameworkResult) -> void:
	if not publish_completions or _bus == null or not _bus.has_method("publish"):
		return
	if result != null and result.is_err():
		return
	var event := CompletedEvent.create(context)
	_bus.call("publish", event)
	interaction_published.emit(event)


func _find_interaction() -> InteractionComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child is InteractionComponent:
			return child as InteractionComponent
	return null


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus")
