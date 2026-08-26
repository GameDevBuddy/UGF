class_name DefinitionValidator
extends RefCounted
## Scans and validates definition content.
##
## Content validation is a framework deliverable, not a nicety (rule 27). Most
## of what breaks a data-driven game is not bad code but bad data -- a mission
## referencing an item that was renamed, two definitions claiming one id, a
## recipe whose output no longer exists. Those failures surface hours later as
## confusing runtime behaviour unless something scans for them up front.
##
## Every method is static: this holds no state and has no reason to be an
## instance, let alone a service (rule 28).


## Validates every definition in [param registry], plus registry-wide
## invariants that no single definition can check for itself.
static func validate_registry(registry: DefinitionRegistry) -> ValidationResult:
	var result := ValidationResult.new()
	if registry == null:
		result.add_error(
			&"validator.null_registry", "Cannot validate a null registry."
		)
		return result

	for definition in registry.get_all():
		result.merge(validate_definition(definition))

	result.merge(check_id_collisions(registry))
	return result


## Validates one definition, guarding against a subclass whose [method
## FrameworkDefinition.validate] forgets to return a result.
static func validate_definition(definition: FrameworkDefinition) -> ValidationResult:
	var result := ValidationResult.new()
	if definition == null:
		result.add_error(
			&"validator.null_definition", "Encountered a null definition."
		)
		return result

	var own := definition.validate()
	if own == null:
		result.add_error(
			&"validator.no_result",
			"%s.validate() returned null instead of a ValidationResult."
			% definition.get_debug_name(),
			definition.resource_path
		)
		return result

	result.merge(own)
	return result


## Flags ids that differ only by case or surrounding whitespace.
##
## The registry already rejects exact duplicates at registration. These are the
## near-misses it cannot reject, because they are technically distinct ids --
## and they are the ones that produce a bug report reading "the wrong item
## spawned and I cannot see why".
static func check_id_collisions(registry: DefinitionRegistry) -> ValidationResult:
	var result := ValidationResult.new()
	if registry == null:
		return result

	var normalised: Dictionary[String, StringName] = {}
	for id in registry.get_ids():
		var key := str(id).strip_edges().to_lower()
		if key.is_empty():
			continue
		if normalised.has(key):
			var other: StringName = normalised[key]
			if other != id:
				var definition := registry.get_definition(id)
				result.add_warning(
					&"validator.near_duplicate_id",
					(
						"Definition ids '%s' and '%s' differ only by case or whitespace."
						% [id, other]
					),
					definition.resource_path if definition != null else "",
					"id"
				)
		else:
			normalised[key] = id
	return result


## Checks that every id in [param referenced_ids] resolves in [param registry].
##
## Modules call this from their own validators to check cross-references --
## a loot table's item ids, a mission's objective ids -- without Core needing
## to know those types exist.
static func check_references(
	registry: DefinitionRegistry,
	referenced_ids: Array[StringName],
	source_path: String = "",
	context: String = ""
) -> ValidationResult:
	var result := ValidationResult.new()
	if registry == null:
		result.add_error(
			&"validator.null_registry", "Cannot resolve references against a null registry."
		)
		return result

	for id in referenced_ids:
		if id == &"":
			result.add_warning(
				&"validator.empty_reference",
				"Empty definition reference.",
				source_path,
				context
			)
		elif not registry.has_definition(id):
			result.add_error(
				&"validator.unresolved_reference",
				"Reference to definition '%s', which is not registered." % id,
				source_path,
				context
			)
	return result


## Detects a cycle in a dependency graph of definition ids.
##
## Mission chains, recipe trees and dialogue jumps are all graphs that must not
## loop; Implementation Plan 28 calls out circular mission chains specifically.
## [param edges] maps an id to the ids it points at.
static func find_cycles(edges: Dictionary[StringName, Array]) -> Array[Array]:
	var cycles: Array[Array] = []
	var visited: Dictionary[StringName, int] = {}
	# 0/absent = unvisited, 1 = on the current path, 2 = fully explored.
	for start in edges:
		if not visited.has(start):
			var path: Array[StringName] = []
			_walk_for_cycles(start, edges, visited, path, cycles)
	return cycles


static func _walk_for_cycles(
	node: StringName,
	edges: Dictionary[StringName, Array],
	visited: Dictionary[StringName, int],
	path: Array[StringName],
	cycles: Array[Array]
) -> void:
	visited[node] = 1
	path.append(node)

	for next in edges.get(node, []):
		var state: int = visited.get(next, 0)
		if state == 1:
			# Found a back edge: slice the path from where it re-enters.
			var start_index := path.find(next)
			if start_index != -1:
				var cycle: Array[StringName] = []
				cycle.assign(path.slice(start_index))
				cycles.append(cycle)
		elif state == 0:
			_walk_for_cycles(next, edges, visited, path, cycles)

	path.pop_back()
	visited[node] = 2
