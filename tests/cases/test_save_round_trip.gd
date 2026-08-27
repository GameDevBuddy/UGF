extends FrameworkTestCase
## The M16 exit gate: a full feature-stack round-trip, and an old save
## migrating forward.
##
## [b]This is the test that only gets harder as the framework grows.[/b] Every
## milestone since M1 has added components and services with saved state, and
## none of them told the save platform. If the aggregation is right, all of it
## comes back; if any module quietly owns state nobody captures, this is where
## it shows — which is why the round-trip drives real components rather than
## hand-made dictionaries.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var saves: SaveService = null
var narrative: NarrativeStateService = null
var factions: FactionService = null
var heat: HeatService = null
var world: WorldStateService = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	narrative = NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	factions = CrimeFixtures.factions()
	heat = CrimeFixtures.heat_service()
	world = WorldFixtures.world([
		WorldFixtures.region(&"region.docks", [&"region.urban"], {&"population.ambient": 5})
	])
	for service in [narrative, factions, heat, world]:
		add_test_node(service)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)
	for pair in [
		[GameplayNames.SERVICE_NARRATIVE, narrative],
		[GameplayNames.SERVICE_FACTION, factions],
		[GameplayNames.SERVICE_CRIME, heat],
		[GameplayNames.SERVICE_WORLD_STATE, world],
	]:
		assert_ok(saves.register_service(pair[0], pair[1]))


## A character carrying most of the stack's saved state at once.
func _survivor(entity_name: String = "Survivor") -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName(entity_name.to_lower())
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	var needs := SurvivalFixtures.needs_component(
		[SurvivalFixtures.need(&"need.hunger", 1.0)]
	)
	entity.add_child(needs)

	var effects := StatusEffectComponent.new()
	effects.name = "StatusEffectComponent"
	effects.auto_tick = false
	entity.add_child(effects)
	return entity


func _register(entity: Node) -> Node:
	add_test_node(entity)
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	assert_ok(saves.register_entity(entity))
	return entity


# --- The round trip -------------------------------------------------------

func test_the_whole_feature_stack_survives_a_save() -> void:
	var ration := SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	core.get_definition_registry().register(ration)

	var survivor := _register(_survivor()) as Node3D
	var health := WorldFixtures.find(survivor, HealthComponent) as HealthComponent
	var inventory := WorldFixtures.find(survivor, InventoryComponent) as InventoryComponent
	var needs := WorldFixtures.find(survivor, NeedsComponent) as NeedsComponent
	var state := WorldFixtures.find(survivor, SemanticState) as SemanticState

	# Move every kind of state there is.
	health.set_current(62.0)
	assert_ok(inventory.add(ItemInstance.create(ration, 3)))
	needs.set_value(&"need.hunger", 18.0)
	state.set_state(&"state.exhausted", true)
	survivor.global_position = Vector3(12.0, 0.0, -7.0)

	narrative.set_flag(&"flag.act_two", true)
	narrative.set_counter(&"counter.bandits", 4)
	factions.set_reputation(&"faction.police", &"survivor", -30.0)
	heat.add_heat(&"survivor", &"faction.police", 60.0)
	world.set_entity_region(survivor, &"region.docks", &"population.ambient")

	assert_ok(saves.save(&"slot_1"))

	# Wipe every service and the entity's state, exactly as quitting would.
	narrative.reset()
	factions.reset()
	heat.clear()
	health.set_current(100.0)
	inventory.clear()
	needs.refill_all()
	state.clear_states()
	survivor.global_position = Vector3.ZERO
	assert_false(narrative.get_flag(&"flag.act_two"), "the world is genuinely wiped")

	assert_ok(saves.load_slot(&"slot_1"))

	assert_almost_eq(health.get_current(), 62.0, 0.001, "health")
	assert_eq(inventory.count(&"item.ration"), 3, "inventory")
	assert_almost_eq(needs.get_value(&"need.hunger"), 18.0, 0.001, "needs")
	assert_true(state.has_state(&"state.exhausted"), "semantic state")
	assert_almost_eq(survivor.global_position.x, 12.0, 0.001, "transform")
	assert_true(narrative.get_flag(&"flag.act_two"), "narrative flags")
	assert_eq(narrative.get_counter(&"counter.bandits"), 4, "narrative counters")
	assert_almost_eq(factions.get_reputation(&"faction.police", &"survivor"), -30.0, 0.001, "reputation")
	assert_almost_eq(heat.get_heat(&"survivor", &"faction.police"), 60.0, 0.001, "heat")
	assert_true(heat.is_wanted(&"survivor", &"faction.police"), "and still wanted")


func test_the_save_platform_needed_no_knowledge_of_any_of_it() -> void:
	# The structural claim behind the round-trip. Fourteen milestones have
	# added saved state and this file names none of them.
	var source := FileAccess.get_file_as_string(
		"res://addons/universal_gameplay/persistence/save_service.gd"
	)
	assert_true(source.length() > 0)
	for name in [
		"InventoryComponent", "HealthComponent", "NeedsComponent", "SeatComponent",
		"NarrativeStateService", "FactionService", "HeatService", "WorldStateService",
		"MissionService", "VehicleComponent",
	]:
		assert_false(source.contains(name), "SaveService names %s" % name)


func test_a_save_round_trips_through_plain_data() -> void:
	# No nodes, no resources, no scene graph. A save that referenced live
	# objects would only load back into the session that wrote it.
	var survivor := _register(_survivor()) as Node3D
	survivor.global_position = Vector3(3.0, 0.0, 4.0)
	narrative.set_flag(&"flag.tested", true)

	var captured := saves.capture()
	var round_tripped := SaveGame.from_dictionary(captured.to_dictionary())

	assert_eq(round_tripped.get_entity_count(), 1)
	assert_true(round_tripped.has_entity(&"survivor"))
	assert_eq(
		round_tripped.get_service_state(GameplayNames.SERVICE_NARRATIVE),
		captured.get_service_state(GameplayNames.SERVICE_NARRATIVE)
	)


func test_a_second_world_can_be_loaded_into_from_the_same_save() -> void:
	# The real shape of loading: the entities are rebuilt, not the ones that
	# were saved. If restore depended on object identity this would fail.
	var original := _register(_survivor()) as Node3D
	(WorldFixtures.find(original, HealthComponent) as HealthComponent).set_current(41.0)
	narrative.set_flag(&"flag.act_two", true)
	assert_ok(saves.save(&"slot_1"))

	var other := SaveService.new()
	other.name = "OtherSaveService"
	add_test_node(other)
	other.configure(saves.backend, core)

	var other_narrative := NarrativeStateService.new()
	other_narrative.name = "OtherNarrative"
	add_test_node(other_narrative)
	other.register_service(GameplayNames.SERVICE_NARRATIVE, other_narrative)

	var rebuilt := _survivor("Survivor")
	add_test_node(rebuilt)
	var context := EntityContext.create(rebuilt, null, core)
	for component in DefinitionBinder.collect_components(rebuilt):
		component.initialize(context)
	other.register_entity(rebuilt)

	assert_ok(other.load_slot(&"slot_1"))
	assert_almost_eq(
		(WorldFixtures.find(rebuilt, HealthComponent) as HealthComponent).get_current(), 41.0
	)
	assert_true(other_narrative.get_flag(&"flag.act_two"))


# --- Missing modules ------------------------------------------------------

func test_a_save_holding_state_for_a_missing_module_still_loads() -> void:
	# Removing an optional module must not make existing saves unloadable.
	narrative.set_flag(&"flag.act_two", true)
	heat.add_heat(&"somebody", &"faction.police", 40.0)
	assert_ok(saves.save(&"slot_1"))

	saves.unregister_service(GameplayNames.SERVICE_CRIME)
	narrative.reset()

	var read := saves.read_save(&"slot_1")
	assert_ok(read)
	var issues := saves.apply(read.payload)
	assert_false(issues.has_errors(), "an absent module is information, not an error")
	assert_true(narrative.get_flag(&"flag.act_two"), "and the rest still loads")


func test_a_save_naming_an_entity_that_is_not_here_still_loads() -> void:
	_register(_survivor())
	narrative.set_flag(&"flag.act_two", true)
	assert_ok(saves.save(&"slot_1"))

	saves.clear_registrations()
	saves.register_service(GameplayNames.SERVICE_NARRATIVE, narrative)
	narrative.reset()

	var read := saves.read_save(&"slot_1")
	assert_ok(read)
	assert_false(saves.apply(read.payload).has_errors())
	assert_true(narrative.get_flag(&"flag.act_two"))


# --- Migration ------------------------------------------------------------

class RenameFlagMigration:
	extends SaveMigration

	func _init() -> void:
		from_version = 1
		to_version = 2
		description = "Renames flag.old to flag.new in narrative state."

	func migrate(data: Dictionary) -> Dictionary:
		var services: Dictionary = data.get("services", {})
		var state: Dictionary = services.get(
			String(GameplayNames.SERVICE_NARRATIVE), {}
		)
		var flags: Dictionary = state.get("flags", {})
		if flags.has("flag.old"):
			flags["flag.new"] = flags["flag.old"]
			flags.erase("flag.old")
		return data


func test_an_old_save_migrates_forward() -> void:
	# The other half of the exit gate. A save written by an older build climbs
	# the ladder one rung at a time and arrives usable.
	var ladder := MigrationRegistry.new()
	assert_ok(ladder.register(RenameFlagMigration.new()))
	saves.migrations = ladder

	# A schema-1 save from a build that called the flag something else.
	var old_save := {
		"framework_version": "0.0.9",
		"schema_version": 1,
		"saved_at": 0,
		"playtime": 120.0,
		"profile": {"name": "Old Player"},
		"services": {
			String(GameplayNames.SERVICE_NARRATIVE): {
				"flags": {"flag.old": true}, "variables": {}, "counters": {},
				"relationships": {},
			},
		},
		"entities": [],
	}
	assert_ok(
		saves.backend.write(
			&"slot_old", old_save, SaveSlot.create(&"slot_old", "Old").to_dictionary()
		)
	)

	var steps: Array = []
	saves.migrated.connect(
		func(_slot: StringName, from: int, to: int) -> void: steps.append([from, to])
	)

	# The running build is at schema 1, so force a higher target to exercise
	# the ladder rather than hard-coding a version bump into the test.
	var climbed := ladder.migrate(old_save, 1, 2)
	assert_ok(climbed)
	var upgraded: Dictionary = climbed.payload
	var flags: Dictionary = (
		upgraded["services"][String(GameplayNames.SERVICE_NARRATIVE)]["flags"]
	)
	assert_true(flags.has("flag.new"), "the flag was renamed")
	assert_false(flags.has("flag.old"), "and the old one is gone")
	assert_eq(int(upgraded["schema_version"]), 2, "and the version moved with it")


func test_a_migrated_save_loads_into_the_live_world() -> void:
	var ladder := MigrationRegistry.new()
	assert_ok(ladder.register(RenameFlagMigration.new()))

	var old_save := {
		"schema_version": 1,
		"services": {
			String(GameplayNames.SERVICE_NARRATIVE): {
				"flags": {"flag.old": true}, "variables": {}, "counters": {},
				"relationships": {},
			},
		},
		"entities": [],
	}
	var climbed := ladder.migrate(old_save, 1, 2)
	assert_ok(climbed)

	var game := SaveGame.from_dictionary(climbed.payload)
	assert_false(saves.apply(game).has_errors())
	assert_true(narrative.get_flag(&"flag.new"))
	assert_false(narrative.get_flag(&"flag.old"))


func test_the_original_save_is_never_mutated_by_a_failed_migration() -> void:
	# A retry after fixing the ladder must start from what was on disk, not
	# from something half-converted.
	var ladder := MigrationRegistry.new()
	var original := {"schema_version": 1, "services": {}, "entities": []}
	var climbed := ladder.migrate(original, 1, 3)
	assert_err(climbed, &"migration.missing_step")
	assert_eq(int(original["schema_version"]), 1)


func test_a_save_from_the_future_is_refused_rather_than_half_loaded() -> void:
	# A player who downgraded should be told, not silently given a broken
	# world.
	var future := {
		"schema_version": FrameworkVersion.SAVE_SCHEMA + 5,
		"services": {},
		"entities": [],
	}
	assert_ok(
		saves.backend.write(
			&"slot_future", future, SaveSlot.create(&"slot_future").to_dictionary()
		)
	)
	assert_err(saves.read_save(&"slot_future"), &"save.from_the_future")


func test_a_save_needing_a_missing_rung_is_refused_whole() -> void:
	var old_save := {"schema_version": 0, "services": {}, "entities": []}
	assert_ok(
		saves.backend.write(
			&"slot_ancient", old_save, SaveSlot.create(&"slot_ancient").to_dictionary()
		)
	)
	# Schema 0 with no migration registered from 0.
	assert_true(saves.read_save(&"slot_ancient").is_err())
	assert_false(narrative.get_flag(&"flag.anything"), "and nothing was applied")
