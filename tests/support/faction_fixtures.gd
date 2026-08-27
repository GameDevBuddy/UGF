class_name FactionFixtures
extends RefCounted
## Builders for the town watch, the bandits and the merchants the M10 suites
## need.


static func faction(
	id: StringName,
	default_standing: float = 0.0,
	relations: Dictionary = {}
) -> FactionDefinition:
	var definition := FactionDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.default_standing = default_standing

	var names: Array[StringName] = []
	var values: Array[float] = []
	for other in relations:
		names.append(StringName(other))
		values.append(float(relations[other]))
	definition.relation_factions = names
	definition.relation_values = values
	return definition


## The town watch: hates bandits, likes merchants, neutral to strangers.
static func watch() -> FactionDefinition:
	var definition := faction(
		&"faction.watch",
		0.0,
		{&"faction.bandits": -80.0, &"faction.merchants": 40.0}
	)
	var tags: Array[StringName] = [&"faction.law"]
	definition.role_tags = tags
	return definition


## The bandits: hate the watch, hate merchants a little less.
static func bandits() -> FactionDefinition:
	var definition := faction(
		&"faction.bandits",
		-10.0,
		{&"faction.watch": -90.0, &"faction.merchants": -30.0}
	)
	var tags: Array[StringName] = [&"faction.criminal"]
	definition.role_tags = tags
	return definition


## The merchants: like everyone until given a reason not to.
static func merchants() -> FactionDefinition:
	return faction(
		&"faction.merchants",
		10.0,
		{&"faction.watch": 40.0, &"faction.bandits": -30.0}
	)


static func service(with_definitions: bool = true) -> FactionService:
	var registry := FactionService.new()
	if with_definitions:
		registry.register_all([watch(), bandits(), merchants()])
	return registry


## An entity belonging to a faction, with an optional personal name.
static func member(
	entity_name: String,
	faction_id: StringName,
	registry: FactionService,
	actor_id: StringName = &""
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var mark := FactionComponent.new()
	mark.name = "FactionComponent"
	mark.faction_override = faction_id
	mark.actor_id = actor_id
	mark.service = registry
	entity.add_child(mark)
	return entity


static func assemble(entity: Node, definition: FrameworkDefinition = null) -> void:
	var context := EntityContext.create(entity, definition)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func faction_of(entity: Node) -> FactionComponent:
	return FactionComponent.find_on(entity)
