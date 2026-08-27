class_name RoleBrain
extends AIBrain
## One brain, configured three ways: civilian, guard, combatant.
##
## [b]This is where the M7 exit gate is won.[/b] Three roles that differ only
## in a stance and four numbers is rule 11 doing its job -- content is data, so
## a new kind of NPC is a [code].tres[/code] rather than a script. Three
## near-identical brain classes would have been three places to fix the same
## bug (rule 23).
##
## [b]It holds no state.[/b] One [code]guard_brain.tres[/code] backs forty
## guards, so anything remembered here would be remembered by all of them at
## once (rule 2, rule 16). Per-NPC state lives in
## [member AIControllerComponent.blackboard], which is what that is for.

enum Stance {
	## Never fights. Runs from anything it notices. The civilian.
	PASSIVE,
	## Investigates first and fights only what stays. The guard.
	CAUTIOUS,
	## Closes and attacks on sight. The combatant.
	AGGRESSIVE,
}

const KEY_INVESTIGATE_LEFT: StringName = &"role_brain.investigate_left"
const KEY_WANDER_GOAL: StringName = &"role_brain.wander_goal"
const KEY_WANDER_PAUSE: StringName = &"role_brain.wander_pause"

@export var stance: Stance = Stance.CAUTIOUS

@export_group("Engaging")
## Metres it closes to before attacking. Zero uses the attack's own reach,
## which is the right default and wrong for a sniper that wants to keep away.
@export_range(0.0, 200.0, 0.1, "or_greater") var preferred_range: float = 0.0

## Fraction of the attack's reach it will actually walk into, so an NPC does
## not stand exactly at the edge and miss on the first swing.
@export_range(0.1, 1.0, 0.01) var reach_margin: float = 0.8

## Sprint while closing the distance.
@export var sprints_to_engage: bool = true

@export_group("Investigating")
## Seconds spent at a last known position before giving up on it.
@export_range(0.0, 60.0, 0.1, "or_greater") var investigate_time: float = 4.0

@export_group("Fleeing")
## Runs when health falls below this fraction. Zero never flees on wounds; a
## [constant Stance.PASSIVE] brain still runs from what it notices.
@export_range(0.0, 1.0, 0.01) var flee_health_fraction: float = 0.0

## Metres it tries to put between itself and what it is running from.
@export_range(1.0, 200.0, 0.1, "or_greater") var flee_distance: float = 20.0

@export_group("Idling")
## Seconds it stands still between wander goals.
@export_range(0.0, 60.0, 0.1, "or_greater") var wander_pause: float = 2.0


func think(context: AIContext) -> void:
	if context == null or context.controller == null:
		return
	if not context.is_alive():
		_stop(context)
		context.controller.set_ai_state(GameplayNames.AI_STATE_DEAD)
		return

	var primary := context.get_primary_target()
	if primary != null and _should_flee(context, primary):
		_flee(context, primary)
		return
	if primary != null:
		_engage(context, primary)
		return

	var remembered := context.get_search_target()
	if remembered != null and stance != Stance.PASSIVE:
		_investigate(context, remembered)
		return
	if remembered != null:
		# A civilian that heard something keeps moving away from it rather than
		# walking over to look.
		_flee(context, remembered)
		return

	_idle(context)


func get_state() -> StringName:
	# Deliberately blank. What this brain is doing is per-NPC and lives on the
	# controller; a shared resource cannot answer it for one of forty guards.
	return &""


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if stance == Stance.PASSIVE and flee_health_fraction > 0.0:
		result.add_info(
			&"role_brain.redundant_flee_threshold",
			"A passive brain already flees everything it notices.",
			resource_path,
			"flee_health_fraction"
		)
	if preferred_range > 0.0 and stance == Stance.PASSIVE:
		result.add_warning(
			&"role_brain.passive_with_range",
			"A passive brain never engages, so its preferred range is unused.",
			resource_path,
			"preferred_range"
		)
	return result


# --- Behaviours -----------------------------------------------------------

func _engage(context: AIContext, entry: MemoryEntry) -> void:
	var controller := context.controller
	if stance == Stance.PASSIVE or not context.can_fight():
		# Noticing something it cannot fight is still information: a civilian
		# runs, and a guard with no weapon does the same rather than walking
		# into a fight it cannot have.
		_flee(context, entry)
		return

	controller.set_ai_state(GameplayNames.AI_STATE_ENGAGE)
	var here := context.get_position()
	var there := entry.last_known_position
	var distance := here.distance_to(there)
	var wanted := _engage_distance(context)

	context.combat.aim_at(there)
	if distance > wanted:
		controller.move_towards(there, sprints_to_engage and distance > wanted * 2.0)
		return

	controller.stop_moving()
	if context.combat.can_attack().is_ok():
		context.combat.attack()


func _investigate(context: AIContext, entry: MemoryEntry) -> void:
	var controller := context.controller
	controller.set_ai_state(GameplayNames.AI_STATE_INVESTIGATE)

	var goal := entry.predict_position()
	var remaining: float = controller.blackboard.get(KEY_INVESTIGATE_LEFT, investigate_time)
	if controller.is_near(goal):
		remaining -= context.delta
		controller.stop_moving()
		if remaining <= 0.0:
			# Searched and found nothing. Forgetting is what stops a guard
			# standing on the spot forever.
			context.memory.forget(entry.target)
			controller.blackboard.erase(KEY_INVESTIGATE_LEFT)
			return
	else:
		controller.move_towards(goal, false)
	controller.blackboard[KEY_INVESTIGATE_LEFT] = remaining


func _flee(context: AIContext, entry: MemoryEntry) -> void:
	var controller := context.controller
	controller.set_ai_state(GameplayNames.AI_STATE_FLEE)
	var here := context.get_position()
	var away := here - entry.last_known_position
	away.y = 0.0
	if away.is_zero_approx():
		# Standing exactly on top of the threat: any direction is better than
		# freezing, and a fixed one keeps it deterministic.
		away = Vector3.FORWARD
	controller.move_towards(here + away.normalized() * flee_distance, true)


func _idle(context: AIContext) -> void:
	var controller := context.controller
	controller.blackboard.erase(KEY_INVESTIGATE_LEFT)
	var role := context.role
	if role == null or role.wander_radius <= 0.0 or not context.can_move():
		controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
		controller.stop_moving()
		return

	var pause: float = controller.blackboard.get(KEY_WANDER_PAUSE, 0.0)
	if pause > 0.0:
		controller.blackboard[KEY_WANDER_PAUSE] = pause - context.delta
		controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
		controller.stop_moving()
		return

	var goal: Variant = controller.blackboard.get(KEY_WANDER_GOAL)
	if goal == null or controller.is_near(goal as Vector3):
		controller.blackboard[KEY_WANDER_GOAL] = controller.pick_wander_goal()
		controller.blackboard[KEY_WANDER_PAUSE] = wander_pause
		controller.set_ai_state(GameplayNames.AI_STATE_IDLE)
		controller.stop_moving()
		return

	controller.set_ai_state(GameplayNames.AI_STATE_WANDER)
	controller.move_towards(goal as Vector3, false)


# --- Internals ------------------------------------------------------------

func _should_flee(context: AIContext, _entry: MemoryEntry) -> bool:
	if stance == Stance.PASSIVE:
		return true
	if flee_health_fraction <= 0.0:
		return false
	return context.get_health_fraction() <= flee_health_fraction


## How close it wants to be before attacking: the authored range, or a margin
## inside whatever the equipped attack can actually reach.
func _engage_distance(context: AIContext) -> float:
	if preferred_range > 0.0:
		return preferred_range
	var attack := context.combat.get_attack()
	var reach := attack.get_reach() if attack != null else 0.0
	return maxf(1.0, reach * reach_margin)


func _stop(context: AIContext) -> void:
	if context.controller != null:
		context.controller.stop_moving()
