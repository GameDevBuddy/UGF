class_name EntityContext
extends RefCounted
## Everything a capability component is handed when it initialises.
##
## This is the framework's dependency-injection seam (rule 20). A component
## receives its entity, its definition and its core through this context
## instead of walking the tree or reaching for autoloads, which is what makes
## a component testable in isolation and immune to scene restructuring
## (rules 21 and 22).

## The entity root that owns the component. Typed as Node because a character
## is a CharacterBody3D, a vehicle may be a VehicleBody3D, and a world object
## may be a StaticBody3D.
var entity: Node = null

## The definition this entity was built from. Null for entities assembled
## directly in a scene without a definition.
var definition: FrameworkDefinition = null

## Stable save identity for this entity instance. Distinct from any network id
## (Implementation Plan 27).
var persistent_id: StringName = &""

## The framework core, injected rather than looked up. Typed as Node to keep
## Core free of a dependency on its own consumers.
var core: Node = null

## Free-form per-entity bag for assembly-time wiring that has no home yet.
## Deliberately untyped and deliberately small: anything that lives here for
## long should become a real field.
var extras: Dictionary = {}


static func create(
	p_entity: Node,
	p_definition: FrameworkDefinition = null,
	p_core: Node = null,
	p_persistent_id: StringName = &""
) -> EntityContext:
	var context := EntityContext.new()
	context.entity = p_entity
	context.definition = p_definition
	context.core = p_core
	context.persistent_id = p_persistent_id
	return context


func has_definition() -> bool:
	return definition != null


## Convenience passthrough so components can branch on optional modules
## without knowing how the core stores feature state (rule 31).
func has_feature(feature_id: StringName) -> bool:
	if core == null or not core.has_method("has_feature"):
		return false
	return core.call("has_feature", feature_id)
