extends FrameworkTestCase
## Covers PerceptionComponent and Perceivable: what an NPC notices, what it
## does not, and what it stops noticing.

var provider: FakePerceptionProvider = null
var guard: Node3D = null
var perception: PerceptionComponent = null
var intruder: Node3D = null


func before_each() -> void:
	provider = FakePerceptionProvider.new()

	guard = add_test_node(AIFixtures.npc("Guard", Vector3.ZERO, AIFixtures.guard())) as Node3D
	AIFixtures.assemble(guard)
	perception = AIFixtures.perception_of(guard)
	perception.set_provider(provider)

	intruder = add_test_node(AIFixtures.actor("Intruder", Vector3.FORWARD * 5.0)) as Node3D
	AIFixtures.assemble(intruder)
	provider.candidates.append(intruder)


# --- Perceivable ----------------------------------------------------------

func test_a_perceivable_entity_joins_the_group() -> void:
	assert_true(intruder.is_in_group(GameplayNames.GROUP_PERCEIVABLE))


func test_turning_perceivability_off_leaves_the_group() -> void:
	var mark := AIFixtures.perceivable_of(intruder)
	mark.set_perceivable(false)
	assert_false(intruder.is_in_group(GameplayNames.GROUP_PERCEIVABLE))
	mark.set_perceivable(true)
	assert_true(intruder.is_in_group(GameplayNames.GROUP_PERCEIVABLE))


func test_a_concealing_state_halves_visibility() -> void:
	var mark := AIFixtures.perceivable_of(intruder)
	assert_almost_eq(mark.get_visibility(), 1.0)
	AIFixtures.state_of(intruder).add_state(GameplayNames.STATE_CROUCHING)
	assert_almost_eq(mark.get_visibility(), 0.5)


func test_an_imperceptible_entity_has_no_visibility() -> void:
	var mark := AIFixtures.perceivable_of(intruder)
	mark.set_perceivable(false)
	assert_almost_eq(mark.get_visibility(), 0.0)


func test_find_on_locates_the_mark() -> void:
	assert_eq(Perceivable.find_on(intruder), AIFixtures.perceivable_of(intruder))
	assert_null(Perceivable.find_on(add_test_node(Node.new())))


# --- Sight ----------------------------------------------------------------

func test_something_in_front_and_in_range_is_perceived() -> void:
	assert_true(perception.can_perceive(intruder))


func test_something_out_of_range_is_not() -> void:
	intruder.global_position = Vector3.FORWARD * 60.0
	assert_false(perception.can_perceive(intruder))


func test_something_behind_is_not() -> void:
	intruder.global_position = Vector3.BACK * 5.0
	assert_false(perception.can_perceive(intruder))


func test_a_wall_blocks_sight() -> void:
	provider.occluded.append(intruder)
	assert_false(perception.can_perceive(intruder))


func test_line_of_sight_can_be_turned_off_entirely() -> void:
	provider.occluded.append(intruder)
	perception.get_profile().requires_line_of_sight = false
	assert_true(perception.can_perceive(intruder))


func test_crouching_halves_the_distance_it_is_spotted_from() -> void:
	# Stealth as one multiplication rather than a special case inside sight.
	intruder.global_position = Vector3.FORWARD * 15.0
	assert_true(perception.can_perceive(intruder))
	AIFixtures.state_of(intruder).add_state(GameplayNames.STATE_CROUCHING)
	assert_false(perception.can_perceive(intruder))


func test_something_that_is_not_perceivable_is_never_perceived() -> void:
	AIFixtures.perceivable_of(intruder).set_perceivable(false)
	assert_false(perception.can_perceive(intruder))


func test_an_entity_with_no_mark_is_invisible() -> void:
	var scenery := add_test_node(Node3D.new()) as Node3D
	scenery.global_position = Vector3.FORWARD * 2.0
	assert_false(perception.can_perceive(scenery))


func test_nothing_perceives_itself() -> void:
	provider.candidates.append(guard)
	assert_false(perception.can_perceive(guard))


# --- Sweeping -------------------------------------------------------------

func test_a_sweep_records_what_it_saw() -> void:
	perception.sweep(0.2)
	assert_true(perception.get_memory().knows(intruder))
	assert_size(perception.get_memory().get_visible(), 1)


func test_a_sweep_ages_what_it_did_not_see() -> void:
	perception.sweep(0.2)
	intruder.global_position = Vector3.BACK * 40.0
	perception.sweep(0.2)

	assert_empty(perception.get_memory().get_visible())
	assert_size(perception.get_memory().get_remembered(), 1)


func test_a_memory_decays_across_sweeps() -> void:
	perception.sweep(0.2)
	intruder.global_position = Vector3.BACK * 40.0
	for step in 10:
		perception.sweep(1.0)
	assert_false(perception.get_memory().knows(intruder))


func test_noticing_is_announced() -> void:
	var noticed: Array[MemoryEntry] = []
	perception.noticed.connect(func(e: MemoryEntry) -> void: noticed.append(e))
	perception.sweep(0.2)
	assert_size(noticed, 1)
	assert_eq(noticed[0].target, intruder)


func test_losing_and_forgetting_are_announced() -> void:
	var lost: Array[MemoryEntry] = []
	var forgotten: Array[Node] = []
	perception.lost.connect(func(e: MemoryEntry) -> void: lost.append(e))
	perception.forgotten.connect(func(t: Node) -> void: forgotten.append(t))

	perception.sweep(0.2)
	intruder.global_position = Vector3.BACK * 40.0
	perception.sweep(0.2)
	assert_size(lost, 1)

	for step in 10:
		perception.sweep(1.0)
	assert_size(forgotten, 1)


func test_sweeping_costs_one_candidate_query() -> void:
	provider.reset_counters()
	perception.sweep(0.2)
	assert_eq(provider.candidate_calls, 1)


# --- The scan interval ----------------------------------------------------

func test_perception_sweeps_on_an_interval_not_every_frame() -> void:
	perception.get_profile().scan_interval = 0.5
	provider.reset_counters()

	perception.tick(0.2)
	assert_eq(provider.candidate_calls, 0)
	perception.tick(0.2)
	assert_eq(provider.candidate_calls, 0)
	perception.tick(0.2)
	assert_eq(provider.candidate_calls, 1)


func test_a_zero_interval_sweeps_every_tick() -> void:
	perception.get_profile().scan_interval = 0.0
	provider.reset_counters()
	perception.tick(0.05)
	perception.tick(0.05)
	assert_eq(provider.candidate_calls, 2)


# --- Hearing --------------------------------------------------------------

func test_a_noise_within_range_is_heard() -> void:
	assert_true(perception.hear(intruder, Vector3.BACK * 5.0, 1.0))
	var entry := perception.get_memory().get_entry(intruder)
	assert_not_null(entry)
	assert_true(entry.heard)
	assert_eq(entry.last_known_position, Vector3.BACK * 5.0)


func test_a_noise_out_of_range_is_not() -> void:
	assert_false(perception.hear(intruder, Vector3.BACK * 50.0, 1.0))
	assert_true(perception.get_memory().is_empty())


func test_a_louder_noise_carries_further() -> void:
	assert_false(perception.hear(intruder, Vector3.BACK * 20.0, 1.0))
	assert_true(perception.hear(intruder, Vector3.BACK * 20.0, 2.0))


func test_hearing_works_through_a_wall() -> void:
	# Sound is not sight: an intruder behind cover is still audible, which is
	# what makes noise worth making.
	provider.occluded.append(intruder)
	assert_true(perception.hear(intruder, Vector3.BACK * 5.0, 1.0))


func test_nothing_hears_itself() -> void:
	assert_false(perception.hear(guard, Vector3.ZERO, 10.0))


# --- Configuration --------------------------------------------------------

func test_the_profile_comes_from_the_role_on_the_definition() -> void:
	var role := AIFixtures.guard()
	var definition := CharacterDefinition.new()
	definition.id = &"character.guard"
	definition.role = role

	var npc := add_test_node(AIFixtures.npc("Sentry")) as Node3D
	AIFixtures.assemble(npc, definition)
	assert_eq(AIFixtures.perception_of(npc).get_profile(), role.perception)


func test_an_entity_with_no_profile_perceives_nothing() -> void:
	var blind := add_test_node(AIFixtures.npc("Statue")) as Node3D
	AIFixtures.assemble(blind)
	var senses := AIFixtures.perception_of(blind)
	senses.set_provider(provider)
	assert_null(senses.get_profile())
	assert_false(senses.can_perceive(intruder))
	senses.sweep(0.2)
	assert_true(senses.get_memory().is_empty())


func test_the_memory_exists_before_the_first_sweep() -> void:
	var fresh := add_test_node(AIFixtures.npc("Rookie", Vector3.ZERO, AIFixtures.guard())) as Node3D
	assert_not_null(AIFixtures.perception_of(fresh).get_memory())


func test_a_provider_is_built_on_demand_when_none_was_injected() -> void:
	var lone := add_test_node(AIFixtures.npc("Lone", Vector3.ZERO, AIFixtures.guard())) as Node3D
	AIFixtures.assemble(lone)
	assert_not_null(AIFixtures.perception_of(lone).get_provider())
