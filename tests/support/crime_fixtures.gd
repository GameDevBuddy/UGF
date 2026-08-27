class_name CrimeFixtures
extends RefCounted
## Builders for the offences, ladders and witnesses the M15 suites need.


# --- Content --------------------------------------------------------------

static func crime(
	id: StringName = &"crime.assault",
	heat: float = 25.0,
	reputation_cost: float = 10.0,
	requires_witness: bool = true
) -> CrimeDefinition:
	var definition := CrimeDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.heat = heat
	definition.reputation_cost = reputation_cost
	definition.requires_witness = requires_witness
	definition.witness_scale = 0.0
	definition.law_faction = &"faction.police"
	var tags: Array[StringName] = [&"crime.violent"]
	definition.crime_tags = tags
	return definition


static func tier(
	state: StringName, threshold: float, cooldown_delay: float = 0.0
) -> WantedTier:
	var rung := WantedTier.new()
	rung.state = state
	rung.threshold = threshold
	rung.display_name = str(state)
	rung.cooldown_delay = cooldown_delay
	return rung


## A three-rung ladder: suspected at 20, wanted at 50, hunted at 100.
static func heat_profile(decay_per_second: float = 1.0) -> HeatProfile:
	var profile := HeatProfile.new()
	var rungs: Array[WantedTier] = [
		tier(&"state.suspected", 20.0),
		tier(GameplayNames.STATE_WANTED, 50.0),
		tier(&"state.hunted", 100.0),
	]
	profile.tiers = rungs
	profile.decay_per_second = decay_per_second
	return profile


# --- Services -------------------------------------------------------------

static func heat_service(profile: HeatProfile = null) -> HeatService:
	var service := HeatService.new()
	service.name = "HeatService"
	service.configure(profile if profile != null else heat_profile())
	return service


static func factions(ids: Array = [&"faction.police", &"faction.thieves"]) -> FactionService:
	var service := FactionService.new()
	service.name = "FactionService"
	for id in ids:
		var definition := FactionDefinition.new()
		definition.id = id
		definition.display_name = str(id)
		service.register(definition)
	return service


# --- Entities -------------------------------------------------------------

## Somebody the law can name: an identity and optionally a faction.
static func actor(
	entity_name: String = "Player",
	faction: StringName = &"",
	faction_service: FactionService = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName(entity_name.to_lower())
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	if faction != &"":
		var mark := FactionComponent.new()
		mark.name = "FactionComponent"
		mark.faction_override = faction
		mark.service = faction_service
		entity.add_child(mark)
	return entity


## Somebody who will tell.
static func witness(
	entity_name: String = "Bystander",
	service: HeatService = null,
	sight_range: float = 0.0,
	faction: StringName = &"",
	faction_service: FactionService = null
) -> Node3D:
	var entity := actor(entity_name, faction, faction_service)
	var component := WitnessComponent.new()
	component.name = "WitnessComponent"
	component.heat = service
	component.sight_range = sight_range
	component.report_cooldown = 0.0
	entity.add_child(component)
	return entity


## A guard: an AI brain, a faction, and the law hook.
static func guard(
	entity_name: String = "Constable",
	service: HeatService = null,
	faction: StringName = &"faction.police",
	faction_service: FactionService = null
) -> Node3D:
	var entity := actor(entity_name, faction, faction_service)

	var movement := MovementComponent.new()
	movement.name = "MovementComponent"
	movement.auto_tick = false
	entity.add_child(movement)

	var brain := AIControllerComponent.new()
	brain.name = "AIControllerComponent"
	brain.movement = movement
	brain.auto_tick = false
	entity.add_child(brain)

	if faction_service != null:
		var politics := FactionAIAdapter.new()
		politics.name = "FactionAIAdapter"
		politics.controller = brain
		politics.service = faction_service
		entity.add_child(politics)

	var law := CrimeAIAdapter.new()
	law.name = "CrimeAIAdapter"
	law.controller = brain
	law.heat = service
	entity.add_child(law)
	return entity


static func context(
	perpetrator: Node,
	definition: CrimeDefinition,
	victim: Node = null,
	witnesses: Array = []
) -> CrimeContext:
	var built := CrimeContext.create(perpetrator, definition, victim)
	for who in witnesses:
		built.add_witness(who)
	return built


static func assemble(entity: Node, core: Node = null) -> void:
	var entity_context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(entity_context)


static func find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


static func witness_of(entity: Node) -> WitnessComponent:
	return find(entity, WitnessComponent) as WitnessComponent
