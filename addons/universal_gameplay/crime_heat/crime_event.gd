extends FrameworkEvent
## Somebody saw something, or somebody's wanted level moved.
##
## Named ids rather than node references, so a mission can have an objective
## that counts "commit three robberies" without Missions loading Crime
## (rule 32).
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

## Who did it.
var actor_id: StringName = &""

## What they did. Blank on a wanted-level change.
var crime_id: StringName = &""

## Whose law. What a mission objective filters on.
var law_faction: StringName = &""

## Tags from the crime definition, so an objective can match a class of offence
## rather than one id.
var crime_tags: Array[StringName] = []

## How many saw it.
var witness_count: int = 0

## The semantic state the actor is now at, blank when no longer wanted. What a
## HUD reads and what "escaped the police" is the absence of.
var wanted_state: StringName = &""

## Heat with that faction after the change.
var heat: float = 0.0

var _name: StringName = &""


static func witnessed(context: CrimeContext) -> FrameworkEvent:
	var event := _make(GameplayNames.EVENT_CRIME_WITNESSED)
	event.actor_id = context.actor_id
	event.crime_id = context.get_crime_id()
	event.law_faction = context.law_faction
	event.witness_count = context.get_witness_count()
	if context.definition != null:
		event.crime_tags = context.definition.crime_tags.duplicate()
	return event


static func wanted(
	p_actor: StringName, p_faction: StringName, p_tier: WantedTier, p_heat: float
) -> FrameworkEvent:
	var event := _make(GameplayNames.EVENT_WANTED_CHANGED)
	event.actor_id = p_actor
	event.law_faction = p_faction
	event.wanted_state = p_tier.state if p_tier != null else &""
	event.heat = p_heat
	return event


static func _make(p_name: StringName) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/crime_heat/crime_event.gd"
	) as GDScript).new()
	event._name = p_name
	return event


func get_event_name() -> StringName:
	return _name


func has_crime_tag(tag: StringName) -> bool:
	return crime_tags.has(tag)


func is_wanted() -> bool:
	return wanted_state != &""
