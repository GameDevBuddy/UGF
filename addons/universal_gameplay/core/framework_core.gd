extends Node
## Framework control plane. Autoloaded as [code]FrameworkCore[/code].
##
## No [code]class_name[/code]: a global class would collide with the autoload
## singleton. Tests preload this script and instantiate it directly, which is
## the point -- nothing here needs to be global to work.
##
## Core owns lifecycle, configuration, registries and stable contracts, and
## nothing else (rule 1). The list of methods that must never appear on this
## class is as important as the list that does:
## [codeblock]
## NOT: apply_damage()  buy_item()  complete_objective()
##      reload_weapon()  open_door()  equip_item()
## [/codeblock]
## Every one of those belongs to a module. The moment Core routes gameplay,
## every module needs Core for everything and rule 10 is dead.

## Emitted once bootstrap completes, after definitions are scanned.
signal bootstrapped
## Emitted at the start of shutdown, before registries are torn down.
signal shutting_down
## Re-emitted from the module registry so features can react to a module
## arriving or leaving without holding a reference to the registry.
signal module_registered(id: StringName)
signal module_unregistered(id: StringName)

## Project setting naming the [FrameworkSettings] resource to auto-load.
## Absent means the project bootstraps Core itself.
const SETTINGS_PATH_PROPERTY: String = "universal_gameplay/config/settings_path"

var settings: FrameworkSettings = null

var _services: ServiceRegistry = ServiceRegistry.new()
var _definitions: DefinitionRegistry = DefinitionRegistry.new()
var _modules: ModuleRegistry = null
var _bootstrapped: bool = false
## Issues collected during the last bootstrap, kept for the debug tooling and
## for CI to assert against.
var _bootstrap_result: ValidationResult = null


func _ready() -> void:
	_ensure_modules()

	if not FrameworkVersion.is_godot_supported():
		push_warning(
			(
				"Universal Gameplay Framework %s targets Godot %d.%d or newer; running on %s."
				% [
					FrameworkVersion.get_version_string(),
					FrameworkVersion.REQUIRED_GODOT[0],
					FrameworkVersion.REQUIRED_GODOT[1],
					Engine.get_version_info().get("string", "unknown"),
				]
			)
		)

	var configured := _load_configured_settings()
	if configured != null:
		bootstrap(configured)


## Prepares the framework for use: stores settings, scans definition folders
## and validates content. Safe to call once; calling again is a no-op unless
## [method shutdown] ran first.
##
## Returns every issue found. Bootstrap does not abort on invalid content --
## the caller decides whether a warning is fatal, via
## [member FrameworkSettings.strict_validation].
func bootstrap(p_settings: FrameworkSettings = null) -> ValidationResult:
	var result := ValidationResult.new()
	if _bootstrapped:
		result.add_warning(
			&"core.already_bootstrapped", "FrameworkCore is already bootstrapped."
		)
		return result

	settings = p_settings if p_settings != null else FrameworkSettings.new()
	_ensure_modules()

	result.merge(settings.validate())

	if settings.scan_definitions_on_bootstrap:
		for path in settings.definition_paths:
			if not path.is_empty():
				result.merge(_definitions.scan_directory(path))

	if settings.validate_on_bootstrap:
		result.merge(validate_definitions())

	_bootstrapped = true
	_bootstrap_result = result

	if settings.verbose_logging:
		print(
			(
				"[UGF] Bootstrapped %s | %d definition(s) | %s"
				% [
					FrameworkVersion.get_version_string(),
					_definitions.size(),
					result.format_report().get_slice("\n", 0),
				]
			)
		)

	bootstrapped.emit()
	return result


## Tears the framework down: unregisters every module, clears registries and
## returns Core to its pre-bootstrap state. Modules are removed dependents
## first so each one shuts down while its dependencies are still alive.
func shutdown() -> void:
	if not _bootstrapped:
		return
	shutting_down.emit()
	if _modules != null:
		_modules.clear()
	_services.clear()
	_definitions.clear()
	settings = null
	_bootstrap_result = null
	_bootstrapped = false


## Builds the module registry on first use, wiring its relay signals.
##
## Deliberately lazy rather than done in [method Node._ready]. Godot defers
## _ready() to the first process frame, so an autoload is reachable before its
## _ready() has run -- during another autoload's initialisation, from a tool
## script, or from a synchronous test harness. Core must be fully wired the
## first time anything asks it for something, not one frame later.
func _ensure_modules() -> ModuleRegistry:
	if _modules == null:
		_modules = ModuleRegistry.new(self)
		_modules.module_registered.connect(_on_module_registered)
		_modules.module_unregistered.connect(_on_module_unregistered)
	return _modules


## Releases the registries when Core leaves the tree.
##
## Godot frees autoloads late, after the resource sweep has already run, so a
## registry still holding script references at that point is reported as a leak
## on exit. Dropping them here is both the fix and the honest thing to do: an
## autoload that owns objects should say when it stops owning them.
func _exit_tree() -> void:
	shutdown()
	if _modules != null:
		if _modules.module_registered.is_connected(_on_module_registered):
			_modules.module_registered.disconnect(_on_module_registered)
		if _modules.module_unregistered.is_connected(_on_module_unregistered):
			_modules.module_unregistered.disconnect(_on_module_unregistered)


func is_bootstrapped() -> bool:
	return _bootstrapped


func get_bootstrap_result() -> ValidationResult:
	return _bootstrap_result


# --- Services -------------------------------------------------------------

func register_service(id: StringName, service: Object) -> FrameworkResult:
	var result := _services.register(id, service)
	if result.is_ok() and service is FrameworkService:
		(service as FrameworkService).service_started()
	return result


func unregister_service(id: StringName) -> bool:
	var service := _services.get_service(id)
	if service is FrameworkService:
		(service as FrameworkService).service_stopped()
	return _services.unregister(id)


func get_service(id: StringName) -> Object:
	return _services.get_service(id)


func has_service(id: StringName) -> bool:
	return _services.has_service(id)


func get_service_registry() -> ServiceRegistry:
	return _services


# --- Modules --------------------------------------------------------------

func register_module(module: FrameworkModule) -> FrameworkResult:
	return _ensure_modules().register(module)


func unregister_module(id: StringName, force: bool = false) -> FrameworkResult:
	return _ensure_modules().unregister(id, force)


## True when the module is [i]registered and running[/i].
##
## Distinct from [method is_module_enabled], which reports what the project
## asked for. Adapters must branch on this one: what is actually present is
## what they can call (rule 31).
func has_feature(id: StringName) -> bool:
	return _ensure_modules().has_module(id)


## True when settings ask for this module. Says nothing about whether it
## registered successfully.
func is_module_enabled(id: StringName) -> bool:
	return settings != null and settings.is_module_enabled(id)


func get_module(id: StringName) -> FrameworkModule:
	return _ensure_modules().get_module(id)


func get_module_ids() -> Array[StringName]:
	return _ensure_modules().get_module_ids()


func get_module_registry() -> ModuleRegistry:
	return _ensure_modules()


# --- Definitions ----------------------------------------------------------

func register_definition(
	definition: FrameworkDefinition, overwrite: bool = false
) -> FrameworkResult:
	return _definitions.register(definition, overwrite)


func get_definition(id: StringName) -> FrameworkDefinition:
	return _definitions.get_definition(id)


func has_definition(id: StringName) -> bool:
	return _definitions.has_definition(id)


func get_definition_registry() -> DefinitionRegistry:
	return _definitions


## Runs [method FrameworkDefinition.validate] across every registered
## definition and rolls the results up into one report.
func validate_definitions() -> ValidationResult:
	return DefinitionValidator.validate_registry(_definitions)


# --- Internals ------------------------------------------------------------

func _load_configured_settings() -> FrameworkSettings:
	if not ProjectSettings.has_setting(SETTINGS_PATH_PROPERTY):
		return null
	var path: String = str(ProjectSettings.get_setting(SETTINGS_PATH_PROPERTY, ""))
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("[UGF] Settings resource '%s' does not exist." % path)
		return null
	var resource := ResourceLoader.load(path) as FrameworkSettings
	if resource == null:
		push_warning("[UGF] Resource '%s' is not a FrameworkSettings." % path)
	return resource


func _on_module_registered(id: StringName) -> void:
	if settings != null and settings.verbose_logging:
		print("[UGF] Module registered: %s" % id)
	module_registered.emit(id)


func _on_module_unregistered(id: StringName) -> void:
	if settings != null and settings.verbose_logging:
		print("[UGF] Module unregistered: %s" % id)
	module_unregistered.emit(id)
