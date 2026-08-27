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


## The most pressing thing currently in view, or null.
func get_primary_target() -> MemoryEntry:
	return memory.get_primary(get_position()) if memory != null else null


## The freshest thing remembered but not in view, or null.
func get_search_target() -> MemoryEntry:
	return memory.get_freshest_memory() if memory != null else null


func _to_string() -> String:
	var who := actor.name if actor != null else "<nobody>"
	var what := role.get_debug_name() if role != null else "<no role>"
	return "AIContext(%s as %s)" % [who, what]
