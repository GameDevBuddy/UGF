class_name ModuleManifest
extends Resource
## Declares a feature module's identity and its dependencies.
##
## Rule 36 requires every dependency to be explicit. A module that needs
## another module says so here, where the registry can check it, rather than
## discovering the coupling at runtime through a failed call.
##
## Depending on Core is implicit and must not be listed: Core is the contract
## layer every module may know.

@export var id: StringName = &""
@export var display_name: String = ""
@export var version: String = "0.1.0"
@export_multiline var description: String = ""

## Modules that must be registered for this one to function. Registration
## fails if any are missing.
@export var requires: Array[StringName] = []

## Modules this one will integrate with when present, and function without
## when absent. Missing optional modules are a valid state, not an error
## (rule 31).
@export var optional: Array[StringName] = []


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if id == &"":
		result.add_error(
			&"module.missing_id", "Module manifest has no id.", resource_path, "id"
		)
	if requires.has(id):
		result.add_error(
			&"module.self_dependency",
			"Module '%s' lists itself as a required dependency." % id,
			resource_path,
			"requires"
		)
	for dependency in requires:
		if optional.has(dependency):
			result.add_warning(
				&"module.ambiguous_dependency",
				"Module '%s' lists '%s' as both required and optional." % [id, dependency],
				resource_path,
				"requires"
			)
	return result


func get_debug_name() -> String:
	if not display_name.is_empty():
		return "%s (%s)" % [display_name, id]
	return str(id) if id != &"" else "<unnamed module>"
