class_name InteractionComponent
extends FrameworkComponent
## The capability of being interacted with. Lives on the door, the chest, the
## NPC, the car.
##
## Owns the list of things that can be done to this entity, whether each is
## currently available, and the transaction that runs one of them. The
## interactor supplies the who and the when; this owns the what (rule 4).
##
## [b]One pipeline, four objects.[/b] A door, a pickup, an NPC and a vehicle
## differ only in the [InteractionDefinition] resources on this component and
## in what listens to [signal interaction_completed]. Nothing above this knows
## which kind of thing it is talking to -- an interactor holds an
## [InteractionComponent], not a Door.
##
## [b]It never reaches for the interactor.[/b] Everything about who is
## interacting arrives in the [InteractionContext], which is what lets an AI,
## a player and a test call the same method (rule 20).

## Emitted when an attempt begins, before any timing has elapsed.
signal interaction_started(context: InteractionContext)
## Emitted once the action has run and the interaction has taken effect.
signal interaction_completed(context: InteractionContext, result: FrameworkResult)
## Emitted when an attempt was refused, at the start or at the end.
signal interaction_failed(context: InteractionContext, result: FrameworkResult)
## Emitted when a timed interaction was abandoned before completing.
signal interaction_cancelled(context: InteractionContext, reason: StringName)
## Emitted when what this entity offers may have changed, so a prompt can be
## re-read rather than polled.
signal availability_changed

## What can be done here. Overrides the definition's list when non-empty, so a
## specific door in a specific scene can offer something extra without a new
## definition resource.
@export var interactions_override: Array[InteractionDefinition] = []

## Off makes the entity temporarily inert: a terminal with no power, a corpse
## already looted. Distinct from having no interactions, which is permanent.
@export var enabled: bool = true

## The states actions and requirements read and write. Wired at composition
## time; found among this entity's own components when it is not.
@export var semantic_state: SemanticState

## Tick cooldowns from [method Node._physics_process]. Ignored entirely when no
## interaction here has a cooldown -- rule 26 forbids a component that
## processes every frame for nothing.
@export var auto_tick: bool = true

var _interactions: Array[InteractionDefinition] = []
var _cooldowns: Dictionary[StringName, float] = {}
var _used: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_register_group()
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _needs_ticking())


func initialize(context: EntityContext) -> void:
	super(context)
	_interactions = _resolve_interactions()
	if semantic_state == null:
		semantic_state = _find_semantic_state()
	_register_group()
	set_physics_process(auto_tick and _needs_ticking())


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

## Everything this entity offers, available or not.
func get_interactions() -> Array[InteractionDefinition]:
	if _interactions.is_empty() and not is_initialized():
		# Usable before assembly, so a plain scene with no binder still works.
		_interactions = _resolve_interactions()
	return _interactions.duplicate()


func find_interaction(id: StringName) -> InteractionDefinition:
	for definition in get_interactions():
		if definition != null and definition.id == id:
			return definition
	return null


func has_interactions() -> bool:
	return not get_interactions().is_empty()


## Whether this entity is worth prompting about at all right now.
func is_interactable() -> bool:
	return enabled and has_interactions()


## What [param interactor] could do here, best first.
##
## Definitions marked [member InteractionDefinition.show_when_unavailable] are
## included even when refused, because "Locked" is a better prompt than
## silence; [method can_interact] still says no.
func get_available(interactor: Node) -> Array[InteractionDefinition]:
	var available: Array[InteractionDefinition] = []
	if not enabled:
		return available
	for definition in get_interactions():
		if definition == null:
			continue
		if _is_spent(definition):
			continue
		var offered := (
			definition.show_when_unavailable
			or can_interact(make_context(interactor, definition)).is_ok()
		)
		if offered:
			available.append(definition)
	available.sort_custom(_by_priority)
	return available


## The one an interact press would run, or null when there is nothing to do.
func get_primary(interactor: Node) -> InteractionDefinition:
	for definition in get_available(interactor):
		if can_interact(make_context(interactor, definition)).is_ok():
			return definition
	return null


## Prompt line for [param interactor], or an empty string for no prompt.
##
## An unavailable-but-shown interaction reports why instead: "Requires
## keycard", straight from the requirement that refused.
func get_prompt(interactor: Node) -> String:
	for definition in get_available(interactor):
		var result := can_interact(make_context(interactor, definition))
		if result.is_ok():
			return definition.get_prompt()
		if definition.show_when_unavailable:
			return result.message if not result.message.is_empty() else definition.get_prompt()
	return ""


## Seconds left before [param definition] can be used again.
## The entity this component speaks for: the door, not the component node.
## What an interactor measures distance to.
func get_entity_root() -> Node:
	return _get_root()


func get_cooldown_remaining(definition: InteractionDefinition) -> float:
	if definition == null:
		return 0.0
	return _cooldowns.get(_key(definition), 0.0)


## Whether a one-shot interaction has already been used.
func is_spent(definition: InteractionDefinition) -> bool:
	return _is_spent(definition)


# --- The transaction ------------------------------------------------------

## Builds the context for an attempt. Exposed because an interactor needs to
## ask before it commits, and because a caller with no interactor component --
## a trigger volume, a test -- still needs a well-formed context.
func make_context(
	interactor: Node, definition: InteractionDefinition = null
) -> InteractionContext:
	var context := InteractionContext.create(interactor, _get_root(), definition)
	context.interaction = self
	context.interactor_component = InteractorComponent.find_on(interactor)
	return context


## Whether [param context] could run right now. Pure: safe to call every frame
## while a prompt is on screen.
func can_interact(context: InteractionContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(
			&"interaction.null_context", "Cannot interact with no context."
		)
	if not enabled:
		return FrameworkResult.fail(
			&"interaction.disabled", "This cannot be used right now."
		)

	var definition := context.definition
	if definition == null:
		# Falling back to the best offered rather than the best available is
		# what makes the refusal legible: a door with one locked interaction
		# should say "Requires a keycard", not "there is nothing to do here".
		# The latter is reserved for an entity that genuinely offers nothing.
		definition = get_primary(context.interactor)
		if definition == null:
			definition = _first_offered()
		if definition == null:
			return FrameworkResult.fail(
				&"interaction.none_available", "There is nothing to do here."
			)
		context.definition = definition
	elif not get_interactions().has(definition):
		return FrameworkResult.fail(
			&"interaction.not_offered",
			"%s is not offered by this entity." % definition.get_debug_name()
		)

	if _is_spent(definition):
		return FrameworkResult.fail(
			&"interaction.spent", "This has already been used."
		)
	var remaining := get_cooldown_remaining(definition)
	if remaining > 0.0:
		return FrameworkResult.fail(
			&"interaction.cooling_down",
			"Not ready for another %.1fs." % remaining
		)

	for requirement in definition.requirements:
		if requirement == null:
			continue
		var met := requirement.check(context)
		if met.is_err():
			return met

	if definition.action != null:
		return definition.action.can_execute(context)
	return FrameworkResult.ok(null)


## Announces the start of an attempt without completing it. What a timed
## interaction calls first, so the door can start creaking while it winds up.
func begin(context: InteractionContext) -> FrameworkResult:
	var result := can_interact(context)
	if result.is_err():
		interaction_failed.emit(context, result)
		return result
	interaction_started.emit(context)
	return FrameworkResult.ok(context.definition)


## Runs the action and commits the interaction. The end of a timed attempt, or
## the whole of an instant one via [method interact].
##
## Re-checks first: a timed interaction can be started while the key is in the
## bag and finished after it was dropped, and rule 17 says the check that
## matters is the one at the moment of the change.
func complete(context: InteractionContext) -> FrameworkResult:
	var allowed := can_interact(context)
	if allowed.is_err():
		interaction_failed.emit(context, allowed)
		return allowed

	var definition := context.definition
	var result := FrameworkResult.ok(null)
	if definition.action != null:
		result = definition.action.execute(context)
		if result.is_err():
			# An action that refuses late leaves nothing behind: no cooldown,
			# no spent flag, no consumed key.
			interaction_failed.emit(context, result)
			return result

	for requirement in definition.requirements:
		if requirement != null:
			requirement.commit(context)

	if not definition.repeatable:
		_used[_key(definition)] = true
	elif definition.has_cooldown():
		_cooldowns[_key(definition)] = definition.cooldown
		set_physics_process(auto_tick and _needs_ticking())

	interaction_completed.emit(context, result)
	availability_changed.emit()
	return result


## Begin and complete in one call. The instant interaction.
func interact(context: InteractionContext) -> FrameworkResult:
	var started := begin(context)
	if started.is_err():
		return started
	return complete(context)


## Convenience for a caller holding an interactor and an id rather than a
## context: an AI task, a trigger volume, a debug command.
func interact_by(
	interactor: Node, definition: InteractionDefinition = null
) -> FrameworkResult:
	return interact(make_context(interactor, definition))


## Reports an abandoned attempt. Nothing is rolled back because nothing was
## applied -- [method complete] is the only thing that changes state.
func cancel(context: InteractionContext, reason: StringName = &"cancelled") -> void:
	interaction_cancelled.emit(context, reason)


# --- Time -----------------------------------------------------------------

## Advances cooldowns. Called for you when [member auto_tick] is on.
func tick(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	var expired: Array[StringName] = []
	for key in _cooldowns:
		var remaining: float = _cooldowns[key] - delta
		if remaining <= 0.0:
			expired.append(key)
		else:
			_cooldowns[key] = remaining
	for key in expired:
		_cooldowns.erase(key)
	if not expired.is_empty():
		availability_changed.emit()
	if _cooldowns.is_empty():
		set_physics_process(auto_tick and _needs_ticking())


## Makes a one-shot usable again and clears any cooldown. What a respawning
## world object calls, and what a save restore uses.
func reset(definition: InteractionDefinition = null) -> void:
	if definition == null:
		_used.clear()
		_cooldowns.clear()
	else:
		_used.erase(_key(definition))
		_cooldowns.erase(_key(definition))
	availability_changed.emit()


# --- Discovery ------------------------------------------------------------

## The interaction component on [param node], searching its own components
## only. Returns null for a node that cannot be interacted with, which is the
## normal answer for most of the world.
static func find_on(node: Node) -> InteractionComponent:
	if node == null:
		return null
	if node is InteractionComponent:
		return node as InteractionComponent
	for component in DefinitionBinder.collect_components(node):
		if component is InteractionComponent:
			return component as InteractionComponent
	return null


# --- Persistence ----------------------------------------------------------
#
# One-shots and cooldowns are the only mutable state here, and both matter: a
# lever that welds itself must stay welded across a save.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var used: Array[String] = []
	for key in _used:
		used.append(String(key))
	var cooldowns: Dictionary = {}
	for key in _cooldowns:
		cooldowns[String(key)] = _cooldowns[key]
	return {"used": used, "cooldowns": cooldowns, "enabled": enabled}


func restore_state(data: Dictionary) -> void:
	_used.clear()
	_cooldowns.clear()
	for key in data.get("used", []):
		_used[StringName(key)] = true
	var cooldowns: Dictionary = data.get("cooldowns", {})
	for key in cooldowns:
		_cooldowns[StringName(key)] = float(cooldowns[key])
	enabled = bool(data.get("enabled", enabled))
	set_physics_process(auto_tick and _needs_ticking())
	availability_changed.emit()


# --- Internals ------------------------------------------------------------

func _by_priority(a: InteractionDefinition, b: InteractionDefinition) -> bool:
	return a.priority > b.priority


## Keyed by semantic id so a save survives the resource being moved on disk
## (rule 32). A definition with no id fails validation already; it falls in
## with every other unnamed one here rather than crashing.
func _key(definition: InteractionDefinition) -> StringName:
	return definition.id if definition.id != &"" else &"<unnamed>"


## The highest-priority interaction offered here, available or not.
func _first_offered() -> InteractionDefinition:
	var offered := get_interactions()
	offered = offered.filter(func(entry: InteractionDefinition) -> bool: return entry != null)
	if offered.is_empty():
		return null
	offered.sort_custom(_by_priority)
	return offered[0]


func _is_spent(definition: InteractionDefinition) -> bool:
	if definition == null or definition.repeatable:
		return false
	return _used.has(_key(definition))


func _needs_ticking() -> bool:
	return not _cooldowns.is_empty()


## The entity this component speaks for. Falls back to the parent so a plain
## door scene with no binder is still a valid target (rule 31).
func _get_root() -> Node:
	var entity := get_entity()
	return entity if entity != null else get_parent()


func _register_group() -> void:
	var root := _get_root()
	if root != null and root.is_inside_tree():
		root.add_to_group(GameplayNames.GROUP_INTERACTABLE)


## Read by property name rather than by casting, so a vehicle or a world object
## with its own definition type can be interactable without this module
## importing another's types (rule 9).
func _resolve_interactions() -> Array[InteractionDefinition]:
	if not interactions_override.is_empty():
		return interactions_override.duplicate()
	var definition := get_definition()
	if definition != null and "interactions" in definition:
		var candidate: Variant = definition.get("interactions")
		if candidate is Array:
			var out: Array[InteractionDefinition] = []
			for entry in candidate as Array:
				if entry is InteractionDefinition:
					out.append(entry as InteractionDefinition)
			return out
	var empty: Array[InteractionDefinition] = []
	return empty


func _find_semantic_state() -> SemanticState:
	var root := _get_root()
	if root == null:
		return null
	for component in DefinitionBinder.collect_components(root):
		if component is SemanticState:
			return component as SemanticState
	return null
