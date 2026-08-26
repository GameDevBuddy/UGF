class_name FrameworkSettings
extends Resource
## Project-level framework configuration.
##
## This is the Resource behind the feature-toggle table in Implementation
## Plan 38. A project declares which modules it wants and where its content
## lives; the framework never assumes a module exists (rule 31).
##
## Settings are read at bootstrap. Changing them at runtime is not supported
## and not needed: enabling a module mid-session is a module-registry
## operation, not a settings edit.

## Folders scanned for definition resources at bootstrap, in order. Game
## content paths belong here; the framework addon ships no content of its own
## (rule 29).
@export var definition_paths: Array[String] = []

## Modules the project wants enabled. A module absent from this table is
## treated as disabled, so adding a module is always an explicit act.
@export var enabled_modules: Dictionary[StringName, bool] = {}

## When true, validation warnings fail the build. Off during development,
## on in CI.
@export var strict_validation: bool = false

## Run definition validation during bootstrap. Worth leaving on in debug
## builds and off in release, where content has already been validated.
@export var validate_on_bootstrap: bool = true

## Scan [member definition_paths] at bootstrap. Projects that register their
## content explicitly can turn this off.
@export var scan_definitions_on_bootstrap: bool = true

## Emit bootstrap and module lifecycle messages to the output log.
@export var verbose_logging: bool = false


func is_module_enabled(id: StringName) -> bool:
	return enabled_modules.get(id, false)


func set_module_enabled(id: StringName, enabled: bool) -> void:
	enabled_modules[id] = enabled


func get_enabled_module_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in enabled_modules:
		if enabled_modules[id]:
			ids.append(id)
	return ids


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	for path in definition_paths:
		if path.is_empty():
			result.add_warning(
				&"settings.empty_definition_path",
				"definition_paths contains an empty entry.",
				resource_path,
				"definition_paths"
			)
		elif not DirAccess.dir_exists_absolute(path):
			result.add_warning(
				&"settings.missing_definition_path",
				"Definition path '%s' does not exist." % path,
				resource_path,
				"definition_paths"
			)
	for id in enabled_modules:
		if id == &"":
			result.add_error(
				&"settings.empty_module_id",
				"enabled_modules contains an empty module id.",
				resource_path,
				"enabled_modules"
			)
	return result
