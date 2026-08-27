class_name WorldFixtures
extends RefCounted
## Builders for the regions, pools and anchors the M14 suites need.


# --- Spawnable content ----------------------------------------------------

## A minimal spawnable scene: a [Node3D] with a [SemanticState] and a binder.
##
## Packed at runtime rather than shipped as a [code].tscn[/code], because the
## addon ships no content of its own (rule 29) — and because an empty
## [code]PackedScene.new()[/code] cannot instantiate, which is how a fixture
## quietly makes half a round trip untestable.
static func spawnable_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Ambient"

	var state := SemanticState.new()
	state.name = "SemanticState"
	root.add_child(state)
	state.owner = root

	var binder := DefinitionBinder.new()
	binder.name = "DefinitionBinder"
	binder.bind_on_ready = false
	root.add_child(binder)
	binder.owner = root

	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## An entity definition something can be spawned from.
static func spawnable(id: StringName = &"npc.pedestrian") -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.scene = spawnable_scene()
	return definition


# --- Regions --------------------------------------------------------------

static func region(
	id: StringName = &"region.docks",
	tags: Array = [&"region.urban"],
	budgets: Dictionary = {&"population.ambient": 10},
	centre: Vector3 = Vector3.ZERO,
	radius: float = 0.0
) -> RegionDefinition:
	var definition := RegionDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.centre = centre
	definition.radius = radius

	var typed_tags: Array[StringName] = []
	typed_tags.assign(tags)
	definition.region_tags = typed_tags

	var categories: Array[StringName] = []
	var limits: Array[int] = []
	for key in budgets:
		categories.append(key)
		limits.append(int(budgets[key]))
	definition.budget_categories = categories
	definition.budget_limits = limits
	return definition


static func world(regions: Array = []) -> WorldStateService:
	var service := WorldStateService.new()
	service.name = "WorldStateService"
	for definition in regions:
		service.register_region(definition)
	return service


# --- Spawning -------------------------------------------------------------

static func entry(
	definition_id: StringName = &"npc.pedestrian",
	weight: float = 1.0,
	minimum: int = 1,
	maximum: int = 1
) -> SpawnEntry:
	var built := SpawnEntry.new()
	built.definition_id = definition_id
	built.weight = weight
	built.minimum = minimum
	built.maximum = maximum
	return built


static func despawn_policy(
	distance: float = 100.0, minimum_lifetime: float = 0.0
) -> DespawnPolicy:
	var policy := DespawnPolicy.new()
	policy.distance = distance
	policy.minimum_lifetime = minimum_lifetime
	policy.maximum_lifetime = 0.0
	policy.protect_visible = false
	return policy


static func pool(
	id: StringName = &"spawn.pedestrians",
	entries: Array = [],
	region_tags: Array = [&"region.urban"],
	category: StringName = &"population.ambient"
) -> SpawnDefinition:
	var definition := SpawnDefinition.new()
	definition.id = id
	definition.display_name = str(id)

	var typed_entries: Array[SpawnEntry] = []
	typed_entries.assign(entries if not entries.is_empty() else [entry()])
	definition.entries = typed_entries

	var typed_tags: Array[StringName] = []
	typed_tags.assign(region_tags)
	definition.region_tags = typed_tags

	definition.category = category
	definition.density = 1.0
	definition.interval = 0.0
	definition.batch_size = 100
	definition.despawn = despawn_policy()
	return definition


static func encounter(
	id: StringName = &"encounter.ambush",
	members: Array = [],
	category: StringName = &"population.encounter"
) -> EncounterDefinition:
	var definition := EncounterDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	var typed: Array[SpawnEntry] = []
	typed.assign(members if not members.is_empty() else [entry(), entry()])
	definition.members = typed
	definition.category = category
	definition.spread = 5.0
	definition.separation = 1.0
	return definition


## An anchor standing at [param position], parented to its own marker.
static func anchor(
	position: Vector3 = Vector3.ZERO,
	region_id: StringName = &"region.docks",
	reuse_delay: float = 0.0
) -> SpawnAnchor:
	var marker := Node3D.new()
	marker.name = "AnchorMarker"
	marker.position = position

	var component := SpawnAnchor.new()
	component.name = "SpawnAnchor"
	component.region_id = region_id
	component.marker = marker
	component.reuse_delay = reuse_delay
	component.scatter = 0.0
	marker.add_child(component)
	return component


static func rng(seed_value: int = 20260827) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


# --- Entities -------------------------------------------------------------

## Something that reports its own region.
static func tracked(
	entity_name: String = "Pedestrian",
	world_service: WorldStateService = null,
	category: StringName = &"population.ambient",
	region_id: StringName = &""
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var tracker := RegionTracker.new()
	tracker.name = "RegionTracker"
	tracker.world = world_service
	tracker.category = category
	tracker.region_id = region_id
	tracker.auto_tick = false
	entity.add_child(tracker)
	return entity


static func assemble(entity: Node, core: Node = null) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
