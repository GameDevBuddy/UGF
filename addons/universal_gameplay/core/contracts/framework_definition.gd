class_name FrameworkDefinition
extends Resource
## Base class for every design-time definition Resource.
##
## A definition answers "what is this thing?". It is immutable shared content:
## hundreds of runtime instances may point at one definition, so a definition
## must never hold per-instance mutable state (rule 2, rule 16).
##
## Subclasses override [method validate] and call [code]super()[/code] first so
## the shared identity checks always run.

## Stable semantic identity. Persistence and cross-references use this, never
## the resource path, because paths are an implementation detail (rule 32).
@export var id: StringName = &""

## Author-facing name. Safe to localise; never use it as an identifier.
@export var display_name: String = ""

## Semantic vocabulary describing this definition. Pure data: no SceneTree
## membership is implied (Ontology Rulebook 12).
@export var tags: Array[StringName] = []


## Returns a [ValidationResult] describing everything wrong with this
## definition. Always returns a result, never null.
func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if id == &"":
		result.add_error(
			&"definition.missing_id",
			"Definition has no id. Persistence and cross-references need a stable id.",
			resource_path,
			"id"
		)
	if display_name.is_empty():
		result.add_warning(
			&"definition.missing_display_name",
			"Definition has no display_name; debug output will fall back to its id.",
			resource_path,
			"display_name"
		)
	for tag in tags:
		if tag == &"":
			result.add_warning(
				&"definition.empty_tag",
				"Definition has an empty tag entry.",
				resource_path,
				"tags"
			)
	return result


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## True when every tag in [param required] is present.
func has_all_tags(required: Array[StringName]) -> bool:
	for tag in required:
		if not tags.has(tag):
			return false
	return true


## True when at least one tag in [param any_of] is present.
func has_any_tag(any_of: Array[StringName]) -> bool:
	for tag in any_of:
		if tags.has(tag):
			return true
	return false


## Human-readable identity for logs, inspectors and validation output.
func get_debug_name() -> String:
	if not display_name.is_empty():
		return "%s (%s)" % [display_name, id]
	if id != &"":
		return str(id)
	if not resource_path.is_empty():
		return resource_path
	return "<unnamed definition>"
