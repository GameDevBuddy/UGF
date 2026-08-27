class_name InteractionContext
extends RefCounted
## Everything one interaction attempt knows about itself.
##
## Built by the interactor, passed to the target, handed on to whatever action
## runs. The same shape [DamageContext] has and for the same reason: an
## interaction crosses module boundaries — Interaction produces it, Dialogue,
## Commerce and Vehicles consume it — and none of them should have to depend on
## another to speak about it.

## Who is interacting. The character, not their hand or their controller.
var interactor: Node = null

## What is being interacted with.
var target: Node = null

## Which interaction was chosen. A target can offer several.
var definition: InteractionDefinition = null

## The component on the target, for an action that needs to talk back to it.
var interaction: InteractionComponent = null

## The interactor's own component, for an action that needs to reach its
## inventory or its stats without searching the tree.
var interactor_component: InteractorComponent = null

## Free-form per-attempt bag. Deliberately small: anything living here for
## long should become a real field.
var extras: Dictionary = {}


static func create(
	p_interactor: Node,
	p_target: Node,
	p_definition: InteractionDefinition = null
) -> InteractionContext:
	var context := InteractionContext.new()
	context.interactor = p_interactor
	context.target = p_target
	context.definition = p_definition
	return context


func get_verb() -> StringName:
	return definition.verb if definition != null else &""


func get_prompt() -> String:
	return definition.get_prompt() if definition != null else ""


## The interactor's inventory, when it has one. Null is a normal answer: a
## creature with no bag can still open a door.
##
## Falls back to searching the interactor's own components, the same way
## [method get_target_state] does. Not every context is built by an
## [InteractorComponent] — a seat checking its requirements builds a bare one,
## and without the fallback an item requirement on it could never be met by
## anybody, which reads as the requirement being broken rather than the context
## being thin.
func get_interactor_inventory() -> InventoryComponent:
	if interactor_component != null and interactor_component.inventory != null:
		return interactor_component.inventory
	return _find_inventory(interactor)


## The interactor's stats, when it has any.
func get_interactor_stats() -> StatsComponent:
	if interactor_component != null and interactor_component.stats != null:
		return interactor_component.stats
	return _find_stats(interactor)


## The target's semantic states, when it has any. What a state requirement
## reads, and what an action flips.
func get_target_state() -> SemanticState:
	if interaction != null and interaction.semantic_state != null:
		return interaction.semantic_state
	return _find_state(target)


## The interactor's semantic states, when it has any.
func get_interactor_state() -> SemanticState:
	if interactor_component != null and interactor_component.semantic_state != null:
		return interactor_component.semantic_state
	return _find_state(interactor)


func _find_inventory(node: Node) -> InventoryComponent:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _find_stats(node: Node) -> StatsComponent:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is StatsComponent:
			return component as StatsComponent
	return null


func _find_state(node: Node) -> SemanticState:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is SemanticState:
			return component as SemanticState
	return null


func _to_string() -> String:
	var actor := interactor.name if interactor != null else "<nobody>"
	var subject := target.name if target != null else "<nothing>"
	return "InteractionContext(%s -> %s: %s)" % [actor, subject, get_verb()]
