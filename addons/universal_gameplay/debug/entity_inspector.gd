class_name EntityInspector
extends RefCounted
## Reports what an entity actually is at runtime.
##
## Debugability is architecture, not a nicety (rule 28 of the Implementation
## Plan). A data-driven entity assembled from a definition, a scene and a stack
## of components is genuinely hard to reason about from the remote inspector
## alone -- "which definition is this, what is bound, what would it save?" is
## the question this answers.
##
## Read-only by construction: every method here observes and none mutate.


## Structured snapshot, for a debug panel or a test.
static func inspect(entity: Node) -> Dictionary:
	if entity == null:
		return {"error": "null entity"}

	var data: Dictionary = {
		"name": entity.name,
		"class": entity.get_class(),
		"is_entity_root": DefinitionBinder.is_entity_root(entity),
	}

	var binder := EntitySerializer.find_binder(entity)
	if binder != null:
		data["bound"] = binder.is_bound()
		var definition := binder.get_definition()
		if definition != null:
			data["definition_id"] = definition.id
			data["definition_tags"] = definition.tags
		else:
			data["definition_id"] = &""

	var identity := EntitySerializer.find_identity(entity)
	if identity != null:
		# Read the stored value rather than get_persistent_id(), so inspecting
		# an entity never causes it to mint an id it did not already have.
		data["persistent_id"] = identity.persistent_id
		data["saveable"] = identity.is_saveable()

	var components: Array[Dictionary] = []
	for component in DefinitionBinder.collect_components(entity):
		components.append({
			"name": component.name,
			"script": _script_name(component),
			"state_key": component.get_state_key(),
			"initialized": component.is_initialized(),
			"persistent": component.is_persistent(),
		})
	data["components"] = components

	var semantic := _find_semantic_state(entity)
	if semantic != null:
		data["states"] = semantic.get_states()

	var groups: Array[StringName] = []
	for group in entity.get_groups():
		if not str(group).begins_with("_"):
			groups.append(group)
	data["groups"] = groups

	return data


## Human-readable dump, for a console or a log line.
static func describe(entity: Node) -> String:
	var data := inspect(entity)
	if data.has("error"):
		return "<%s>" % data["error"]

	var lines := PackedStringArray()
	lines.append("%s [%s]" % [data["name"], data["class"]])

	if data.has("definition_id"):
		var definition_id: StringName = data["definition_id"]
		lines.append(
			"  definition: %s%s"
			% [
				definition_id if definition_id != &"" else "<none>",
				"" if data.get("bound", false) else "  (NOT BOUND)",
			]
		)
	if data.has("definition_tags") and not (data["definition_tags"] as Array).is_empty():
		lines.append("  tags: %s" % str(data["definition_tags"]))
	if data.has("persistent_id"):
		var pid: StringName = data["persistent_id"]
		lines.append(
			"  save id: %s%s"
			% [
				pid if pid != &"" else "<not yet generated>",
				"" if data.get("saveable", true) else "  (not saveable)",
			]
		)
	if data.has("states") and not (data["states"] as Array).is_empty():
		lines.append("  states: %s" % str(data["states"]))
	if not (data["groups"] as Array).is_empty():
		lines.append("  groups: %s" % str(data["groups"]))

	var components: Array = data["components"]
	if components.is_empty():
		lines.append("  components: none")
	else:
		lines.append("  components:")
		for component in components:
			var flags := PackedStringArray()
			if not component["initialized"]:
				flags.append("UNINITIALISED")
			if component["persistent"]:
				flags.append("saved as '%s'" % component["state_key"])
			var suffix := "  (%s)" % " ".join(flags) if not flags.is_empty() else ""
			lines.append("    - %s : %s%s" % [component["name"], component["script"], suffix])

	return "\n".join(lines)


## What this entity would write to a save right now, with any problems found
## while capturing it. Answers "why is this not persisting correctly?" without
## running a save.
static func preview_save_state(entity: Node) -> Dictionary:
	var issues := ValidationResult.new()
	var record := EntitySerializer.capture(entity, issues)
	return {
		"record": record.to_dictionary(),
		"saveable": EntitySerializer.is_saveable(entity),
		"issues": issues.format_report(),
	}


static func _find_semantic_state(entity: Node) -> SemanticState:
	for component in DefinitionBinder.collect_components(entity):
		if component is SemanticState:
			return component as SemanticState
	return null


static func _script_name(node: Node) -> String:
	var script := node.get_script() as Script
	if script == null:
		return node.get_class()
	var global_name := script.get_global_name()
	if global_name != &"":
		return str(global_name)
	return script.resource_path.get_file()
