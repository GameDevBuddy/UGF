extends FrameworkTestCase
## Covers FactionDefinition and FactionService: relations, reputation,
## attitude and what survives a save.

var factions: FactionService = null


func before_each() -> void:
	factions = FactionFixtures.service()
	add_test_node(factions)


func test_it_registers_under_the_faction_service_id() -> void:
	assert_eq(factions.get_service_id(), GameplayNames.SERVICE_FACTION)


func test_registered_factions_can_be_looked_up() -> void:
	assert_true(factions.has_faction(&"faction.watch"))
	assert_size(factions.get_faction_ids(), 3)
	assert_null(factions.get_definition(&"faction.nobody"))


func test_registering_something_without_an_id_is_refused() -> void:
	assert_err(factions.register(FactionDefinition.new()), &"faction.invalid")
	assert_err(factions.register(null), &"faction.invalid")


# --- Relations ------------------------------------------------------------

func test_authored_relations_are_the_starting_point() -> void:
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.bandits"), -80.0)
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.merchants"), 40.0)


func test_relations_are_directional() -> void:
	# The watch hating bandits does not make bandits hate the watch by the
	# same amount, and a symmetric store could not say that.
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.bandits"), -80.0)
	assert_almost_eq(factions.get_relation(&"faction.bandits", &"faction.watch"), -90.0)


func test_a_faction_likes_itself_unless_content_says_otherwise() -> void:
	# What stops guards shooting each other.
	assert_false(factions.is_hostile(&"faction.watch", &"faction.watch"))
	assert_true(factions.is_friendly(&"faction.watch", &"faction.watch"))


func test_an_unknown_pair_falls_back_to_the_default_standing() -> void:
	assert_almost_eq(factions.get_relation(&"faction.merchants", &"faction.nobody"), 10.0)


func test_an_unregistered_faction_has_no_opinion() -> void:
	assert_almost_eq(factions.get_relation(&"faction.nobody", &"faction.watch"), 0.0)
	assert_eq(
		factions.resolve_attitude(&"faction.nobody", &"faction.watch"),
		AttitudeSolver.Attitude.NEUTRAL
	)


func test_relations_move_and_are_announced() -> void:
	var changes: Array[float] = []
	factions.relation_changed.connect(
		func(_s: StringName, _o: StringName, value: float) -> void: changes.append(value)
	)
	assert_almost_eq(
		factions.modify_relation(&"faction.watch", &"faction.merchants", 10.0), 50.0
	)
	factions.set_relation(&"faction.watch", &"faction.merchants", 50.0)
	assert_size(changes, 1, "setting it to what it already is changes nothing")


func test_relations_are_clamped() -> void:
	factions.modify_relation(&"faction.watch", &"faction.merchants", 1000.0)
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.merchants"), 100.0)
	factions.modify_relation(&"faction.watch", &"faction.merchants", -5000.0)
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.merchants"), -100.0)


# --- Reputation -----------------------------------------------------------

func test_reputation_starts_at_the_factions_default() -> void:
	assert_almost_eq(factions.get_reputation(&"faction.bandits", &"actor.player"), -10.0)
	assert_almost_eq(factions.get_reputation(&"faction.merchants", &"actor.player"), 10.0)


func test_reputation_moves_independently_of_relations() -> void:
	factions.modify_reputation(&"faction.watch", &"actor.player", -60.0)
	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), -60.0)
	assert_almost_eq(
		factions.get_relation(&"faction.watch", &"faction.bandits"),
		-80.0,
		0.0001,
		"one actor's crimes are not a change in politics"
	)


func test_reputation_changes_are_announced() -> void:
	var changes: Array[float] = []
	factions.reputation_changed.connect(
		func(_f: StringName, _a: StringName, value: float) -> void: changes.append(value)
	)
	factions.modify_reputation(&"faction.watch", &"actor.player", -20.0)
	assert_size(changes, 1)
	assert_almost_eq(changes[0], -20.0)


func test_a_crime_reaches_the_victims_friends() -> void:
	# Robbing the watch should cost you with the merchants who like them,
	# and having a project write that fan-out by hand is how one faction
	# ends up forgotten.
	factions.propagate_reputation(&"faction.watch", &"actor.player", -40.0)

	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), -40.0)
	assert_true(
		factions.get_reputation(&"faction.merchants", &"actor.player") < 10.0,
		"the merchants like the watch, so they mind"
	)


func test_a_faction_that_does_not_care_shrugs() -> void:
	var loners := FactionFixtures.faction(&"faction.loners", 0.0)
	factions.register(loners)
	factions.propagate_reputation(&"faction.watch", &"actor.player", -40.0)
	assert_almost_eq(factions.get_reputation(&"faction.loners", &"actor.player"), 0.0)


func test_a_factions_enemies_are_pleased_by_a_crime_against_it() -> void:
	factions.propagate_reputation(&"faction.watch", &"actor.player", -40.0)
	assert_true(
		factions.get_reputation(&"faction.bandits", &"actor.player") > -10.0,
		"the bandits hate the watch, so they approve"
	)


func test_propagation_can_be_switched_off() -> void:
	factions.propagate_reputation(&"faction.watch", &"actor.player", -40.0, 0.0)
	assert_almost_eq(factions.get_reputation(&"faction.merchants", &"actor.player"), 10.0)


# --- Attitude -------------------------------------------------------------

func test_attitude_comes_from_the_factions_own_bands() -> void:
	assert_eq(
		factions.resolve_attitude(&"faction.watch", &"faction.bandits"),
		AttitudeSolver.Attitude.HOSTILE
	)
	assert_eq(
		factions.resolve_attitude(&"faction.watch", &"faction.merchants"),
		AttitudeSolver.Attitude.FRIENDLY
	)


func test_personal_history_outranks_group_politics() -> void:
	# A bandit clan that hates the watch still tolerates the one guard who
	# has been paying them.
	assert_true(factions.is_hostile(&"faction.bandits", &"faction.watch"))
	factions.set_reputation(&"faction.bandits", &"actor.friendly_guard", 60.0)
	assert_true(factions.is_friendly(&"faction.bandits", &"actor.friendly_guard"))


func test_crossing_a_band_is_announced_and_moving_within_one_is_not() -> void:
	# An adapter should re-evaluate when behaviour changes, not on every
	# point of standing.
	var crossings: Array[int] = []
	factions.attitude_changed.connect(
		func(_f: StringName, _o: StringName, attitude: int) -> void: crossings.append(attitude)
	)

	factions.modify_reputation(&"faction.watch", &"actor.player", -10.0)
	assert_empty(crossings, "still neutral")

	factions.modify_reputation(&"faction.watch", &"actor.player", -10.0)
	assert_size(crossings, 1)
	assert_eq(crossings[0], AttitudeSolver.Attitude.WARY)

	factions.modify_reputation(&"faction.watch", &"actor.player", -40.0)
	assert_size(crossings, 2)
	assert_eq(crossings[1], AttitudeSolver.Attitude.HOSTILE)


# --- Definition validation ------------------------------------------------

func test_a_complete_faction_validates_clean() -> void:
	var result := FactionFixtures.watch().validate()
	assert_true(result.is_valid(), result.format_report())
	assert_false(result.has_warnings(), result.format_report())


func test_mismatched_relation_arrays_are_an_error() -> void:
	var definition := FactionFixtures.watch()
	var values: Array[float] = [1.0]
	definition.relation_values = values
	assert_false(definition.validate().is_valid())


func test_overlapping_bands_are_an_error() -> void:
	var definition := FactionFixtures.watch()
	definition.friendly_above = -80.0
	assert_false(definition.validate().is_valid())


func test_a_faction_hostile_to_itself_is_flagged() -> void:
	var definition := FactionFixtures.faction(
		&"faction.suicidal", 0.0, {&"faction.suicidal": -90.0}
	)
	assert_true(definition.validate().has_warnings())


func test_a_relation_towards_nobody_is_flagged() -> void:
	var definition := FactionFixtures.faction(&"faction.vague", 0.0, {&"": 10.0})
	assert_true(definition.validate().has_warnings())


# --- Persistence ----------------------------------------------------------

func test_live_standing_survives_a_save() -> void:
	factions.modify_relation(&"faction.watch", &"faction.merchants", -20.0)
	factions.modify_reputation(&"faction.watch", &"actor.player", -45.0)
	var saved := factions.capture_state()

	factions.reset()
	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), 0.0)

	factions.restore_state(saved)
	assert_almost_eq(factions.get_relation(&"faction.watch", &"faction.merchants"), 20.0)
	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), -45.0)


func test_definitions_are_content_and_are_not_saved() -> void:
	# They come back from disk, not from the save file.
	assert_false(factions.capture_state().has("definitions"))
	factions.restore_state(factions.capture_state())
	assert_true(factions.has_faction(&"faction.watch"))


func test_resetting_keeps_the_factions_but_forgets_the_history() -> void:
	factions.modify_reputation(&"faction.watch", &"actor.player", -45.0)
	factions.reset()
	assert_true(factions.has_faction(&"faction.watch"))
	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), 0.0)


func test_clearing_forgets_the_factions_too() -> void:
	factions.clear()
	assert_empty(factions.get_faction_ids())
