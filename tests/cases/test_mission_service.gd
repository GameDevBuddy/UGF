extends FrameworkTestCase
## Covers MissionService, and holds the M9 exit gate: a mission reacting to
## combat, inventory and dialogue without importing any of them.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var bus: Node = null
var core: Node = null
var narrative: NarrativeStateService = null
var missions: MissionService = null
var player: Node3D = null
var bandit: Node3D = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	narrative = NarrativeStateService.new()
	add_test_node(narrative)

	missions = MissionService.new()
	add_test_node(missions)
	missions.configure(core, bus, narrative)

	player = _actor("Player")
	missions.default_subject = player
	bandit = _actor("Bandit", &"actor.bandit")


func _actor(entity_name: String, tag: StringName = &"") -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = entity_name
	if tag != &"":
		var mark := Perceivable.new()
		mark.name = "Perceivable"
		var tags: Array[StringName] = [tag]
		mark.tags = tags
		entity.add_child(mark)
	return entity


func _kill(victim: Node, killer: Node = null) -> void:
	bus.publish(
		ActorDiedEvent.create(
			victim, DamageContext.create(10.0, killer if killer != null else player)
		)
	)


# --- Starting -------------------------------------------------------------

func test_a_mission_starts_and_is_tracked() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	assert_ok(missions.start(definition))
	assert_true(missions.is_active(&"m"))
	assert_size(missions.get_active(), 1)


func test_starting_the_same_mission_twice_is_refused() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	missions.start(definition)
	assert_err(missions.start(definition), &"mission.already_active")


func test_a_completed_mission_cannot_be_taken_again() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	missions.start(definition)
	_kill(bandit)

	assert_true(missions.has_completed(&"m"))
	assert_err(missions.start(definition), &"mission.already_completed")


func test_a_repeatable_mission_can_be() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	definition.repeatable = true
	missions.start(definition)
	_kill(bandit)
	assert_ok(missions.start(definition))


func test_required_flags_gate_a_mission() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	var required: Array[StringName] = [&"flag.hired"]
	definition.required_flags = required

	assert_err(missions.start(definition), &"mission.unavailable")
	narrative.set_flag(&"flag.hired")
	assert_ok(missions.start(definition))


func test_forbidden_flags_block_a_mission() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	var forbidden: Array[StringName] = [&"flag.town_burned"]
	definition.forbidden_flags = forbidden
	narrative.set_flag(&"flag.town_burned")
	assert_err(missions.start(definition), &"mission.unavailable")


func test_a_mission_chain_waits_for_its_predecessor() -> void:
	var first := MissionFixtures.mission(&"m.first", [MissionFixtures.kill_objective(1)])
	var second := MissionFixtures.mission(&"m.second", [MissionFixtures.kill_objective(1)])
	var prerequisites: Array[StringName] = [&"m.first"]
	second.required_missions = prerequisites

	assert_err(missions.start(second), &"mission.unavailable")
	missions.start(first)
	_kill(bandit)
	assert_ok(missions.start(second))


func test_starting_by_id_resolves_through_the_registry() -> void:
	var definition := MissionFixtures.mission(&"m.registered", [MissionFixtures.kill_objective(1)])
	core.get_definition_registry().register(definition)
	assert_ok(missions.start_by_id(&"m.registered"))


func test_starting_an_unknown_id_is_refused() -> void:
	assert_err(missions.start_by_id(&"m.nonexistent"), &"mission.unknown")


# --- Reacting to the bus --------------------------------------------------

func test_the_service_hears_events_without_being_told_about_them() -> void:
	# One subscription to the firehose, not one per objective.
	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	_kill(bandit)
	assert_almost_eq(
		missions.get_runtime(&"m").get_objective(&"objective.kill_bandits").progress, 1.0
	)


func test_completion_is_announced_and_the_mission_leaves_the_active_list() -> void:
	var completed: Array[MissionRuntime] = []
	missions.mission_completed.connect(func(r: MissionRuntime) -> void: completed.append(r))

	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	_kill(bandit)

	assert_size(completed, 1)
	assert_false(missions.is_active(&"m"))
	assert_true(missions.has_completed(&"m"))


func test_failure_is_announced_and_recorded() -> void:
	var failed: Array[MissionRuntime] = []
	missions.mission_failed.connect(func(r: MissionRuntime) -> void: failed.append(r))

	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.escort_objective()]))
	_kill(_actor("Escort", &"actor.escort"), bandit)

	assert_size(failed, 1)
	assert_true(missions.has_failed(&"m"))


func test_abandoning_removes_it_without_recording_a_failure() -> void:
	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	assert_ok(missions.abandon(&"m"))
	assert_false(missions.is_active(&"m"))
	assert_false(missions.has_failed(&"m"))
	assert_false(missions.has_completed(&"m"))


func test_abandoning_something_not_under_way_is_refused() -> void:
	assert_err(missions.abandon(&"m"), &"mission.not_active")


func test_timed_objectives_advance_on_the_services_tick() -> void:
	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.survive_objective(2.0)]))
	missions.tick(1.0)
	assert_true(missions.is_active(&"m"))
	missions.tick(1.5)
	assert_true(missions.has_completed(&"m"))


# --- Missions publish, so missions can chain ------------------------------

func test_mission_facts_reach_the_bus() -> void:
	var started: Array[FrameworkEvent] = []
	var completed: Array[FrameworkEvent] = []
	var objectives: Array[FrameworkEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_MISSION_STARTED,
		func(e: FrameworkEvent) -> void: started.append(e)
	)
	bus.subscribe(
		GameplayNames.EVENT_MISSION_COMPLETED,
		func(e: FrameworkEvent) -> void: completed.append(e)
	)
	bus.subscribe(
		GameplayNames.EVENT_OBJECTIVE_COMPLETED,
		func(e: FrameworkEvent) -> void: objectives.append(e)
	)

	missions.start(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	_kill(bandit)

	assert_size(started, 1)
	assert_size(objectives, 1)
	assert_size(completed, 1)
	assert_eq(completed[0].mission_id, &"m")
	assert_eq(objectives[0].objective_id, &"objective.kill_bandits")


func test_one_mission_can_be_an_objective_of_another() -> void:
	# The chain, authored entirely as content: the second mission's objective
	# counts the first one's completion event.
	var follow_up := MissionFixtures.objective(
		&"objective.finish_first",
		GameplayNames.EVENT_MISSION_COMPLETED,
		[MissionFixtures.matcher(&"mission_id", &"m.first")]
	)
	missions.start(MissionFixtures.mission(&"m.second", [follow_up]))
	missions.start(MissionFixtures.mission(&"m.first", [MissionFixtures.kill_objective(1)]))

	_kill(bandit)
	assert_true(missions.has_completed(&"m.first"))
	assert_true(missions.has_completed(&"m.second"))


# --- Rewards --------------------------------------------------------------

func test_a_narrative_reward_is_paid_on_completion() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	definition.rewards = MissionFixtures.rewards([MissionFixtures.flag_reward(&"flag.paid")])
	missions.start(definition)

	assert_false(narrative.get_flag(&"flag.paid"))
	_kill(bandit)
	assert_true(narrative.get_flag(&"flag.paid"))


func test_an_item_reward_goes_in_the_subjects_bag() -> void:
	var gold := ItemFixtures.stackable(&"item.gold", 999)
	core.get_definition_registry().register(gold)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container()
	player.add_child(inventory)
	inventory.initialize(EntityContext.create(player))

	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	definition.rewards = MissionFixtures.rewards(
		[MissionFixtures.item_reward(&"item.gold", 250)]
	)
	missions.start(definition)
	_kill(bandit)

	assert_eq(inventory.count(&"item.gold"), 250)


func test_a_reward_that_cannot_be_paid_does_not_undo_the_completion() -> void:
	# A mission that completed should stay completed even if the bag was full.
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	definition.rewards = MissionFixtures.rewards(
		[MissionFixtures.item_reward(&"item.nonexistent", 1)]
	)
	missions.start(definition)
	_kill(bandit)
	assert_true(missions.has_completed(&"m"))


func test_rewards_are_not_paid_for_a_failed_mission() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.escort_objective()])
	definition.rewards = MissionFixtures.rewards([MissionFixtures.flag_reward(&"flag.paid")])
	missions.start(definition)
	_kill(_actor("Escort", &"actor.escort"), bandit)
	assert_false(narrative.get_flag(&"flag.paid"))


# --- Persistence ----------------------------------------------------------

func test_the_quest_log_survives_a_save() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(5)])
	core.get_definition_registry().register(definition)
	missions.start(definition)
	_kill(bandit)
	_kill(bandit)

	var saved := missions.capture_state()
	missions.restore_state({})
	assert_false(missions.is_active(&"m"))

	missions.restore_state(saved)
	assert_true(missions.is_active(&"m"))
	assert_almost_eq(
		missions.get_runtime(&"m").get_objective(&"objective.kill_bandits").progress, 2.0
	)


func test_what_was_already_done_survives_a_save() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	core.get_definition_registry().register(definition)
	missions.start(definition)
	_kill(bandit)

	var saved := missions.capture_state()
	missions.restore_state({})
	missions.restore_state(saved)
	assert_true(missions.has_completed(&"m"))


func test_a_restored_mission_keeps_counting() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)])
	core.get_definition_registry().register(definition)
	missions.start(definition)
	_kill(bandit)
	var saved := missions.capture_state()

	missions.restore_state({})
	missions.restore_state(saved)
	_kill(bandit)
	assert_true(missions.has_completed(&"m"))


func test_a_save_naming_a_mission_that_no_longer_exists_is_dropped() -> void:
	missions.restore_state({"active": [{"id": "m.deleted", "state": 1, "objectives": []}]})
	assert_empty(missions.get_active())


# --- The exit gate --------------------------------------------------------

func test_a_mission_reacts_to_combat_inventory_and_dialogue_without_importing_them() -> void:
	# The M9 exit gate. Three objectives, three source modules, and the only
	# thing Missions knows about any of them is an event name and a field name.
	var runtime_result := missions.start(MissionFixtures.cross_feature_mission())
	assert_ok(runtime_result)
	var runtime: MissionRuntime = runtime_result.payload

	# Combat, through HealthEventAdapter's event.
	_kill(bandit)
	_kill(bandit)
	assert_true(runtime.get_objective(&"objective.kill_bandits").is_complete())

	# Inventory, through InventoryEventAdapter's event. Published by a real
	# adapter on a real container rather than a hand-made event.
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container()
	player.add_child(inventory)
	var adapter := InventoryEventAdapter.new()
	adapter.name = "InventoryEventAdapter"
	adapter.inventory = inventory
	adapter.event_bus = bus
	player.add_child(adapter)
	var context := EntityContext.create(player)
	inventory.initialize(context)
	adapter.initialize(context)

	inventory.add(ItemInstance.create(ItemFixtures.stackable(&"item.plank", 99), 3))
	assert_true(runtime.get_objective(&"objective.collect").is_complete())

	# Dialogue, through DialogueEventAdapter's event. Also a real adapter.
	var npc := add_test_node(Node3D.new())
	var dialogue := DialogueComponent.new()
	dialogue.name = "DialogueComponent"
	dialogue.dialogue_override = DialogueFixtures.branching()
	dialogue.narrative = narrative
	dialogue.suppresses_control = false
	npc.add_child(dialogue)
	var dialogue_adapter := DialogueEventAdapter.new()
	dialogue_adapter.name = "DialogueEventAdapter"
	dialogue_adapter.dialogue = dialogue
	dialogue_adapter.event_bus = bus
	npc.add_child(dialogue_adapter)
	var npc_context := EntityContext.create(npc)
	dialogue.initialize(npc_context)
	dialogue_adapter.initialize(npc_context)

	dialogue.talk(player)
	dialogue.get_runtime().advance()
	dialogue.get_runtime().choose_id(&"choice.accept")

	assert_true(runtime.get_objective(&"objective.accept").is_complete())
	assert_true(missions.has_completed(&"mission.cross_feature"))
