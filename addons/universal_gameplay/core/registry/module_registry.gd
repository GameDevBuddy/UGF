class_name ModuleRegistry
extends RefCounted
## Tracks which feature modules are registered, and enforces their manifests.
##
## This registry is where rule 10 ("every module must be removable") stops
## being an aspiration and becomes a check. Registration fails when a declared
## dependency is absent, and unregistration fails while another registered
## module still requires the one being removed -- so a coupling that was never
## declared shows up as a broken feature in testing, and a coupling that was
## declared cannot be silently violated.
##
## Optional dependencies are never enforced in either direction. A module
## listing another as optional must work with it absent (rule 31).

signal module_registered(id: StringName)
signal module_unregistered(id: StringName)

var _modules: Dictionary[StringName, FrameworkModule] = {}
## Injected rather than looked up, so a registry can be exercised against a
## throwaway core in tests.
var _core: Node = null


func _init(core: Node = null) -> void:
	_core = core


func set_core(core: Node) -> void:
	_core = core


## Validates the manifest, checks required dependencies, then initialises the
## module. Nothing is stored if any step fails, so a rejected registration
## leaves the registry exactly as it was.
func register(module: FrameworkModule) -> FrameworkResult:
	if module == null:
		return FrameworkResult.fail(&"module.null", "Cannot register a null module.")

	var manifest := module.get_manifest()
	if manifest == null:
		return FrameworkResult.fail(
			&"module.missing_manifest", "Module returned a null manifest."
		)

	var manifest_result := manifest.validate()
	if manifest_result.has_errors():
		return FrameworkResult.fail(
			&"module.invalid_manifest",
			"Manifest for '%s' is invalid: %s" % [manifest.id, manifest_result.format_report()]
		)

	if _modules.has(manifest.id):
		return FrameworkResult.fail(
			&"module.already_registered",
			"Module '%s' is already registered." % manifest.id
		)

	var missing := get_missing_requirements(manifest)
	if not missing.is_empty():
		return FrameworkResult.fail(
			&"module.missing_dependency",
			(
				"Module '%s' requires %s, which %s not registered."
				% [
					manifest.id,
					str(missing),
					"is" if missing.size() == 1 else "are",
				]
			)
		)

	_modules[manifest.id] = module
	module.initialize(_core)
	module_registered.emit(manifest.id)
	return FrameworkResult.ok(module)


## Removes a module and shuts it down.
##
## Refuses while another registered module declares it as required, unless
## [param force] is set. Forcing is for teardown, not for working around a
## dependency.
func unregister(id: StringName, force: bool = false) -> FrameworkResult:
	if not _modules.has(id):
		return FrameworkResult.fail(
			&"module.not_registered", "Module '%s' is not registered." % id
		)

	if not force:
		var dependents := get_dependents(id)
		if not dependents.is_empty():
			return FrameworkResult.fail(
				&"module.has_dependents",
				(
					"Cannot unregister '%s': still required by %s."
					% [id, str(dependents)]
				)
			)

	var module: FrameworkModule = _modules[id]
	_modules.erase(id)
	module.shutdown(_core)
	module_unregistered.emit(id)
	return FrameworkResult.ok(module)


## Required dependencies of [param manifest] that are not currently registered.
func get_missing_requirements(manifest: ModuleManifest) -> Array[StringName]:
	var missing: Array[StringName] = []
	if manifest == null:
		return missing
	for dependency in manifest.requires:
		if not _modules.has(dependency):
			missing.append(dependency)
	return missing


## Registered modules that declare [param id] as a required dependency.
func get_dependents(id: StringName) -> Array[StringName]:
	var dependents: Array[StringName] = []
	for module_id in _modules:
		var manifest := _modules[module_id].get_manifest()
		if manifest != null and manifest.requires.has(id):
			dependents.append(module_id)
	return dependents


func has_module(id: StringName) -> bool:
	return _modules.has(id)


func get_module(id: StringName) -> FrameworkModule:
	return _modules.get(id, null)


func get_manifest(id: StringName) -> ModuleManifest:
	var module := get_module(id)
	return module.get_manifest() if module != null else null


func get_module_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_modules.keys())
	return ids


func size() -> int:
	return _modules.size()


## Unregisters everything, dependents first, ignoring dependency order errors.
## Used at shutdown, where the whole graph is going away regardless.
func clear() -> void:
	# Repeatedly remove modules nothing depends on. Any cycle left over is
	# force-removed, since a cycle should have been impossible to register.
	while not _modules.is_empty():
		var removable: Array[StringName] = []
		for id in _modules:
			if get_dependents(id).is_empty():
				removable.append(id)
		if removable.is_empty():
			for id in get_module_ids():
				unregister(id, true)
			return
		for id in removable:
			unregister(id)
