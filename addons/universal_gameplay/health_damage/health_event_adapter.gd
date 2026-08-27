class_name HealthEventAdapter
extends FrameworkComponent
## Promotes a local death signal to a cross-feature fact on the EventBus.
##
## [b]This class is the argument the two source documents were having.[/b]
## Implementation Plan 45 has [HealthComponent] publish
## [code]EventBus.actor_died[/code] itself; the Ontology Rulebook has it emit
## only a local signal. The framework takes the Rulebook's side and puts the
## promotion here, in a component that can be deleted.
##
## What that buys, concretely:
##
## [b]Health stays testable.[/b] A component that reaches for an autoload
## cannot be instantiated without booting the singleton, and rule 33 wants
## domain logic testable without a live scene. Every health test in this
## framework runs with no bus in existence.
##
## [b]The bus stays optional.[/b] Delete this component and an entity still
## takes damage, still dies, still saves. What it stops doing is telling
## Missions and Loot about it -- which is exactly the right failure mode for a
## module that some projects will not install (rule 10, rule 31).
##
## [b]The decision has an owner.[/b] "Which deaths are worth telling the whole
## game about?" is a design question. An ambient crowd NPC dying is probably
## not; a named quest target certainly is. Because the promotion is a component,
## the answer is per-entity data instead of a hard-coded yes.

## Emitted after the event is published, for debug tooling that wants to see
## the promotion happen without subscribing to the bus.
signal death_published(event: ActorDiedEvent)

## The health to observe, wired at composition time (rule 20).
@export var health: HealthComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes, and for the
## same reason: this is the seam where one entity meets the wider game, and
## requiring every authored scene to be handed a bus by hand would make
## authored content unusable on its own.
@export var event_bus: Node

## Whether this entity's death is a fact the rest of the game should hear.
## Ambient population can turn it off and stop flooding the bus.
@export var publish_death: bool = true

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if health == null:
		health = _find_health()
	_bus = event_bus if event_bus != null else _find_bus()
	if health != null and not health.died.is_connected(_on_died):
		health.died.connect(_on_died)


func _exit_tree() -> void:
	if health != null and health.died.is_connected(_on_died):
		health.died.disconnect(_on_died)


func get_bus() -> Node:
	return _bus


## Injects the bus directly. For tests, and for a project running more than one
## bus, which is unusual but not forbidden.
func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus


func _on_died(context: DamageContext) -> void:
	if not publish_death or _bus == null:
		return
	if not _bus.has_method("publish"):
		return
	var event := ActorDiedEvent.create(get_entity(), context)
	_bus.call("publish", event)
	death_published.emit(event)


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")


func _find_health() -> HealthComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is HealthComponent:
			return component as HealthComponent
	return null
