class_name EntityFactory
extends RefCounted
## Builds entities from definitions, and rebuilds them from saved records.
##
## This is the load path the architecture is designed around:
## [codeblock]
## definition_id -> DefinitionRegistry -> scene.instantiate()
##               -> bind definition -> apply saved state
## [/codeblock]
## Because that path exists, a save can hold ids and component state rather
## than a scene graph, and content can be re-authored without breaking it.
##
## Binding is always explicit here. The factory switches
## [member DefinitionBinder.bind_on_ready] off before adding the entity to the
## tree, so state is restored before anything can react to a half-built entity
## -- and so the sequence behaves identically whether or not a process frame
## has elapsed.


## Instantiates the entity for [param definition_id] and binds it.
##
## Returns the new Node as the result payload. On failure nothing is added to
## the tree and nothing is left half-built.
static func spawn(
	core: Node, definition_id: StringName, parent: Node = null
) -> FrameworkResult:
	if core == null or not core.has_method("get_definition"):
		return FrameworkResult.fail(
			&"factory.no_core", "A FrameworkCore is required to resolve definitions."
		)

	var definition := core.call("get_definition", definition_id) as FrameworkDefinition
	if definition == null:
		return FrameworkResult.fail(
			&"factory.unresolved_definition",
			"Definition '%s' is not registered." % definition_id
		)

	var entity_definition := definition as EntityDefinition
	if entity_definition == null:
		return FrameworkResult.fail(
			&"factory.not_an_entity",
			(
				"Definition '%s' is not an EntityDefinition, so it has no scene to spawn."
				% definition_id
			)
		)
	if entity_definition.scene == null:
		return FrameworkResult.fail(
			&"factory.missing_scene", "Definition '%s' has no scene." % definition_id
		)

	var entity := entity_definition.scene.instantiate()
	var binder := EntitySerializer.find_binder(entity)
	if binder == null:
		entity.free()
		return FrameworkResult.fail(
			&"factory.no_binder",
			(
				"The scene for '%s' has no DefinitionBinder, so it cannot be bound."
				% definition_id
			)
		)

	binder.bind_on_ready = false
	binder.definition = entity_definition

	if parent != null:
		parent.add_child(entity)

	var bind_result := binder.bind(core)
	if bind_result.is_err():
		if parent != null:
			parent.remove_child(entity)
		entity.free()
		return bind_result

	return FrameworkResult.ok(entity)


## Rebuilds a saved entity: spawn from its definition, reapply its identity,
## then restore component state.
##
## Identity is applied before binding so the entity's context carries the saved
## id rather than a freshly generated one.
static func spawn_from_record(
	core: Node, record: EntityRecord, parent: Node = null
) -> FrameworkResult:
	if record == null:
		return FrameworkResult.fail(&"factory.null_record", "Cannot spawn a null record.")
	if record.definition_id == &"":
		return FrameworkResult.fail(
			&"factory.record_without_definition",
			(
				"Record '%s' has no definition_id, so there is nothing to rebuild it from."
				% record.persistent_id
			)
		)

	if core == null or not core.has_method("get_definition"):
		return FrameworkResult.fail(
			&"factory.no_core", "A FrameworkCore is required to resolve definitions."
		)

	var definition := core.call("get_definition", record.definition_id) as EntityDefinition
	if definition == null or definition.scene == null:
		return FrameworkResult.fail(
			&"factory.unresolved_definition",
			(
				"Definition '%s' is not registered as a spawnable entity."
				% record.definition_id
			)
		)

	var entity := definition.scene.instantiate()
	var binder := EntitySerializer.find_binder(entity)
	if binder == null:
		entity.free()
		return FrameworkResult.fail(
			&"factory.no_binder",
			"The scene for '%s' has no DefinitionBinder." % record.definition_id
		)

	binder.bind_on_ready = false
	binder.definition = definition

	var identity := EntitySerializer.find_identity(entity)
	if identity != null and record.persistent_id != &"":
		identity.set_persistent_id(record.persistent_id)

	if parent != null:
		parent.add_child(entity)

	var bind_result := binder.bind(core)
	if bind_result.is_err():
		if parent != null:
			parent.remove_child(entity)
		entity.free()
		return bind_result

	var restore_result := EntitySerializer.restore(entity, record)
	return FrameworkResult.ok({"entity": entity, "issues": restore_result})
