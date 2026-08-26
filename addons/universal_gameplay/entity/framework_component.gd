class_name FrameworkComponent
extends Node
## Base class for a reusable capability attached to an entity.
##
## A component answers "what can this entity do?" (Ontology Rulebook, layer 3).
## It owns its own mutable state, exposes a typed API, and reports changes
## through local signals.
##
## [b]Components do not touch the EventBus.[/b] This is the one place the two
## source documents disagree, and it is worth being explicit about: the
## reference snippet in Implementation Plan 45 has [code]HealthComponent[/code]
## emit [code]EventBus.actor_died[/code] directly, while the Ontology Rulebook
## has the same component emit only a local [code]died[/code] signal. This
## framework takes the Rulebook's side, for two reasons.
##
## First, testability. A component that reaches for an autoload cannot be
## instantiated in a unit test without booting the singleton, and rule 33 wants
## domain logic testable without a live scene.
##
## Second, removability. If every component hard-references the bus, the bus
## becomes a mandatory runtime dependency of every entity, and "which module
## publishes this fact" stops having an answer. Promoting a local signal to a
## cross-feature fact is a decision, and decisions belong at the seam that owns
## them -- the entity root or an explicit adapter -- not inside the capability.
##
## So: components emit locally, and something above relays. Rule 7 already says
## signals are the local default; this is only following it all the way down.

## Emitted once [method initialize] has run and the component is usable.
signal initialized

var _context: EntityContext = null
var _initialized: bool = false


## Called during entity assembly, before the component is used.
##
## Overrides should call [code]super(context)[/code] first, then read whatever
## they need from [member EntityContext.definition]. Everything a component
## needs arrives here; a component that walks the tree for a collaborator has
## broken rules 20 through 22.
func initialize(context: EntityContext) -> void:
	_context = context
	_initialized = true
	initialized.emit()


func is_initialized() -> bool:
	return _initialized


func get_context() -> EntityContext:
	return _context


## The entity root that owns this component, or null before initialisation.
func get_entity() -> Node:
	return _context.entity if _context != null else null


## The definition this entity was built from, or null when it has none.
func get_definition() -> FrameworkDefinition:
	return _context.definition if _context != null else null


# --- Persistence ----------------------------------------------------------
#
# Stateful components implement this pair and nothing else; SaveService walks
# the entity and aggregates whatever it gets back (Implementation Plan 26).
# What is returned must be plain serialisable data -- no Nodes, no object
# references, no scene paths. Persist ids, not the scene graph (rule 22).

## Serialisable snapshot of this component's mutable state. Return an empty
## dictionary when there is nothing worth saving.
func capture_state() -> Dictionary:
	return {}


## Applies a snapshot produced by [method capture_state], possibly from an
## older schema version. Restoring must tolerate missing keys: a save written
## before a field existed is a normal case, not a corrupt file.
func restore_state(_data: Dictionary) -> void:
	pass


## Whether SaveService should include this component. Defaults to false so a
## purely behavioural component is not asked to serialise nothing.
func is_persistent() -> bool:
	return false
