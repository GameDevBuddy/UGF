class_name DefinitionRegistry
extends RefCounted
## Resolves stable definition ids to loaded [FrameworkDefinition] resources.
##
## This is the indirection that makes rule 32 work. Saves, missions, loot
## tables and dialogue all reference content by id; only this registry knows
## where that content actually lives on disk, so content can be moved,
## repacked or loaded from a mod folder without invalidating a single save.
##
## Duplicate ids are rejected rather than silently overwritten: two definitions
## claiming one id is a content bug that would otherwise surface much later as
## the wrong item appearing in someone's inventory.

## Recognised definition file extensions. [code].remap[/code] appears in
## exported projects where resources are converted to binary.
const RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]

var _definitions: Dictionary[StringName, FrameworkDefinition] = {}


## Registers [param definition] under its own id.
##
## Fails on a missing id, or on a duplicate unless [param overwrite] is set.
## Re-registering the identical resource is a no-op, which keeps a folder scan
## that overlaps an explicit registration from failing.
func register(definition: FrameworkDefinition, overwrite: bool = false) -> FrameworkResult:
	if definition == null:
		return FrameworkResult.fail(
			&"definition.null", "Cannot register a null definition."
		)
	if definition.id == &"":
		return FrameworkResult.fail(
			&"definition.missing_id",
			"Definition at '%s' has no id." % definition.resource_path
		)
	if _definitions.has(definition.id):
		var existing: FrameworkDefinition = _definitions[definition.id]
		if existing == definition:
			return FrameworkResult.ok(definition)
		if not overwrite:
			return FrameworkResult.fail(
				&"definition.duplicate_id",
				(
					"Duplicate definition id '%s': '%s' collides with '%s'."
					% [definition.id, definition.resource_path, existing.resource_path]
				)
			)
	_definitions[definition.id] = definition
	return FrameworkResult.ok(definition)


func unregister(id: StringName) -> bool:
	return _definitions.erase(id)


func get_definition(id: StringName) -> FrameworkDefinition:
	return _definitions.get(id, null)


func has_definition(id: StringName) -> bool:
	return _definitions.has(id)


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_definitions.keys())
	return ids


func get_all() -> Array[FrameworkDefinition]:
	var all: Array[FrameworkDefinition] = []
	all.assign(_definitions.values())
	return all


## Every definition carrying [param tag]. This is the data-side counterpart to
## a SceneTree group: it answers "which content is a vendor?" without anything
## needing to exist in the tree (Ontology Rulebook 12).
func get_by_tag(tag: StringName) -> Array[FrameworkDefinition]:
	var matches: Array[FrameworkDefinition] = []
	for definition in _definitions.values():
		if definition.has_tag(tag):
			matches.append(definition)
	return matches


## Every definition whose script is [param script], or derives from it. Lets a
## module ask for "all VehicleDefinitions" without Core knowing that type
## exists.
func get_by_script(script: Script) -> Array[FrameworkDefinition]:
	var matches: Array[FrameworkDefinition] = []
	if script == null:
		return matches
	for definition in _definitions.values():
		if _script_derives_from(definition.get_script(), script):
			matches.append(definition)
	return matches


func size() -> int:
	return _definitions.size()


func clear() -> void:
	_definitions.clear()


## Loads and registers every definition resource under [param directory],
## recursively. Returns a result describing everything that went wrong;
## the scan always completes, so one bad file cannot hide the rest.
func scan_directory(directory: String, overwrite: bool = false) -> ValidationResult:
	var result := ValidationResult.new()
	_scan_recursive(directory, overwrite, result)
	return result


func _scan_recursive(directory: String, overwrite: bool, result: ValidationResult) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		result.add_warning(
			&"registry.missing_directory",
			"Definition directory does not exist.",
			directory
		)
		return

	var dir := DirAccess.open(directory)
	if dir == null:
		result.add_error(
			&"registry.unreadable_directory",
			"Could not open definition directory (error %d)." % DirAccess.get_open_error(),
			directory
		)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := directory.path_join(entry)
		if dir.current_is_dir():
			_scan_recursive(full_path, overwrite, result)
		else:
			_try_register_file(full_path, overwrite, result)
		entry = dir.get_next()
	dir.list_dir_end()


func _try_register_file(path: String, overwrite: bool, result: ValidationResult) -> void:
	# Exported projects rename resources to <original>.remap; loading the
	# original path still works, so strip the suffix before checking type.
	var effective_path := path
	if effective_path.get_extension() == "remap":
		effective_path = effective_path.get_basename()
	if not RESOURCE_EXTENSIONS.has(effective_path.get_extension()):
		return

	var resource: Resource = ResourceLoader.load(effective_path)
	if resource == null:
		result.add_error(
			&"registry.load_failed", "Could not load resource.", effective_path
		)
		return

	var definition := resource as FrameworkDefinition
	if definition == null:
		# Profiles and other non-definition resources live alongside
		# definitions legitimately. Not an error.
		return

	var registration := register(definition, overwrite)
	if registration.is_err():
		result.add_error(registration.code, registration.message, effective_path)


static func _script_derives_from(candidate: Script, base: Script) -> bool:
	var current := candidate
	while current != null:
		if current == base:
			return true
		current = current.get_base_script()
	return false
