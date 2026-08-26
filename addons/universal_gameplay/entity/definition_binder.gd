class_name DefinitionBinder
extends Node
## Binds a definition to an entity and initialises its capabilities.
##
## This is the composition seam. Everything above it is data -- a definition
## resolved by id -- and everything below it is capability Nodes that need a
## context before they can work. The binder is what joins them, and it is the
## reason a component never has to search the tree for its collaborators
## (rules 20 to 22).
##
## Its presence also marks a node as an entity root. A vehicle containing a
## seated character contains two binders, and neither reaches into the other's
## components.
##
## The binder is not a [FrameworkComponent]: it initialises components, so it
## cannot be one of the things waiting to be initialised.

## Emitted once the definition is bound and every capability is initialised.
signal bound(context: EntityContext)

## Definition authored directly on this entity. Takes precedence over
## [member definition_id].
@export var definition: FrameworkDefinition

## Definition resolved from the registry at bind time. This is the normal case
## for spawned content: the scene carries an id, not a hard resource reference.
@export var definition_id: StringName = &""

## Bind automatically when the entity enters the tree. Turn this off when
## something else owns the timing -- a spawner restoring saved state wants to
## bind, restore, then release the entity in one controlled sequence.
@export var bind_on_ready: bool = true

## The entity root. Defaults to this node's parent.
@export var entity_root: Node

var _context: EntityContext = null
var _bound: bool = false


func _ready() -> void:
	if bind_on_ready and not _bound:
		bind()


## Resolves the definition, builds the [EntityContext] and initialises every
## capability belonging to this entity.
##
## [param core] is injected when known. When omitted the binder falls back to
## the [code]FrameworkCore[/code] autoload if one exists -- this is the single
## place in the framework that reaches for a global, because it is the seam
## where an entity meets the wider game, and requiring every spawned scene to
## be handed a core by hand would make authored content unusable on its own.
func bind(core: Node = null) -> FrameworkResult:
	if _bound:
		return FrameworkResult.fail(
			&"binder.already_bound", "This entity is already bound."
		)

	var root := get_entity_root()
	if root == null:
		return FrameworkResult.fail(
			&"binder.no_entity_root",
			"DefinitionBinder has no entity root; it needs a parent or an explicit one."
		)

	var resolved_core := core if core != null else _find_core()
	var resolution := _resolve_definition(resolved_core)
	if resolution.is_err():
		return resolution

	# The context is built before the id is known, then completed afterwards.
	# PersistentIdentity derives its prefix from the definition, so it needs a
	# context before it can produce an id -- and the context needs that id.
	# Building it in two steps is what breaks the circle; the context is a
	# reference, so every component sees the completed value.
	_context = EntityContext.create(root, resolution.payload, resolved_core)

	var components := collect_components(root)
	for component in components:
		component.initialize(_context)

	var identity := get_persistent_identity()
	if identity != null:
		_context.persistent_id = identity.get_persistent_id()

	_bound = true
	bound.emit(_context)
	return FrameworkResult.ok(_context)


func is_bound() -> bool:
	return _bound


func get_context() -> EntityContext:
	return _context


func get_entity_root() -> Node:
	return entity_root if entity_root != null else get_parent()


## The definition this entity was bound to, or null before binding.
func get_definition() -> FrameworkDefinition:
	return _context.definition if _context != null else definition


## This entity's [PersistentIdentity], or null when it has none. An entity
## without one is not saveable, which is a legitimate choice for scenery.
func get_persistent_identity() -> PersistentIdentity:
	var root := get_entity_root()
	if root == null:
		return null
	for component in collect_components(root):
		if component is PersistentIdentity:
			return component as PersistentIdentity
	return null


func _resolve_definition(core: Node) -> FrameworkResult:
	if definition != null:
		return FrameworkResult.ok(definition)

	if definition_id == &"":
		# An entity with no definition is valid: a scene-authored prop whose
		# components are configured in the inspector needs no content behind it.
		return FrameworkResult.ok(null)

	if core == null or not core.has_method("get_definition"):
		return FrameworkResult.fail(
			&"binder.no_registry",
			(
				"Cannot resolve definition '%s': no FrameworkCore is available."
				% definition_id
			)
		)

	var resolved: FrameworkDefinition = core.call("get_definition", definition_id)
	if resolved == null:
		return FrameworkResult.fail(
			&"binder.unresolved_definition",
			"Definition '%s' is not registered." % definition_id
		)
	return FrameworkResult.ok(resolved)


func _find_core() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("FrameworkCore")


# --- Component discovery --------------------------------------------------

## Every [FrameworkComponent] belonging to [param root], stopping at nested
## entity roots.
##
## A nested entity -- a character seated in a vehicle, a turret mounted on a
## hull -- binds its own components through its own binder. Descending into it
## would initialise its capabilities with the wrong entity's context.
static func collect_components(root: Node) -> Array[FrameworkComponent]:
	var found: Array[FrameworkComponent] = []
	_collect_into(root, found)
	return found


static func _collect_into(node: Node, into: Array[FrameworkComponent]) -> void:
	for child in node.get_children():
		if is_entity_root(child):
			continue
		if child is FrameworkComponent:
			into.append(child as FrameworkComponent)
		_collect_into(child, into)


## True when [param node] owns a [DefinitionBinder], and is therefore an
## entity in its own right.
static func is_entity_root(node: Node) -> bool:
	for child in node.get_children():
		if child is DefinitionBinder:
			return true
	return false
