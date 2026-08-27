extends FrameworkModule
## The Input module.
##
## Owns one [InputRouter] and registers it as a service, so anything that needs
## to ask about a semantic action can find one without an autoload (rule 8).
##
## The router starts with no context on the stack. Pushing the first one is the
## project's decision -- a game that opens on a main menu should not spend its
## title screen listening for jump.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.input"

var _manifest: ModuleManifest = null
var _router: InputRouter = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Input"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Semantic action routing through a context stack, so gameplay asks "
			+ "for actions rather than for keys."
		)
	return _manifest


func initialize(core: Node) -> void:
	_router = InputRouter.new()
	_router.name = "InputRouter"
	if core != null:
		# A service that is a Node needs a parent to live under. Core owns the
		# lifetime; the registry only holds the reference.
		core.add_child(_router)
		if core.has_method("register_service"):
			core.call("register_service", GameplayNames.SERVICE_INPUT, _router)


func shutdown(core: Node) -> void:
	if core != null and core.has_method("unregister_service"):
		core.call("unregister_service", GameplayNames.SERVICE_INPUT)
	if _router != null:
		# Registered again after shutdown means a fresh router, not a revived
		# one holding a stale context stack.
		_router.queue_free()
		_router = null


## The router this module owns, or null before initialisation.
func get_router() -> InputRouter:
	return _router
