extends FrameworkTestCase
## Covers MissionRuntime and ObjectiveRuntime: counting, sequencing, failure
## and what survives a save.

const AcquiredEvent := preload(
	"res://addons/universal_gameplay/inventory/item_acquired_event.gd"
)
const AreaEvent := preload("res://addons/universal_gameplay/missions/area_event.gd")

var narrative: NarrativeStateService = null
var player: Node3D = null
var bandit: Node3D = null


func before_each() -> void:
	narrative = NarrativeStateService.new()
	add_test_node(narrative)
	player = add_test_node(Node3D.new()) as Node3D
	player.name = "Player"
	bandit = _tagged("Bandit", &"actor.bandit")


func _tagged(entity_name: String, tag: StringName) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = entity_name
	var mark := Perceivable.new()
	mark.name = "Perceivable"
	var tags: Array[StringName] = [tag]
	mark.tags = tags
	entity.add_child(mark)
	return entity


func _runtime(definition: MissionDefinition) -> MissionRuntime:
	return MissionRuntime.create(definition, player, narrative)


func _kill(victim: Node, killer: Node = null) -> ActorDiedEvent:
	return ActorDiedEvent.create(
		victim, DamageContext.create(10.0, killer if killer != null else player)
	)


func _acquire(item_id: StringName, quantity: int) -> FrameworkEvent:
	var definition := ItemFixtures.stackable(item_id, 99)
	return AcquiredEvent.create(null, ItemInstance.create(definition, quantity), quantity)


# --- Counting -------------------------------------------------------------

func test_a_mission_starts_and_activates_its_objectives() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	assert_ok(runtime.start())
	assert_true(runtime.is_active())
	assert_size(runtime.get_active_objectives(), 1)


func test_a_matching_event_makes_progress() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	runtime.start()

	assert_true(runtime.handle(_kill(bandit)))
	assert_almost_eq(runtime.get_objective(&"objective.kill_bandits").progress, 1.0)
	assert_false(runtime.get_objective(&"objective.kill_bandits").is_complete())


func test_reaching_the_count_completes_the_objective_and_the_mission() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	runtime.start()
	runtime.handle(_kill(bandit))
	runtime.handle(_kill(bandit))

	assert_true(runtime.get_objective(&"objective.kill_bandits").is_complete())
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_an_event_that_does_not_match_changes_nothing() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	runtime.start()

	var guard := _tagged("Guard", &"actor.guard")
	assert_false(runtime.handle(_kill(guard)), "wrong tag")
	assert_false(runtime.handle(_kill(bandit, bandit)), "wrong killer")
	assert_almost_eq(runtime.get_objective(&"objective.kill_bandits").progress, 0.0)


func test_a_count_field_lets_one_event_be_worth_several() -> void:
	# A stack of ten planks arrives as one event worth ten.
	var runtime := _runtime(
		MissionFixtures.mission(&"m", [MissionFixtures.acquire_objective(&"item.plank", 10)])
	)
	runtime.start()
	runtime.handle(_acquire(&"item.plank", 4))
	assert_almost_eq(runtime.get_objective(&"objective.collect").progress, 4.0)
	runtime.handle(_acquire(&"item.plank", 6))
	assert_true(runtime.get_objective(&"objective.collect").is_complete())


func test_progress_never_exceeds_the_target() -> void:
	var runtime := _runtime(
		MissionFixtures.mission(&"m", [MissionFixtures.acquire_objective(&"item.plank", 3)])
	)
	runtime.start()
	runtime.handle(_acquire(&"item.plank", 99))
	assert_almost_eq(runtime.get_objective(&"objective.collect").progress, 3.0)
	assert_almost_eq(runtime.get_objective(&"objective.collect").get_fraction(), 1.0)


func test_a_finished_mission_ignores_further_events() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_false(runtime.handle(_kill(bandit)))


# --- Sequencing -----------------------------------------------------------

func test_parallel_objectives_all_count_at_once() -> void:
	var runtime := _runtime(MissionFixtures.cross_feature_mission())
	runtime.start()
	assert_size(runtime.get_active_objectives(), 3)


func test_a_sequential_mission_counts_one_at_a_time() -> void:
	var runtime := _runtime(
		MissionFixtures.mission(
			&"m",
			[MissionFixtures.kill_objective(1), MissionFixtures.acquire_objective(&"item.plank", 1)],
			true
		)
	)
	runtime.start()
	assert_size(runtime.get_active_objectives(), 1)
	assert_eq(runtime.get_active_objectives()[0].get_id(), &"objective.kill_bandits")

	# The second objective is not counting yet, so its event is ignored.
	assert_false(runtime.handle(_acquire(&"item.plank", 1)))

	runtime.handle(_kill(bandit))
	assert_eq(runtime.get_active_objectives()[0].get_id(), &"objective.collect")
	assert_true(runtime.handle(_acquire(&"item.plank", 1)))
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_hidden_objectives_stay_out_of_a_tracker_until_they_are_active() -> void:
	var second := MissionFixtures.acquire_objective(&"item.plank", 1)
	second.hidden = true
	var runtime := _runtime(
		MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1), second], true)
	)
	runtime.start()
	assert_size(runtime.get_visible_objectives(), 1)
	runtime.handle(_kill(bandit))
	assert_size(runtime.get_visible_objectives(), 2)


# --- Optional and failure -------------------------------------------------

func test_an_optional_objective_does_not_hold_up_completion() -> void:
	var bonus := MissionFixtures.acquire_objective(&"item.plank", 5)
	bonus.optional = true
	var runtime := _runtime(
		MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1), bonus])
	)
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_a_failed_required_objective_fails_the_mission() -> void:
	var escort := _tagged("Escort", &"actor.escort")
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.escort_objective()]))
	runtime.start()

	runtime.handle(_kill(escort, bandit))
	assert_true(runtime.get_objective(&"objective.escort").is_failed())
	assert_eq(runtime.state, MissionRuntime.State.FAILED)


func test_a_failed_optional_objective_does_not() -> void:
	var escort := _tagged("Escort", &"actor.escort")
	var optional_escort := MissionFixtures.escort_objective()
	optional_escort.optional = true
	var runtime := _runtime(
		MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1), optional_escort])
	)
	runtime.start()

	runtime.handle(_kill(escort, bandit))
	assert_true(runtime.get_objective(&"objective.escort").is_failed())
	assert_true(runtime.is_active())

	runtime.handle(_kill(bandit))
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_failure_is_checked_before_progress() -> void:
	# An event that both counts and fails is a contradiction in content, and
	# failing is the safer reading.
	var contradictory := MissionFixtures.kill_objective(2)
	contradictory.failure_event_name = GameplayNames.EVENT_ACTOR_DIED
	var runtime := _runtime(MissionFixtures.mission(&"m", [contradictory]))
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_true(runtime.get_objective(&"objective.kill_bandits").is_failed())


func test_a_mission_can_be_abandoned_and_that_is_not_failure() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	runtime.start()
	assert_ok(runtime.abandon())
	assert_eq(runtime.state, MissionRuntime.State.ABANDONED)
	assert_err(runtime.abandon(), &"mission.finished")


# --- Timed ----------------------------------------------------------------

func test_a_timed_objective_counts_seconds_not_events() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.survive_objective(3.0)]))
	runtime.start()

	assert_false(runtime.handle(_kill(bandit)), "events do not advance a timer")
	runtime.tick(1.0)
	assert_almost_eq(runtime.get_objective(&"objective.survive").progress, 1.0)
	runtime.tick(2.0)
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_a_timer_only_runs_while_its_objective_is_active() -> void:
	var runtime := _runtime(
		MissionFixtures.mission(
			&"m", [MissionFixtures.kill_objective(1), MissionFixtures.survive_objective(3.0)], true
		)
	)
	runtime.start()
	runtime.tick(5.0)
	assert_almost_eq(runtime.get_objective(&"objective.survive").progress, 0.0)


# --- Explicit control -----------------------------------------------------

func test_an_objective_can_be_completed_outright() -> void:
	# What a cutscene or a debug command calls.
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(5)]))
	runtime.start()
	assert_ok(runtime.complete_objective(&"objective.kill_bandits"))
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


func test_completing_an_objective_that_is_not_there_is_refused() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	runtime.start()
	assert_err(runtime.complete_objective(&"objective.nope"), &"mission.no_such_objective")


func test_a_mission_that_does_not_complete_automatically_waits() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)])
	definition.completes_automatically = false
	var runtime := _runtime(definition)
	runtime.start()
	runtime.handle(_kill(bandit))

	assert_true(runtime.is_active())
	assert_ok(runtime.complete())
	assert_eq(runtime.state, MissionRuntime.State.COMPLETED)


# --- Signals --------------------------------------------------------------

func test_progress_and_completion_are_announced() -> void:
	var progressed: Array[ObjectiveRuntime] = []
	var completed: Array[ObjectiveRuntime] = []
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(2)]))
	runtime.objective_progressed.connect(
		func(o: ObjectiveRuntime) -> void: progressed.append(o)
	)
	runtime.objective_completed.connect(
		func(o: ObjectiveRuntime) -> void: completed.append(o)
	)
	runtime.start()
	runtime.handle(_kill(bandit))
	runtime.handle(_kill(bandit))

	assert_size(progressed, 1)
	assert_size(completed, 1)


func test_finishing_is_announced_with_its_state() -> void:
	var states: Array[int] = []
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(1)]))
	runtime.finished.connect(func(state: int) -> void: states.append(state))
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_size(states, 1)
	assert_eq(states[0], MissionRuntime.State.COMPLETED)


# --- Presentation ---------------------------------------------------------

func test_an_objective_describes_itself_with_its_count() -> void:
	var runtime := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(5)]))
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_has(runtime.get_objective(&"objective.kill_bandits").describe(), "1/5")


func test_mission_progress_averages_its_required_objectives() -> void:
	var runtime := _runtime(
		MissionFixtures.mission(
			&"m", [MissionFixtures.kill_objective(2), MissionFixtures.acquire_objective(&"item.plank", 2)]
		)
	)
	runtime.start()
	runtime.handle(_kill(bandit))
	assert_almost_eq(runtime.get_fraction(), 0.25)


# --- Persistence ----------------------------------------------------------

func test_progress_survives_a_save() -> void:
	var definition := MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(5)])
	var runtime := _runtime(definition)
	runtime.start()
	runtime.handle(_kill(bandit))
	runtime.handle(_kill(bandit))
	runtime.locals[&"var.target"] = "the docks"
	var saved := runtime.capture_state()

	var restored := _runtime(definition)
	restored.restore_state(saved)

	assert_eq(restored.state, MissionRuntime.State.ACTIVE)
	assert_almost_eq(restored.get_objective(&"objective.kill_bandits").progress, 2.0)
	assert_eq(restored.locals[&"var.target"], "the docks")


func test_objectives_restore_by_id_not_by_index() -> void:
	# A mission whose objectives were reordered between versions restores what
	# it can rather than putting the wrong progress on the wrong objective.
	var original := MissionFixtures.mission(
		&"m", [MissionFixtures.kill_objective(5), MissionFixtures.acquire_objective(&"item.plank", 5)]
	)
	var runtime := _runtime(original)
	runtime.start()
	runtime.handle(_acquire(&"item.plank", 3))
	var saved := runtime.capture_state()

	var reordered := MissionFixtures.mission(
		&"m", [MissionFixtures.acquire_objective(&"item.plank", 5), MissionFixtures.kill_objective(5)]
	)
	var restored := _runtime(reordered)
	restored.restore_state(saved)

	assert_almost_eq(restored.get_objective(&"objective.collect").progress, 3.0)
	assert_almost_eq(restored.get_objective(&"objective.kill_bandits").progress, 0.0)


func test_an_objective_that_no_longer_exists_is_dropped_rather_than_breaking_the_load() -> void:
	var original := MissionFixtures.mission(
		&"m", [MissionFixtures.kill_objective(5), MissionFixtures.acquire_objective(&"item.plank", 5)]
	)
	var runtime := _runtime(original)
	runtime.start()
	runtime.handle(_kill(bandit))
	var saved := runtime.capture_state()

	var trimmed := _runtime(MissionFixtures.mission(&"m", [MissionFixtures.kill_objective(5)]))
	trimmed.restore_state(saved)
	assert_almost_eq(trimmed.get_objective(&"objective.kill_bandits").progress, 1.0)
	assert_size(trimmed.get_objectives(), 1)
