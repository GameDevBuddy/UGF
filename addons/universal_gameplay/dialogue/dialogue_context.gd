class_name DialogueContext
extends RefCounted
## Everything one conversation knows about itself.
##
## Built by [DialogueRuntime], read by every condition, written by every
## action. The same role [InteractionContext] and [AttackContext] play, and for
## the same reason: a conversation crosses module boundaries -- Narrative,
## Items, Commerce and Missions all touch one -- and none of them should have
## to depend on another to speak about it.

## Who is talking: the NPC, the terminal, the sign.
var speaker: Node = null

## Who they are talking to. Usually the player's character.
var listener: Node = null

## Which conversation is running.
var definition: DialogueDefinition = null

## Weak handle on the runtime driving this conversation.
##
## [b]Weak on purpose.[/b] The runtime holds this context; a strong reference
## back closes a [RefCounted] cycle Godot's reference counting cannot break,
## and the entire conversation graph -- definition, nodes, conditions,
## actions -- then survives to exit as a leak. Use [method get_runtime].
var _runtime_ref: WeakRef = null

## Where flags and variables live. Null is a legitimate configuration: a
## conversation with no conditions and no consequences needs no store, and
## everything here degrades to "unknown" rather than erroring (rule 31).
var narrative: NarrativeStateService = null

## Values scoped to this conversation only, cleared when it ends. What a
## "which of the three answers did they pick" branch uses without leaving
## anything in the save.
var locals: Dictionary[StringName, Variant] = {}

## Free-form per-conversation bag. Deliberately small.
var extras: Dictionary = {}


## The runtime driving this conversation, or null once it has ended or been
## collected. An action that wants to redirect the conversation rather than
## merely change the world asks here.
func get_runtime() -> DialogueRuntime:
	if _runtime_ref == null:
		return null
	return _runtime_ref.get_ref() as DialogueRuntime


func set_runtime(runtime: DialogueRuntime) -> void:
	_runtime_ref = weakref(runtime) if runtime != null else null


static func create(
	p_speaker: Node,
	p_listener: Node,
	p_definition: DialogueDefinition = null,
	p_narrative: NarrativeStateService = null
) -> DialogueContext:
	var context := DialogueContext.new()
	context.speaker = p_speaker
	context.listener = p_listener
	context.definition = p_definition
	context.narrative = p_narrative
	return context


# --- Narrative, safely ----------------------------------------------------
#
# Every read answers something sensible with no store attached, so a condition
# is one expression rather than one expression wrapped in a null check.

func get_flag(flag: StringName) -> bool:
	return narrative.get_flag(flag) if narrative != null else false


func set_flag(flag: StringName, value: bool = true) -> void:
	if narrative != null:
		narrative.set_flag(flag, value)


func get_variable(key: StringName, fallback: Variant = null) -> Variant:
	if locals.has(key):
		return locals[key]
	return narrative.get_variable(key, fallback) if narrative != null else fallback


func get_counter(counter: StringName) -> int:
	return narrative.get_counter(counter) if narrative != null else 0


# --- The parties ----------------------------------------------------------

## The listener's bag, when they have one. Null is a normal answer.
func get_listener_inventory() -> InventoryComponent:
	return _find_inventory(listener)


func get_speaker_inventory() -> InventoryComponent:
	return _find_inventory(speaker)


func get_listener_stats() -> StatsComponent:
	if listener == null:
		return null
	for component in DefinitionBinder.collect_components(listener):
		if component is StatsComponent:
			return component as StatsComponent
	return null


func _find_inventory(node: Node) -> InventoryComponent:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _to_string() -> String:
	var who := speaker.name if speaker != null else "<nobody>"
	var what := definition.get_debug_name() if definition != null else "<no dialogue>"
	return "DialogueContext(%s: %s)" % [who, what]
