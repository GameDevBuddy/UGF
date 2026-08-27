@tool
extends EditorPlugin
## Editor entry point: installs the framework's autoloads and project settings.
##
## The plugin exists only to make installation one click. Nothing at runtime
## depends on it, and the framework works in a project that wires the two
## autoloads by hand.

## Loaded rather than referenced by class_name, because autoload scripts
## deliberately have none.
const FrameworkCoreScript := preload(
	"res://addons/universal_gameplay/core/framework_core.gd"
)

const CORE_AUTOLOAD: StringName = &"FrameworkCore"
const EVENT_BUS_AUTOLOAD: StringName = &"EventBus"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const EVENT_BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"


func _enter_tree() -> void:
	# EventBus is added first so it exists before Core bootstraps against it.
	add_autoload_singleton(EVENT_BUS_AUTOLOAD, EVENT_BUS_SCRIPT)
	add_autoload_singleton(CORE_AUTOLOAD, CORE_SCRIPT)
	_ensure_settings_property()
	_ensure_default_input_bindings()
	ProjectSettings.save()


func _exit_tree() -> void:
	remove_autoload_singleton(CORE_AUTOLOAD)
	remove_autoload_singleton(EVENT_BUS_AUTOLOAD)


func _get_plugin_name() -> String:
	return "Universal Gameplay Framework"


## Registers the settings-path property so it is visible and documented in
## Project Settings rather than being an undiscoverable magic string.
func _ensure_settings_property() -> void:
	var property: String = FrameworkCoreScript.SETTINGS_PATH_PROPERTY
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, "")
	ProjectSettings.set_initial_value(property, "")
	ProjectSettings.add_property_info({
		"name": property,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res",
	})


## Gives the framework's semantic actions default keyboard and gamepad
## bindings, for any the project has not already defined.
##
## Without this, enabling the addon produces a character that compiles, spawns,
## validates and cannot move, because [code]move_forward[/code] is a name with
## nothing bound to it -- and an unbound action is indistinguishable from an
## unpressed one at runtime.
##
## Never overwrites. A project that rebinds these keeps its bindings through
## every future version of the addon; quietly resetting rebound controls on an
## update is not a bug anyone enjoys tracking down.
func _ensure_default_input_bindings() -> void:
	DefaultInputBindings.write_project_settings()
