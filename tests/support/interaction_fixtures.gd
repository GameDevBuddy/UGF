class_name InteractionFixtures
extends RefCounted
## Builders for the doors, keycards, actors and vehicles the M5 suites need.
##
## Entities are assembled by hand rather than instantiated from a scene,
## because the point of most of these tests is that the pipeline works on a
## plain [Node] with two components on it -- no binder, no definition, no
## scene. Rule 33 asks for exactly that.
##
## Static builders rather than [code].tres[/code] files: the addon ships no
## content of its own (rule 29).


static func definition(
	id: StringName = &"interaction.use",
	verb: StringName = &"verb.use",
	prompt: String = ""
) -> InteractionDefinition:
	var interaction := InteractionDefinition.new()
	interaction.id = id
	interaction.display_name = str(id)
	interaction.verb = verb
	interaction.prompt = prompt if not prompt.is_empty() else "Use"
	return interaction


## An interaction that flips [constant GameplayNames.STATE_OPEN] on its target.
static func door(id: StringName = &"interaction.door") -> InteractionDefinition:
	var interaction := definition(id, GameplayNames.VERB_OPEN, "Open")
	var action := ToggleStateAction.new()
	action.state = GameplayNames.STATE_OPEN
	interaction.action = action
	return interaction


## A hold: [param duration] seconds before it takes effect.
static func timed(
	duration: float = 1.0, id: StringName = &"interaction.hack"
) -> InteractionDefinition:
	var interaction := definition(id, GameplayNames.VERB_USE, "Hack")
	interaction.duration = duration
	return interaction


## Requires an item, optionally taking it.
static func needs_item(
	item_id: StringName = &"item.keycard",
	quantity: int = 1,
	consume: bool = false
) -> ItemRequirement:
	var requirement := ItemRequirement.new()
	requirement.item_id = item_id
	requirement.quantity = quantity
	requirement.consume = consume
	requirement.unmet_text = "Requires a keycard"
	return requirement


## [param required] and [param forbidden] are plain arrays and are copied into
## typed ones here. A bare literal cannot be assigned to an
## [code]Array[StringName][/code] property in GDScript, and every caller
## writing out the typed local is noise.
static func needs_state(
	required: Array = [],
	forbidden: Array = [],
	subject: StateRequirement.Subject = StateRequirement.Subject.TARGET
) -> StateRequirement:
	var requirement := StateRequirement.new()
	requirement.subject = subject
	var required_states: Array[StringName] = []
	required_states.assign(required)
	var forbidden_states: Array[StringName] = []
	forbidden_states.assign(forbidden)
	requirement.required = required_states
	requirement.forbidden = forbidden_states
	return requirement


## An interactable entity: a semantic state and an interaction component, with
## no definition and no binder.
static func target(
	interactions: Array = [],
	entity_name: String = "Door",
	spatial: bool = false
) -> Node:
	var entity: Node = Node3D.new() if spatial else Node.new()
	entity.name = entity_name

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var offered: Array[InteractionDefinition] = []
	offered.assign(interactions)
	interaction.interactions_override = offered
	interaction.semantic_state = state
	interaction.auto_tick = false
	entity.add_child(interaction)
	return entity


## An entity that can interact. [param carry] is an item definition to put in
## its inventory, or null for an actor with no bag at all.
static func actor(
	entity_name: String = "Player",
	carry: ItemDefinition = null,
	quantity: int = 1,
	spatial: bool = false
) -> Node:
	var entity: Node = Node3D.new() if spatial else Node.new()
	entity.name = entity_name

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	if carry != null:
		var inventory := InventoryComponent.new()
		inventory.name = "InventoryComponent"
		inventory.profile_override = ItemFixtures.container()
		entity.add_child(inventory)

	var interactor := InteractorComponent.new()
	interactor.name = "InteractorComponent"
	interactor.auto_tick = false
	entity.add_child(interactor)
	return entity


## Runs [method FrameworkComponent.initialize] over an assembled entity, the
## way a [DefinitionBinder] would. Call it after the entity is in the tree.
static func assemble(entity: Node, definition_resource: FrameworkDefinition = null) -> void:
	var context := EntityContext.create(entity, definition_resource)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


## The interaction component of an entity built by [method target].
static func interaction_of(entity: Node) -> InteractionComponent:
	return InteractionComponent.find_on(entity)


## The interactor component of an entity built by [method actor].
static func interactor_of(entity: Node) -> InteractorComponent:
	return InteractorComponent.find_on(entity)


static func state_of(entity: Node) -> SemanticState:
	for component in DefinitionBinder.collect_components(entity):
		if component is SemanticState:
			return component as SemanticState
	return null


static func inventory_of(entity: Node) -> InventoryComponent:
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null
