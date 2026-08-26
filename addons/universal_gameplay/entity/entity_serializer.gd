class_name EntitySerializer
extends RefCounted
## Captures and restores an entity's state.
##
## Walks the entity's capabilities and asks each persistent one for its state,
## rather than serialising Nodes reflectively (Implementation Plan 26). The
## difference matters: a component decides what of its state is worth saving,
## and adding a field to a component cannot silently change a save format.
##
## Stateless and static; there is nothing here worth making a service (rule 28).


## Builds a record from a live entity.
##
## [param issues] collects problems when supplied. Capture never fails outright
## -- a partial record beats losing an entity from the save entirely.
static func capture(entity: Node, issues: ValidationResult = null) -> EntityRecord:
	var record := EntityRecord.new()
	if entity == null:
		if issues != null:
			issues.add_error(&"serializer.null_entity", "Cannot capture a null entity.")
		return record

	var binder := find_binder(entity)
	if binder != null:
		var definition := binder.get_definition()
		if definition != null:
			record.definition_id = definition.id

	var seen_keys: Dictionary[StringName, bool] = {}
	for component in DefinitionBinder.collect_components(entity):
		if component is PersistentIdentity:
			var identity := component as PersistentIdentity
			record.persistent_id = identity.get_persistent_id()
		if not component.is_persistent():
			continue

		var key := component.get_state_key()
		if key == &"":
			if issues != null:
				issues.add_warning(
					&"serializer.empty_state_key",
					"A component on '%s' returned an empty state key; skipped."
					% entity.name
				)
			continue
		if seen_keys.has(key):
			# Two components filing under one key would silently clobber each
			# other, and the loss would only show up on load.
			if issues != null:
				issues.add_error(
					&"serializer.duplicate_state_key",
					(
						"Two components on '%s' share the state key '%s'. Override "
						+ "get_state_key() on one of them."
					) % [entity.name, key]
				)
			continue
		seen_keys[key] = true
		record.component_state[key] = component.capture_state()

	if entity is Node3D:
		var spatial := entity as Node3D
		# global_transform is only meaningful, and only legal, inside the tree.
		# An entity captured before it is parented -- built by a spawner and
		# serialised before placement -- still has a local transform worth
		# keeping, and asking for the global one would both error and silently
		# return identity.
		record.transform = (
			spatial.global_transform if spatial.is_inside_tree() else spatial.transform
		)
		record.has_transform = true

	return record


## Applies [param record] to a live entity.
##
## Missing state is not an error: a component added since the save was written
## keeps its defaults, which is the normal case for a game under development
## and must never be a load failure.
static func restore(entity: Node, record: EntityRecord) -> ValidationResult:
	var result := ValidationResult.new()
	if entity == null:
		result.add_error(&"serializer.null_entity", "Cannot restore into a null entity.")
		return result
	if record == null:
		result.add_error(&"serializer.null_record", "Cannot restore a null record.")
		return result

	if record.has_transform and entity is Node3D:
		var spatial := entity as Node3D
		if spatial.is_inside_tree():
			spatial.global_transform = record.transform
		else:
			# Not yet placed. The local transform is the best available
			# meaning, and the entity lands correctly once parented at origin.
			spatial.transform = record.transform

	var restored_keys: Dictionary[StringName, bool] = {}
	for component in DefinitionBinder.collect_components(entity):
		if component is PersistentIdentity and record.persistent_id != &"":
			(component as PersistentIdentity).set_persistent_id(record.persistent_id)
		if not component.is_persistent():
			continue
		var key := component.get_state_key()
		if not record.has_component_state(key):
			continue
		component.restore_state(record.get_component_state(key))
		restored_keys[key] = true

	# State in the record with no component to receive it usually means a
	# component was renamed or removed. Worth reporting, never worth failing:
	# the rest of the entity loaded correctly.
	for key in record.component_state:
		if not restored_keys.has(key):
			result.add_warning(
				&"serializer.orphan_state",
				(
					"Saved state for '%s' had no matching component on '%s'; "
					+ "it was renamed, removed, or belongs to a disabled module."
				) % [key, entity.name]
			)

	return result


## True when the entity has an identity and is marked saveable. Ambient
## population is regenerated from definitions rather than persisted.
static func is_saveable(entity: Node) -> bool:
	if entity == null:
		return false
	for component in DefinitionBinder.collect_components(entity):
		if component is PersistentIdentity:
			return (component as PersistentIdentity).is_saveable()
	return false


static func find_binder(entity: Node) -> DefinitionBinder:
	if entity == null:
		return null
	for child in entity.get_children():
		if child is DefinitionBinder:
			return child as DefinitionBinder
	return null


static func find_identity(entity: Node) -> PersistentIdentity:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is PersistentIdentity:
			return component as PersistentIdentity
	return null
