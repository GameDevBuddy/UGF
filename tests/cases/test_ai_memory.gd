extends FrameworkTestCase
## Covers AIMemory and MemoryEntry: noticing, losing, searching, forgetting.

var memory: AIMemory = null
var intruder: Node = null


func before_each() -> void:
	memory = AIMemory.new()
	intruder = add_test_node(Node3D.new())
	intruder.name = "Intruder"


# --- Seeing ---------------------------------------------------------------

func test_a_new_sighting_creates_a_memory() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	assert_true(memory.knows(intruder))
	assert_eq(memory.size(), 1)


func test_a_notice_time_delays_the_reaction() -> void:
	# The whole of sneaking past a guard: in view is not yet noticed.
	var noticed: Array[MemoryEntry] = []
	memory.target_noticed.connect(func(e: MemoryEntry) -> void: noticed.append(e))

	memory.see(intruder, Vector3.FORWARD, 3.0, 0.2, 0.5)
	assert_empty(noticed)
	assert_empty(memory.get_visible())

	memory.see(intruder, Vector3.FORWARD, 3.0, 0.4, 0.5)
	assert_size(noticed, 1)
	assert_size(memory.get_visible(), 1)


func test_no_notice_time_notices_immediately() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1, 0.0)
	assert_size(memory.get_visible(), 1)


func test_breaking_contact_restarts_the_notice_timer() -> void:
	# Ducking behind a crate and back out should not accumulate towards being
	# spotted; otherwise stealth is a stopwatch rather than a skill.
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.4, 1.0)
	var none: Array[Node] = []
	memory.age(0.1, none, 10.0)
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.4, 1.0)
	assert_empty(memory.get_visible())


func test_a_sighting_records_where_and_how_dangerous() -> void:
	memory.see(intruder, Vector3(1.0, 0.0, 2.0), 7.0, 0.1)
	var entry := memory.get_entry(intruder)
	assert_eq(entry.last_known_position, Vector3(1.0, 0.0, 2.0))
	assert_almost_eq(entry.threat, 7.0)
	assert_true(entry.visible)


# --- Losing and remembering -----------------------------------------------

func test_losing_sight_keeps_the_memory() -> void:
	memory.see(intruder, Vector3.FORWARD * 5.0, 3.0, 0.1)
	var none: Array[Node] = []
	memory.age(1.0, none, 8.0)

	assert_true(memory.knows(intruder))
	assert_empty(memory.get_visible())
	assert_size(memory.get_remembered(), 1)


func test_losing_sight_is_announced_once() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var lost: Array[MemoryEntry] = []
	memory.target_lost.connect(func(e: MemoryEntry) -> void: lost.append(e))
	var none: Array[Node] = []
	memory.age(1.0, none, 8.0)
	memory.age(1.0, none, 8.0)
	assert_size(lost, 1)


func test_a_memory_decays_and_is_forgotten() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var forgotten: Array[Node] = []
	memory.target_forgotten.connect(func(t: Node) -> void: forgotten.append(t))

	var none: Array[Node] = []
	memory.age(4.0, none, 5.0)
	assert_true(memory.knows(intruder))
	memory.age(2.0, none, 5.0)

	assert_false(memory.knows(intruder))
	assert_size(forgotten, 1)


func test_still_being_seen_keeps_a_memory_fresh() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var seen: Array[Node] = [intruder]
	for step in 20:
		memory.see(intruder, Vector3.FORWARD, 3.0, 0.5)
		memory.age(0.5, seen, 2.0)
	assert_true(memory.knows(intruder))


func test_a_position_is_predicted_from_where_it_was_heading() -> void:
	# Why an NPC searches ahead of you rather than where you were standing.
	memory.see(intruder, Vector3.ZERO, 3.0, 1.0)
	memory.see(intruder, Vector3.FORWARD * 2.0, 3.0, 1.0)
	var none: Array[Node] = []
	memory.age(1.0, none, 8.0)

	var predicted := memory.get_entry(intruder).predict_position()
	assert_true(predicted.z < (Vector3.FORWARD * 2.0).z, "should lead the target")


func test_prediction_is_capped_so_a_search_stays_plausible() -> void:
	memory.see(intruder, Vector3.ZERO, 3.0, 1.0)
	memory.see(intruder, Vector3.FORWARD * 5.0, 3.0, 1.0)
	var none: Array[Node] = []
	memory.age(60.0, none, 300.0)

	var entry := memory.get_entry(intruder)
	var lead := entry.last_known_position.distance_to(entry.predict_position(1.5))
	assert_true(lead <= 5.0 * 1.5 + 0.001, "a minute of extrapolation would be across the map")


func test_a_visible_target_is_not_predicted_anywhere() -> void:
	memory.see(intruder, Vector3.ZERO, 3.0, 1.0)
	memory.see(intruder, Vector3.FORWARD * 2.0, 3.0, 1.0)
	var entry := memory.get_entry(intruder)
	assert_eq(entry.predict_position(), Vector3.FORWARD * 2.0)


# --- Hearing --------------------------------------------------------------

func test_a_noise_is_noticed_immediately_and_is_not_a_sighting() -> void:
	var noticed: Array[MemoryEntry] = []
	memory.target_noticed.connect(func(e: MemoryEntry) -> void: noticed.append(e))

	memory.hear(intruder, Vector3.FORWARD * 8.0)
	var entry := memory.get_entry(intruder)
	assert_size(noticed, 1)
	assert_true(entry.noticed)
	assert_true(entry.heard)
	assert_false(entry.visible)
	assert_size(memory.get_remembered(), 1)


func test_a_second_noise_does_not_re_announce() -> void:
	var noticed: Array[MemoryEntry] = []
	memory.target_noticed.connect(func(e: MemoryEntry) -> void: noticed.append(e))
	memory.hear(intruder, Vector3.FORWARD)
	memory.hear(intruder, Vector3.FORWARD * 2.0)
	assert_size(noticed, 1)


# --- Choosing -------------------------------------------------------------

func _second(threat: float, position: Vector3) -> Node:
	var other := add_test_node(Node3D.new())
	other.name = "Other"
	memory.see(other, position, threat, 0.1)
	return other


func test_the_most_dangerous_visible_thing_is_primary() -> void:
	memory.see(intruder, Vector3.FORWARD * 2.0, 1.0, 0.1)
	var dangerous := _second(9.0, Vector3.FORWARD * 20.0)
	assert_eq(memory.get_primary().target, dangerous)


func test_equal_threats_break_on_distance() -> void:
	memory.see(intruder, Vector3.FORWARD * 30.0, 5.0, 0.1)
	var nearer := _second(5.0, Vector3.FORWARD * 2.0)
	assert_eq(memory.get_primary(Vector3.ZERO).target, nearer)


func test_nothing_visible_has_no_primary() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var none: Array[Node] = []
	memory.age(1.0, none, 8.0)
	assert_null(memory.get_primary())


func test_the_freshest_memory_is_what_a_search_uses() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var none: Array[Node] = []
	memory.age(3.0, none, 30.0)
	var recent := _second(3.0, Vector3.RIGHT)
	memory.age(0.5, none, 30.0)
	assert_eq(memory.get_freshest_memory().target, recent)


# --- Housekeeping ---------------------------------------------------------

func test_forgetting_one_target_leaves_the_rest() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	var other := _second(3.0, Vector3.RIGHT)
	memory.forget(intruder)
	assert_false(memory.knows(intruder))
	assert_true(memory.knows(other))


func test_clearing_empties_the_memory() -> void:
	memory.see(intruder, Vector3.FORWARD, 3.0, 0.1)
	_second(3.0, Vector3.RIGHT)
	memory.clear()
	assert_true(memory.is_empty())


func test_a_freed_target_is_dropped_rather_than_kept() -> void:
	var doomed := Node3D.new()
	add_test_node(doomed)
	memory.see(doomed, Vector3.FORWARD, 3.0, 0.1)
	doomed.free()

	var none: Array[Node] = []
	memory.age(0.1, none, 8.0)
	assert_true(memory.is_empty())


func test_seeing_nothing_is_answered_rather_than_crashing() -> void:
	assert_null(memory.see(null, Vector3.ZERO, 1.0, 0.1))
	assert_null(memory.hear(null, Vector3.ZERO))
	assert_null(memory.get_entry(null))
	assert_true(memory.is_empty())
