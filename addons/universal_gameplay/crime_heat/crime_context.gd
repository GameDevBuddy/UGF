class_name CrimeContext
extends RefCounted
## One thing somebody did, and who saw it.
##
## Built by whatever noticed — a witness, a trigger volume, a script — and
## handed to [HeatService]. The same shape [DamageContext] and
## [InteractionContext] have, and for the same reason: a crime crosses module
## boundaries, and none of them should have to depend on another to speak
## about it.

## Who did it.
var perpetrator: Node = null

## Who it was done to. Null for a victimless offence: trespass, speeding.
var victim: Node = null

## What was done.
var definition: CrimeDefinition = null

## Where, for a law response that needs somewhere to go.
var location: Vector3 = Vector3.ZERO

## Which region it happened in, when the world knows.
var region_id: StringName = &""

## Who saw it. Deliberately a list of nodes rather than a count, so an adapter
## can ask a witness what it knows and a stealth game can silence them.
var witnesses: Array[Node] = []

## Whose law was broken. Resolved on report from the definition or the victim.
var law_faction: StringName = &""

## The offender's id in the eyes of the law. Resolved on report.
var actor_id: StringName = &""

## Free-form per-report bag. Deliberately small: anything living here for long
## should become a real field.
var extras: Dictionary = {}


static func create(
	p_perpetrator: Node,
	p_definition: CrimeDefinition,
	p_victim: Node = null
) -> CrimeContext:
	var context := CrimeContext.new()
	context.perpetrator = p_perpetrator
	context.definition = p_definition
	context.victim = p_victim
	if p_perpetrator is Node3D and (p_perpetrator as Node3D).is_inside_tree():
		context.location = (p_perpetrator as Node3D).global_position
	return context


func get_crime_id() -> StringName:
	return definition.id if definition != null else &""


func get_witness_count() -> int:
	var count := 0
	for witness in witnesses:
		if witness != null and is_instance_valid(witness):
			count += 1
	return count


func has_witnesses() -> bool:
	return get_witness_count() > 0


## Adds a witness, ignoring duplicates and the perpetrator.
##
## Ignoring the perpetrator matters more than it looks: a witness component on
## the player would otherwise report the player to the police for the player's
## own crimes, which is funny once.
func add_witness(witness: Node) -> bool:
	if witness == null or witness == perpetrator or witnesses.has(witness):
		return false
	witnesses.append(witness)
	return true


## Whether this crime is reportable at all: it needs a definition, somebody to
## blame, and — unless the offence says otherwise — somebody who saw it.
func is_reportable() -> bool:
	if definition == null or perpetrator == null:
		return false
	return not definition.requires_witness or has_witnesses()


func get_heat() -> float:
	if definition == null:
		return 0.0
	return definition.get_heat_for(get_witness_count())


func _to_string() -> String:
	var who := perpetrator.name if perpetrator != null else "<nobody>"
	return "CrimeContext(%s: %s, %d witness(es))" % [
		who, get_crime_id(), get_witness_count()
	]
