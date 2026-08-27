class_name DialogueDefinition
extends FrameworkDefinition
## A whole conversation, as content.
##
## Nodes in a flat array addressed by id rather than a nested tree, for the
## same reason a scene graph is not a linked list: a conversation is a graph
## with loops and shared endings, and a tree cannot hold one. Ids rather than
## indices so inserting a line in the middle does not renumber every jump
## (rule 32).
##
## [b]The framework ships no editor for this.[/b] Implementation Plan 18 is
## explicit that the runtime contract matters and the authoring format does
## not: a project is expected to build or buy a graph tool that emits these
## resources. What the framework owes is a shape stable enough to be a
## compilation target.

## Every node, in no particular order. The first is not the start; that is
## [member start_node].
@export var nodes: Array[DialogueNode] = []

## Where the conversation begins. Blank uses the first node.
@export var start_node: StringName = &""

## Who is talking, when a line does not say. A semantic name rather than a node
## reference: content names parties, scenes bind them.
@export var default_speaker: StringName = &""

@export_group("Availability")
## Everything that must hold for this conversation to be offered at all.
@export var conditions: Array[DialogueCondition] = []

## Run once when the conversation starts, before the first node.
@export var start_actions: Array[DialogueAction] = []

## Run once when it ends, however it ended.
@export var end_actions: Array[DialogueAction] = []

@export_group("Repetition")
## Whether this can be had more than once. Off is a one-shot: an introduction,
## a confession, a will read aloud.
@export var repeatable: bool = true

var _index: Dictionary[StringName, DialogueNode] = {}
## Node count the index was last built for. A definition is shared and
## immutable at runtime, so the index is derived data rather than the mutable
## state rule 2 forbids -- and keying the check on the count rather than a flag
## means a node list edited in the inspector re-indexes.
var _indexed_for: int = -1


func find_node(node_id: StringName) -> DialogueNode:
	_ensure_index()
	return _index.get(node_id)


func has_node(node_id: StringName) -> bool:
	return find_node(node_id) != null


## The node the conversation starts on, or null when it has none.
func get_start_node() -> DialogueNode:
	if start_node != &"":
		return find_node(start_node)
	for node in nodes:
		if node != null:
			return node
	return null


func is_available(context: DialogueContext) -> bool:
	return DialogueCondition.all_hold(conditions, context)


func get_node_count() -> int:
	return nodes.size()


func validate() -> ValidationResult:
	var result := super()
	if nodes.is_empty():
		result.add_error(
			&"dialogue.no_nodes",
			"%s has no nodes, so there is nothing to say." % get_debug_name(),
			resource_path,
			"nodes"
		)
		return result

	var seen: Dictionary[StringName, bool] = {}
	for node in nodes:
		if node == null:
			result.add_warning(
				&"dialogue.empty_node_slot",
				"%s has an empty node slot." % get_debug_name(),
				resource_path,
				"nodes"
			)
			continue
		if node.id != &"" and seen.has(node.id):
			result.add_error(
				&"dialogue.duplicate_node_id",
				(
					"%s has two nodes with id '%s'; jumps to it would be "
					+ "ambiguous."
				) % [get_debug_name(), node.id],
				resource_path,
				"nodes"
			)
		seen[node.id] = true
		result.merge(node.validate())

	if start_node != &"" and not seen.has(start_node):
		result.add_error(
			&"dialogue.missing_start_node",
			(
				"%s starts on '%s', which does not exist, so it can never "
				+ "begin."
			) % [get_debug_name(), start_node],
			resource_path,
			"start_node"
		)

	_validate_targets(result, seen)
	_validate_reachability(result, seen)

	for condition in conditions:
		if condition != null:
			result.merge(condition.validate())
	for action in start_actions + end_actions:
		if action != null:
			result.merge(action.validate())
	return result


# --- Internals ------------------------------------------------------------

## Every jump lands somewhere. A dangling target is the commonest thing to get
## wrong in a hand-authored conversation and the hardest to notice, because it
## looks exactly like a conversation that was meant to end there.
func _validate_targets(result: ValidationResult, seen: Dictionary) -> void:
	for node in nodes:
		if node == null:
			continue
		for target in node.get_outgoing():
			if not seen.has(target):
				result.add_error(
					&"dialogue.dangling_target",
					(
						"%s: node '%s' leads to '%s', which does not exist."
					) % [get_debug_name(), node.id, target],
					resource_path,
					"nodes"
				)


## Nodes nothing can reach are content that will never be seen. A warning
## rather than an error: a conversation under construction has orphans, and
## failing the build over one would make the validator something people turn
## off.
func _validate_reachability(result: ValidationResult, seen: Dictionary) -> void:
	var start := get_start_node()
	if start == null:
		return
	var reached: Dictionary[StringName, bool] = {}
	var frontier: Array[StringName] = [start.id]
	while not frontier.is_empty():
		var current: StringName = frontier.pop_back()
		if reached.has(current):
			continue
		reached[current] = true
		var node := find_node(current)
		if node == null:
			continue
		for target in node.get_outgoing():
			if seen.has(target) and not reached.has(target):
				frontier.append(target)

	for node in nodes:
		if node != null and node.id != &"" and not reached.has(node.id):
			result.add_warning(
				&"dialogue.unreachable_node",
				(
					"%s: node '%s' cannot be reached from the start, so it will "
					+ "never be seen."
				) % [get_debug_name(), node.id],
				resource_path,
				"nodes"
			)


func _ensure_index() -> void:
	if _indexed_for == nodes.size():
		return
	_index.clear()
	for node in nodes:
		if node != null and node.id != &"":
			_index[node.id] = node
	_indexed_for = nodes.size()
