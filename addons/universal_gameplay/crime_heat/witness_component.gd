class_name WitnessComponent
extends FrameworkComponent
## Somebody who will tell.
##
## [b]It reports through the service, never into it.[/b] The plan is explicit:
## "witness AI reports crime through an event rather than directly modifying
## wanted state". So this builds a [CrimeContext] and hands it over; it never
## touches heat, tiers or reputation, and it could not if it wanted to.
##
## That indirection is what makes a stealth game possible. Silencing a witness
## is deleting one of these, blinding it, or getting out of its range — none of
## which the law has to know about.

## Emitted when this witness reports something.
signal crime_witnessed(context: CrimeContext)
## Emitted when it saw something and did not report it, with why. What a
## stealth HUD shows: "he didn't see you".
signal report_withheld(context: CrimeContext, reason: StringName)

## Where reports go. Resolved from the core when not wired.
@export var heat: HeatService

## How far this witness can see a crime, in metres. Zero sees everything,
## which is right for a security camera and wrong for a pedestrian.
@export_range(0.0, 1000.0, 0.1, "or_greater") var sight_range: float = 25.0

## Optional perception, so a witness that cannot see through walls uses the
## same eyes an AI already has rather than a second, disagreeing set (rule 23).
## Absent, only range applies.
@export var perception: PerceptionComponent

## Semantic states that stop this witness reporting: unconscious, dead,
## blinded, bribed. The whole of "silencing a witness" without Crime learning
## what any of those mean.
@export var silenced_by: Array[StringName] = [
	GameplayNames.STATE_DEAD, GameplayNames.STATE_DOWNED
]

## This entity's own states, read for the silencing check.
@export var semantic_state: SemanticState

## Whether this witness reports crimes against factions other than its own.
## Off is a bystander who only cares when it is personal.
@export var reports_for_others: bool = true

## Seconds before this witness will report again, so one brawl is not fifty
## reports.
@export_range(0.0, 600.0, 0.1, "or_greater") var report_cooldown: float = 3.0

var _cooldown: float = 0.0


func initialize(context: EntityContext) -> void:
	super(context)
	if heat == null:
		heat = _resolve_heat()
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	if perception == null:
		perception = _find(PerceptionComponent) as PerceptionComponent


# --- Queries --------------------------------------------------------------

func is_silenced() -> bool:
	if semantic_state == null:
		return false
	for state in silenced_by:
		if semantic_state.has_state(state):
			return true
	return false


func is_ready() -> bool:
	return not is_silenced() and _cooldown <= 0.0


func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown)


## Where this witness is standing. Public because [CombatCrimeAdapter] gathers
## witnesses by distance and has to be able to ask.
func get_position() -> Vector3:
	var entity := get_entity() as Node3D
	if entity != null and entity.is_inside_tree():
		return entity.global_position
	return Vector3.ZERO


## Whether this witness could see something happen at [param location].
##
## Range first because it is cheap, then perception if there is any. A witness
## with neither sees everything, which is a security camera.
func can_see(location: Vector3, subject: Node = null) -> bool:
	if is_silenced():
		return false
	if sight_range > 0.0 and get_position().distance_to(location) > sight_range:
		return false
	if perception != null and subject != null:
		return perception.can_perceive(subject)
	return true


## Advances the report cooldown. Called by whatever ticks this witness; there
## is no [method Node._process] here on purpose (rule 26).
func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


# --- Reporting ------------------------------------------------------------

## Reports a crime this witness saw.
##
## Returns the service's answer, so a caller learns whether it stuck. A
## withheld report is not a failure of this component — it is a stealth game
## working — which is why it has its own signal.
func report(context: CrimeContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(&"witness.no_crime", "There is nothing to report.")
	if is_silenced():
		report_withheld.emit(context, &"witness.silenced")
		return FrameworkResult.fail(&"witness.silenced", "This witness cannot report.")
	if _cooldown > 0.0:
		report_withheld.emit(context, &"witness.cooling_down")
		return FrameworkResult.fail(&"witness.cooling_down", "They just reported.")
	if context.perpetrator == get_entity():
		# A witness on the player would otherwise report the player to the
		# police for the player's own crimes, which is funny exactly once.
		report_withheld.emit(context, &"witness.self")
		return FrameworkResult.fail(&"witness.self", "They did it themselves.")
	if not can_see(context.location, context.perpetrator):
		report_withheld.emit(context, &"witness.did_not_see")
		return FrameworkResult.fail(&"witness.did_not_see", "They did not see it.")
	if not reports_for_others and not _is_own_faction(context):
		report_withheld.emit(context, &"witness.not_their_business")
		return FrameworkResult.fail(
			&"witness.not_their_business", "It is not their business."
		)
	if heat == null:
		report_withheld.emit(context, &"witness.no_service")
		return FrameworkResult.fail(&"witness.no_service", "There is no law to report to.")

	context.add_witness(get_entity())
	_cooldown = report_cooldown
	crime_witnessed.emit(context)
	return heat.report(context)


## Builds a context and reports it, for a caller that has a perpetrator and a
## crime and nothing else.
func witness(perpetrator: Node, definition: CrimeDefinition, victim: Node = null) -> FrameworkResult:
	return report(CrimeContext.create(perpetrator, definition, victim))


# --- Internals ------------------------------------------------------------

func _is_own_faction(context: CrimeContext) -> bool:
	var mine := _own_faction()
	if mine == &"":
		return false
	if context.law_faction != &"":
		return context.law_faction == mine
	if context.definition != null and context.definition.law_faction != &"":
		return context.definition.law_faction == mine
	return _faction_of(context.victim) == mine


func _own_faction() -> StringName:
	return _faction_of(get_entity())


## Duck-typed, so a witness works with Factions uninstalled (rule 9, rule 31).
func _faction_of(node: Node) -> StringName:
	if node == null:
		return &""
	for component in DefinitionBinder.collect_components(node):
		if component.has_method("get_faction"):
			var faction: Variant = component.call("get_faction")
			if faction is StringName and faction != &"":
				return faction
	return &""


func _resolve_heat() -> HeatService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_CRIME) as HeatService


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
