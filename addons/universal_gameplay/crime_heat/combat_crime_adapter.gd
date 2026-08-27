class_name CombatCrimeAdapter
extends Node
## Makes killing people illegal, without Combat ever hearing about the law.
##
## [b]This file is the M15 exit gate made concrete.[/b] The obvious design has
## [HealthComponent] or [DamagePipeline] call into a crime service on death —
## and that is the dependency cycle the gate forbids: Combat would depend on
## Crime, Crime depends on Factions, Factions is consumed by AI, and AI issues
## the attacks. Instead this subscribes to [code]actor_died[/code], a fact
## Combat has published since M3 and which it publishes whether or not anybody
## is listening (rule 5, rule 9).
##
## The consequence worth noticing: Combat needed no change at all for this
## milestone. Not one line.
##
## Which death counts as which offence is data. A project maps "killed
## somebody of faction X" to a [CrimeDefinition] and gets murder; leave the map
## empty and killing is legal, which is correct for an arena shooter.

signal death_reported(context: CrimeContext)
signal death_ignored(actor: Node, reason: StringName)

## Where reports go.
@export var heat: HeatService

## The bus to listen to. Left null, the [code]EventBus[/code] autoload.
@export var event_bus: Node

## The offence a killing counts as. Null makes killing legal.
@export var murder: CrimeDefinition

## Offence for killing somebody of a faction the killer is already at war
## with. Null means war is not a crime, which is the usual case.
@export var wartime_murder: CrimeDefinition

## Whether a death needs a witness for this adapter to report it. Off is a
## world where bodies are found; the crime definition's own
## [member CrimeDefinition.requires_witness] still applies downstream.
@export var requires_witness: bool = true

## How far a witness can be and still count, in metres. Only used when this
## adapter gathers witnesses itself.
@export_range(0.0, 1000.0, 0.1, "or_greater") var witness_range: float = 30.0

## Witnesses to consider. Registered rather than discovered: searching the
## scene for anybody nearby is exactly the scan M14 spent a milestone
## avoiding, and a project already knows who its guards are.
var _witnesses: Array[WitnessComponent] = []
var _bus: Node = null


func _ready() -> void:
	set_bus(event_bus if event_bus != null else _find_bus())


func _exit_tree() -> void:
	set_bus(null)


func set_bus(bus: Node) -> void:
	if _bus == bus:
		return
	if _bus != null and _bus.has_method("unsubscribe"):
		_bus.call("unsubscribe", GameplayNames.EVENT_ACTOR_DIED, _on_death)
	_bus = bus
	event_bus = bus
	if _bus != null and _bus.has_method("subscribe"):
		_bus.call("subscribe", GameplayNames.EVENT_ACTOR_DIED, _on_death)


func get_bus() -> Node:
	return _bus


# --- Witnesses ------------------------------------------------------------

func register_witness(witness: WitnessComponent) -> bool:
	if witness == null or _witnesses.has(witness):
		return false
	_witnesses.append(witness)
	return true


func unregister_witness(witness: WitnessComponent) -> bool:
	var index := _witnesses.find(witness)
	if index < 0:
		return false
	_witnesses.remove_at(index)
	return true


func get_witness_count() -> int:
	return _witnesses.size()


## Everybody registered who could see [param location].
func find_witnesses(location: Vector3, subject: Node = null) -> Array[WitnessComponent]:
	var found: Array[WitnessComponent] = []
	for witness in _witnesses:
		if witness == null or not is_instance_valid(witness):
			continue
		if witness.get_entity() == subject:
			continue
		if witness_range > 0.0 and witness.get_position().distance_to(location) > witness_range:
			continue
		if witness.can_see(location, subject):
			found.append(witness)
	return found


# --- Reporting ------------------------------------------------------------

## Turns one death into a crime report, if it is one.
##
## Public and directly callable so a project driving deaths its own way — a
## cutscene, a scripted execution — reaches the same path a bus event does.
func report_death(victim: Node, killer: Node) -> FrameworkResult:
	if heat == null:
		return FrameworkResult.fail(&"crime.no_service", "There is no law to report to.")
	if killer == null:
		death_ignored.emit(victim, &"crime.no_killer")
		return FrameworkResult.fail(&"crime.no_killer", "Nobody is to blame.")
	if killer == victim:
		# A suicide, or an explosion that killed the person who set it. Not a
		# crime against anybody, and charging it would be absurd.
		death_ignored.emit(victim, &"crime.self_inflicted")
		return FrameworkResult.fail(&"crime.self_inflicted", "They did it to themselves.")

	var definition := _definition_for(victim, killer)
	if definition == null:
		death_ignored.emit(victim, &"crime.not_a_crime")
		return FrameworkResult.fail(&"crime.not_a_crime", "Killing that is not illegal.")

	var context := CrimeContext.create(killer, definition, victim)
	if victim is Node3D and (victim as Node3D).is_inside_tree():
		context.location = (victim as Node3D).global_position

	for witness in find_witnesses(context.location, killer):
		context.add_witness(witness.get_entity())
	if requires_witness and not context.has_witnesses():
		death_ignored.emit(victim, &"crime.unwitnessed")
		return FrameworkResult.fail(&"crime.unwitnessed", "Nobody saw it.")

	var reported := heat.report(context)
	if reported.is_ok():
		death_reported.emit(context)
	return reported


# --- Internals ------------------------------------------------------------

func _on_death(event: FrameworkEvent) -> void:
	var actor: Node = event.get("actor") if "actor" in event else null
	var damage: DamageContext = event.get("context") if "context" in event else null
	var killer: Node = damage.instigator if damage != null else null
	report_death(actor, killer)


## Which offence a killing counts as, or null when it is legal.
##
## The wartime case is a distinct definition rather than a discount, so a
## project can make war entirely legal, mildly illegal, or worse than murder
## without any of those being special cases in code.
func _definition_for(victim: Node, killer: Node) -> CrimeDefinition:
	if wartime_murder != null and _at_war(victim, killer):
		return wartime_murder
	return murder


## Duck-typed through [FactionComponent]'s public API, so this file works with
## Factions uninstalled — in which case nobody is at war and every killing is
## plain murder (rule 9, rule 31).
func _at_war(victim: Node, killer: Node) -> bool:
	if victim == null or killer == null:
		return false
	for component in DefinitionBinder.collect_components(killer):
		if component.has_method("get_attitude_to"):
			var attitude: Variant = component.call("get_attitude_to", victim)
			if attitude is int:
				return AttitudeSolver.is_hostile(attitude as AttitudeSolver.Attitude)
	return false


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
