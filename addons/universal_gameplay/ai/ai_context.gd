class_name AIContext
extends RefCounted
## Everything a brain is given to think with.
##
## The reason a brain is a [Resource] with no node in it: it receives this and
## returns nothing, so deciding what a guard does next is a pure function of
## what the guard knows, and testable as one (rule 33). Assembled by
## [AIControllerComponent], which is also the only thing that acts on the
## decision.
##
## Every capability here may be null. A civilian with no combat component is
## not a broken NPC, it is a civilian (rule 31), and a brain that checks before
## it commands is the difference between a framework and a game.

## The NPC doing the thinking.
var actor: Node = null

## Its controller, for a brain that wants to set a goal rather than a command.
var controller: AIControllerComponent = null

## What it knows. Never null.
var memory: AIMemory = null

## Its senses, for a brain that wants to re-check a sight line before shooting.
var perception: PerceptionComponent = null

## How it moves. Null for something rooted to the spot.
var movement: MovementComponent = null

## How it gets somewhere. Null steers straight at the goal.
var navigation: NavigationAdapter = null

## How it fights. Null for a civilian.
var combat: CombatComponent = null

## How it uses the world. Null for something that opens no doors.
var interactor: InteractorComponent = null

## Its own health, for deciding whether to run. Null never flees on wounds.
var health: HealthComponent = null

## Its own states, for reading and for a brain that wants to advertise.
var semantic_state: SemanticState = null

## The role this NPC is playing.
var role: NPCRoleDefinition = null

## Seconds since the last decision.
var delta: float = 0.0


## Whether this NPC should fight [param target].
##
## Routed through the controller's [HostilityProvider] so a brain never learns
## what a faction is. With none installed the answer is yes, which is what an
## arena shooter wants (rule 31).
func is_hostile(target: Node) -> bool:
	if target == null or target == actor:
		return false
	if controller == null:
		return true
	return controller.get_hostility_provider().is_hostile(actor, target)


func is_ally(target: Node) -> bool:
	if target == null or controller == null:
		return false
	return controller.get_hostility_provider().is_ally(actor, target)


## How threatening [param target] looks once the hostility provider has had
## its say. A brain choosing between two enemies sorts on this.
func get_threat_of(entry: MemoryEntry) -> float:
	if entry == null:
		return 0.0
	var scale := 1.0
	if controller != null:
		scale = controller.get_hostility_provider().get_threat_scale(actor, entry.target)
	return entry.threat * scale


func get_position() -> Vector3:
	if actor is Node3D and (actor as Node3D).is_inside_tree():
		return (actor as Node3D).global_position
	return Vector3.ZERO


## Fraction of health remaining, or one when there is no health component --
## something that cannot be hurt is never hurt enough to run.
func get_health_fraction() -> float:
	return health.get_fraction() if health != null else 1.0


func is_alive() -> bool:
	return health == null or health.is_alive()


func can_move() -> bool:
	return movement != null


func can_fight() -> bool:
	return combat != null and combat.get_attack() != null


## The most pressing hostile thing currently in view, or null.
##
## Filtered by hostility rather than taking whatever the memory ranked first:
## an NPC that charged the most threatening thing it could see would attack
## its own escort.
func get_primary_target() -> MemoryEntry:
	if memory == null:
		return null
	var best: MemoryEntry = null
	var best_threat := -1.0
	for entry in memory.get_visible():
		if not is_hostile(entry.target):
			continue
		var threat := get_threat_of(entry)
		if best == null or threat > best_threat:
			best = entry
			best_threat = threat
	return best


## The freshest hostile thing remembered but not in view, or null.
func get_search_target() -> MemoryEntry:
	if memory == null:
		return null
	var best: MemoryEntry = null
	for entry in memory.get_remembered():
		if not is_hostile(entry.target):
			continue
		if best == null or entry.time_since_seen < best.time_since_seen:
			best = entry
	return best


func _to_string() -> String:
	var who := actor.name if actor != null else "<nobody>"
	var what := role.get_debug_name() if role != null else "<no role>"
	return "AIContext(%s as %s)" % [who, what]
