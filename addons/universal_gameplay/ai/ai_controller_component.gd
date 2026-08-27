class_name AIControllerComponent
extends FrameworkComponent
## Drives a character from a brain instead of from a gamepad.
##
## [b]The counterpart to [CharacterController], and deliberately its equal.[/b]
## It calls [method MovementComponent.set_move_direction],
## [method CombatComponent.attack] and
## [method InteractorComponent.begin] -- the same public methods the player's
## controller calls, with no privileged path and nothing an AI has to work
## around (rule 14). Delete this component and add a controller and the NPC is
## the player; do the reverse and the player is an NPC. Nothing else in the
## entity changes, which is what the M2 exit gate promised and what this
## milestone spends.
##
## [b]It decides nothing itself.[/b] The brain decides; this assembles the
## context, holds the per-NPC state a shared brain resource must not, and turns
## decisions into commands.

## Emitted when the brain's reported activity changes.
signal state_changed(state: StringName)
## Emitted when the brain is swapped, including for none.
signal brain_changed(brain: AIBrain)

## Role played regardless of the definition's. What a spawner sets to make one
## civilian in a crowd a pickpocket.
@export var role_override: NPCRoleDefinition

## Brain used regardless of the role's. For a scripted actor or a debug puppet.
@export var brain_override: AIBrain

@export_group("Capabilities")
## Everything the brain is given. Each is found among this entity's own
## components when it is not wired, and each may legitimately be absent.
@export var perception: PerceptionComponent
@export var movement: MovementComponent
@export var navigation: NavigationAdapter
@export var combat: CombatComponent
@export var interactor: InteractorComponent
@export var health: HealthComponent
@export var semantic_state: SemanticState

@export_group("Timing")
## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

## Seconds between decisions. Thinking every frame is the permanent per-frame
## work rule 26 warns about, and no NPC needs to reconsider sixty times a
## second. Movement is still applied every frame; only the decision is paced.
@export_range(0.0, 2.0, 0.01) var think_interval: float = 0.1

@export_group("Territory")
## Metres from a goal that count as arrived, for [method is_near].
@export_range(0.01, 20.0, 0.01) var arrival_distance: float = 1.0

## Per-NPC scratch space for the brain. Shared brain resources must not hold
## state; this is where it goes instead.
var blackboard: Dictionary = {}

var _role: NPCRoleDefinition = null
var _brain: AIBrain = null
var _thinking: AIContext = null
var _state: StringName = &""
var _home: Vector3 = Vector3.ZERO
var _has_home: bool = false
var _rng: RandomNumberGenerator = null
var _since_think: float = 0.0
var _active: bool = true
var _move_goal: Vector3 = Vector3.ZERO
var _moving: bool = false
var _sprinting: bool = false


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	_role = _resolve_role()
	if perception == null:
		perception = _find(PerceptionComponent) as PerceptionComponent
	if movement == null:
		movement = _find(MovementComponent) as MovementComponent
	if navigation == null:
		navigation = _find(NavigationAdapter) as NavigationAdapter
	if combat == null:
		combat = _find(CombatComponent) as CombatComponent
	if interactor == null:
		interactor = _find(InteractorComponent) as InteractorComponent
	if health == null:
		health = _find(HealthComponent) as HealthComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState

	set_role(_resolve_role())
	if not _has_home:
		set_home(get_position())
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- What it is -----------------------------------------------------------

func get_role() -> NPCRoleDefinition:
	return _role


## Changes what this NPC is for. Its perception follows, so making one
## civilian in a crowd a guard is one call rather than two -- an NPC whose
## brain and eyes came from different roles is the kind of half-applied change
## that is very hard to see.
func set_role(role: NPCRoleDefinition) -> void:
	_role = role
	if perception != null and _role != null and _role.perception != null:
		perception.set_profile(_role.perception)
	_adopt(_resolve_brain())


func get_brain() -> AIBrain:
	return _brain


## Swaps the brain. What a project calls to put an NPC into a scripted mode and
## back again without rebuilding it.
func set_brain(brain: AIBrain) -> void:
	_adopt(brain)


## What the brain says it is doing, for debug output and for a project hanging
## barks or animation off it.
func get_ai_state() -> StringName:
	return _state


## Reported by the brain each decision. Mirrored onto semantic state so
## anything watching the entity can see it without knowing about AI at all
## (rule 21).
func set_ai_state(state: StringName) -> void:
	if state == _state:
		return
	_apply_state_tags(_state, false)
	_state = state
	_apply_state_tags(_state, true)
	state_changed.emit(_state)


## Whether this NPC is thinking. Off freezes it in place without destroying
## what it knows: what a cutscene, a stun or a distant unloaded region wants.
func is_active() -> bool:
	return _active


func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if not _active:
		stop_moving()


# --- Territory ------------------------------------------------------------

## Where this NPC considers itself posted. Defaults to where it was assembled.
func get_home() -> Vector3:
	return _home


func set_home(home: Vector3) -> void:
	_home = home
	_has_home = true


## Whether it is close enough to [param point] to call it arrived.
func is_near(point: Vector3, tolerance: float = 0.0) -> bool:
	var allowed := tolerance if tolerance > 0.0 else arrival_distance
	var here := get_position()
	var there := point
	# Flattened: an NPC on a ramp is at the right place, not one metre short.
	here.y = 0.0
	there.y = 0.0
	return here.distance_to(there) <= allowed


func get_position() -> Vector3:
	var entity := get_entity()
	if entity is Node3D and (entity as Node3D).is_inside_tree():
		return (entity as Node3D).global_position
	return Vector3.ZERO


## A point to wander to, inside the role's radius around home.
func pick_wander_goal() -> Vector3:
	var radius := _role.wander_radius if _role != null else 0.0
	if radius <= 0.0:
		return _home
	var rng := get_rng()
	var angle := rng.randf() * TAU
	var distance := radius * sqrt(rng.randf())
	return _home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


## Deterministic randomness. Injected so a test gets the same wander twice and
## a networked game can share the stream.
func get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


# --- Commands the brain issues --------------------------------------------

## Heads for [param goal]. Routed through the navigation adapter when there is
## one and straight at it when there is not.
func move_towards(goal: Vector3, sprinting: bool = false) -> void:
	_move_goal = goal
	_moving = true
	_sprinting = sprinting
	if navigation != null:
		navigation.set_destination(goal)
	_apply_movement()


func stop_moving() -> void:
	if not _moving and movement == null:
		return
	_moving = false
	_sprinting = false
	if navigation != null:
		navigation.clear_destination()
	if movement != null:
		movement.stop()


func is_moving_to_goal() -> bool:
	return _moving


func get_move_goal() -> Vector3:
	return _move_goal


# --- Time -----------------------------------------------------------------

## Applies movement every frame and re-decides on the think interval. Called
## for you when [member auto_tick] is on.
func tick(delta: float) -> void:
	if delta <= 0.0 or not _active:
		return
	if navigation != null:
		navigation.tick(delta)
	_apply_movement()

	_since_think += delta
	if _since_think < think_interval:
		return
	think(_since_think)
	_since_think = 0.0


## Runs one decision immediately. Public so a project can drive AI on its own
## schedule, and so a test can step exactly one thought.
func think(delta: float) -> void:
	if _brain == null:
		return
	_brain.think(_build_context(delta))


## What the brain is given. Named build_ rather than get_ because
## [method FrameworkComponent.get_context] already means the entity context,
## and a component whose two contexts share a name is a trap.
##
## Rebuilt per decision rather than cached, because a component can be added or
## freed between two thoughts.
func build_context(delta: float = 0.0) -> AIContext:
	return _build_context(delta)


# --- Persistence ----------------------------------------------------------
#
# Where it is posted and what it was doing survive a save. What it knows does
# not: a guard that reloads into a search for someone who logged out an hour
# ago is worse than one that starts calm.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {
		"home": [_home.x, _home.y, _home.z],
		"state": String(_state),
		"active": _active,
	}


func restore_state(data: Dictionary) -> void:
	var home: Array = data.get("home", [])
	if home.size() == 3:
		set_home(Vector3(float(home[0]), float(home[1]), float(home[2])))
	set_active(bool(data.get("active", _active)))
	set_ai_state(StringName(data.get("state", "")))
	blackboard.clear()


# --- Internals ------------------------------------------------------------

func _build_context(delta: float) -> AIContext:
	if _thinking == null:
		_thinking = AIContext.new()
	_thinking.actor = get_entity()
	_thinking.controller = self
	_thinking.perception = perception
	_thinking.memory = perception.get_memory() if perception != null else _empty_memory()
	_thinking.movement = movement
	_thinking.navigation = navigation
	_thinking.combat = combat
	_thinking.interactor = interactor
	_thinking.health = health
	_thinking.semantic_state = semantic_state
	_thinking.role = _role
	_thinking.delta = delta
	return _thinking


## A memory nobody writes to, so a brain on an entity with no perception reads
## an empty one rather than checking for null on every line.
func _empty_memory() -> AIMemory:
	if not blackboard.has(&"ai.empty_memory"):
		blackboard[&"ai.empty_memory"] = AIMemory.new()
	return blackboard[&"ai.empty_memory"]


## Re-issues the current movement command. Run every frame rather than only on
## a decision, so an NPC walking to a goal keeps walking between thoughts
## instead of stuttering at the think interval.
func _apply_movement() -> void:
	if movement == null or not _moving:
		return
	var direction := _direction_to_goal()
	if direction.is_zero_approx():
		movement.stop()
		return
	movement.set_move_direction(direction)
	movement.set_sprinting(_sprinting)


func _direction_to_goal() -> Vector3:
	if navigation != null:
		return navigation.get_desired_direction()
	var direction := _move_goal - get_position()
	direction.y = 0.0
	if direction.length() <= arrival_distance:
		return Vector3.ZERO
	return direction.normalized()


func _adopt(brain: AIBrain) -> void:
	if brain == _brain:
		return
	_brain = brain
	blackboard.clear()
	if _brain != null:
		_brain.reset(_build_context(0.0))
	brain_changed.emit(_brain)


func _apply_state_tags(state: StringName, active: bool) -> void:
	if semantic_state == null or state == &"":
		return
	match state:
		GameplayNames.AI_STATE_ENGAGE, GameplayNames.AI_STATE_INVESTIGATE:
			semantic_state.set_state(GameplayNames.STATE_ALERTED, active)
		GameplayNames.AI_STATE_FLEE:
			semantic_state.set_state(GameplayNames.STATE_FLEEING, active)
			semantic_state.set_state(GameplayNames.STATE_ALERTED, active)


func _resolve_role() -> NPCRoleDefinition:
	if role_override != null:
		return role_override
	var definition := get_definition()
	if definition != null and "role" in definition:
		var candidate: Variant = definition.get("role")
		if candidate is NPCRoleDefinition:
			return candidate as NPCRoleDefinition
	return null


func _resolve_brain() -> AIBrain:
	if brain_override != null:
		return brain_override
	return _role.brain if _role != null else null


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
