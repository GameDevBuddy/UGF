class_name InteractorComponent
extends FrameworkComponent
## The capability of interacting with things. Lives on whoever does the using:
## the player's character, an NPC, a companion.
##
## Owns focus -- what is currently in reach -- and time, which is the whole of
## a timed interaction. It owns neither the rules nor the effect: those belong
## to the [InteractionComponent] on the target (rule 4).
##
## [b]An AI uses this exactly as a player does.[/b] There is no AI path.
## [method interact] is the same call whether it came from a button, a
## behaviour tree or a test, which is the same arrangement locomotion has and
## the reason the exit gate for M2 asked for it.
##
## [b]It polls, and says so.[/b] Rule 26 forbids components that process every
## frame for nothing; focus scanning is a real exception rather than a
## permanent one -- it runs on an interval, it stops when there is nothing to
## do, and [member InteractorProfile.auto_focus] turns it off entirely for a
## project that drives focus from an Area3D instead.

## Emitted when what is in reach changes, including to nothing.
signal focus_changed(interaction: InteractionComponent)
## Emitted when the prompt line for the current focus changes. What a HUD
## listens to instead of reading the prompt every frame (rule 21).
signal prompt_changed(prompt: String)
## Emitted when an attempt begins.
signal interaction_started(context: InteractionContext)
## Emitted each tick of a timed interaction, with progress in 0..1.
signal interaction_progressed(context: InteractionContext, progress: float)
## Emitted once the interaction has taken effect.
signal interaction_completed(context: InteractionContext, result: FrameworkResult)
## Emitted when an attempt was refused.
signal interaction_failed(context: InteractionContext, result: FrameworkResult)
## Emitted when a timed attempt was abandoned.
signal interaction_cancelled(context: InteractionContext, reason: StringName)

## Reach and focus settings. Takes precedence over the definition's profile.
@export var profile_override: InteractorProfile

## The bag actions and requirements reach for. Wired at composition time;
## found among this entity's own components when it is not. Null is normal --
## a creature with no bag can still open a door (rule 31).
@export var inventory: InventoryComponent

## Attributes an action may read, e.g. a strength check on a jammed door.
@export var stats: StatsComponent

## States mirrored while an interaction is running.
@export var semantic_state: SemanticState

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _profile: InteractorProfile = null
var _focus: InteractionComponent = null
var _prompt: String = ""
var _attempt: InteractionContext = null
var _elapsed: float = 0.0
var _since_scan: float = 0.0


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _needs_ticking())


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent
	if stats == null:
		stats = _find(StatsComponent) as StatsComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	set_physics_process(auto_tick and _needs_ticking())


func _physics_process(delta: float) -> void:
	tick(delta)


func get_profile() -> InteractorProfile:
	return _profile


func get_reach() -> float:
	return _profile.reach if _profile != null else 2.5


# --- Focus ----------------------------------------------------------------

## What is currently in reach, or null.
func get_focus() -> InteractionComponent:
	return _focus


## Points this interactor at something, or at nothing when [param interaction]
## is null. The entry point for a project that owns detection itself: an
## Area3D's [signal Area3D.body_entered] calls this and turns
## [member InteractorProfile.auto_focus] off.
func set_focus(interaction: InteractionComponent) -> void:
	if interaction == _focus:
		_refresh_prompt()
		return
	_focus = interaction
	focus_changed.emit(_focus)
	_refresh_prompt()
	set_physics_process(auto_tick and _needs_ticking())


func clear_focus() -> void:
	set_focus(null)


## The prompt for the current focus, or an empty string. Cached: reading this
## every frame costs nothing, and [signal prompt_changed] is the better hook.
func get_prompt() -> String:
	return _prompt


## Rescans for the nearest interactable in reach and focuses it.
##
## Called for you on an interval when the profile asks for it. Scans the
## [constant GameplayNames.GROUP_INTERACTABLE] group, which is what that group
## exists for -- discovery by membership, not by walking the tree (rule 22).
func refresh_focus() -> void:
	set_focus(find_best_target())


## The best target in reach right now, without changing focus. Separated so a
## project can apply its own tie-breaks -- a look-direction test, a priority --
## on top of distance.
func find_best_target() -> InteractionComponent:
	var tree := get_tree()
	if tree == null:
		return null
	var best: InteractionComponent = null
	var best_distance := INF
	var reach := get_reach()
	for node in tree.get_nodes_in_group(GameplayNames.GROUP_INTERACTABLE):
		if node == get_entity() or not node is Node:
			continue
		var interaction := InteractionComponent.find_on(node as Node)
		if interaction == null or not interaction.is_interactable():
			continue
		if interaction.get_available(get_entity()).is_empty():
			continue
		var distance := _distance_to(node as Node)
		if distance > reach or distance >= best_distance:
			continue
		best = interaction
		best_distance = distance
	return best


func is_in_reach(target: Node) -> bool:
	return _distance_to(target) <= get_reach()


# --- Interacting ----------------------------------------------------------

## Whether a timed interaction is running.
func is_busy() -> bool:
	return _attempt != null


## Progress of the running interaction in 0..1, or zero when idle.
func get_progress() -> float:
	if _attempt == null or _attempt.definition == null:
		return 0.0
	if not _attempt.definition.is_timed():
		return 1.0
	return clampf(_elapsed / _attempt.definition.duration, 0.0, 1.0)


## The attempt in progress, or null.
func get_attempt() -> InteractionContext:
	return _attempt


## Uses whatever is in focus. The one call a player input handler and an AI
## task both make.
func interact(definition: InteractionDefinition = null) -> FrameworkResult:
	if _focus == null:
		return FrameworkResult.fail(
			&"interactor.no_focus", "There is nothing in reach."
		)
	return begin(_focus, definition)


## Uses a specific target, in reach or not focused. What an AI with its own
## target selection calls, and what a scripted sequence calls.
func begin(
	target: Variant, definition: InteractionDefinition = null
) -> FrameworkResult:
	var interaction := _as_interaction(target)
	if interaction == null:
		return FrameworkResult.fail(
			&"interactor.no_target", "That cannot be interacted with."
		)
	if is_busy():
		return FrameworkResult.fail(
			&"interactor.busy", "Already interacting with something."
		)
	if not is_in_reach(interaction.get_entity_root()):
		return FrameworkResult.fail(
			&"interactor.out_of_reach", "That is too far away."
		)

	var context := interaction.make_context(get_entity(), definition)
	context.interactor_component = self
	var started := interaction.begin(context)
	if started.is_err():
		interaction_failed.emit(context, started)
		return started

	interaction_started.emit(context)
	if not context.definition.is_timed():
		return _finish(context, interaction)

	_attempt = context
	_elapsed = 0.0
	_set_state(true)
	set_physics_process(auto_tick and _needs_ticking())
	return FrameworkResult.ok(context)


## Abandons a running timed interaction. Nothing is rolled back because nothing
## was applied: only completion changes state.
##
## An interaction marked uninterruptible ignores this, which is what that flag
## means: releasing the button does not abandon a commitment. [param force] is
## for the cases that are not the player changing their mind -- the target
## being destroyed, the entity being despawned.
func cancel(reason: StringName = &"cancelled", force: bool = false) -> void:
	if _attempt == null:
		return
	if not force and _attempt.definition != null and not _attempt.definition.interruptible:
		return
	var context := _attempt
	var interaction := context.interaction
	_clear_attempt()
	if interaction != null:
		interaction.cancel(context, reason)
	interaction_cancelled.emit(context, reason)


# --- Time -----------------------------------------------------------------

## Advances focus scanning and any running interaction. Called for you when
## [member auto_tick] is on.
func tick(delta: float) -> void:
	_tick_focus(delta)
	_tick_attempt(delta)


func _tick_focus(delta: float) -> void:
	if _profile == null or not _profile.auto_focus:
		return
	_since_scan += delta
	if _since_scan < _profile.focus_interval:
		return
	_since_scan = 0.0
	refresh_focus()


func _tick_attempt(delta: float) -> void:
	if _attempt == null:
		return
	var definition := _attempt.definition
	var interaction := _attempt.interaction

	if definition.interruptible and _should_break_off(interaction):
		cancel(&"out_of_reach")
		return

	_elapsed += delta
	interaction_progressed.emit(_attempt, get_progress())
	if _elapsed < definition.duration:
		return

	var context := _attempt
	_clear_attempt()
	_finish(context, interaction)


# --- Persistence ----------------------------------------------------------
#
# Focus and a half-finished interaction are both moment-to-moment state that a
# load should not restore: the world has moved. Nothing here is persistent.

# --- Internals ------------------------------------------------------------

func _finish(
	context: InteractionContext, interaction: InteractionComponent
) -> FrameworkResult:
	if interaction == null or not is_instance_valid(interaction):
		var gone := FrameworkResult.fail(
			&"interactor.target_gone", "The target is no longer there."
		)
		interaction_failed.emit(context, gone)
		return gone
	var result := interaction.complete(context)
	if result.is_err():
		interaction_failed.emit(context, result)
	else:
		interaction_completed.emit(context, result)
	_refresh_prompt()
	return result


func _should_break_off(interaction: InteractionComponent) -> bool:
	if interaction == null or not is_instance_valid(interaction):
		return true
	if _profile != null and not _profile.cancel_when_out_of_reach:
		return false
	return not is_in_reach(interaction.get_entity_root())


func _clear_attempt() -> void:
	_attempt = null
	_elapsed = 0.0
	_set_state(false)
	set_physics_process(auto_tick and _needs_ticking())


func _set_state(active: bool) -> void:
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_INTERACTING, active)


func _refresh_prompt() -> void:
	var prompt := _focus.get_prompt(get_entity()) if _focus != null else ""
	if prompt == _prompt:
		return
	_prompt = prompt
	prompt_changed.emit(_prompt)


func _needs_ticking() -> bool:
	if _attempt != null:
		return true
	return _profile != null and _profile.auto_focus


func _as_interaction(target: Variant) -> InteractionComponent:
	if target is InteractionComponent:
		return target as InteractionComponent
	if target is Node:
		return InteractionComponent.find_on(target as Node)
	return null


## Distance from this interactor to [param target] in metres.
##
## Zero when either end is not spatial. That is deliberate: a headless test
## entity and a non-spatial UI target are both always in reach, and refusing
## them would make the module untestable without a 3D scene (rule 33).
func _distance_to(target: Node) -> float:
	var here := _get_position(get_entity())
	var there := _get_position(target)
	if here == null or there == null:
		return 0.0
	return (here as Vector3).distance_to(there as Vector3)


func _get_position(node: Node) -> Variant:
	if node is Node3D:
		return (node as Node3D).global_position
	if node is Node2D:
		var flat := (node as Node2D).global_position
		return Vector3(flat.x, flat.y, 0.0)
	return null


func _resolve_profile() -> InteractorProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "interaction" in definition:
		var candidate: Variant = definition.get("interaction")
		if candidate is InteractorProfile:
			return candidate as InteractorProfile
	# A default rather than null: an interactor with no authored profile should
	# still reach as far as everything else does.
	return InteractorProfile.new()


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


static func find_on(node: Node) -> InteractorComponent:
	if node == null:
		return null
	if node is InteractorComponent:
		return node as InteractorComponent
	for component in DefinitionBinder.collect_components(node):
		if component is InteractorComponent:
			return component as InteractorComponent
	return null
