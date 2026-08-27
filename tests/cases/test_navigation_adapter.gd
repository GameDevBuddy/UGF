extends FrameworkTestCase
## Covers NavigationAdapter: goals, arrival, and steering with no navmesh.

var entity: Node3D = null
var navigation: NavigationAdapter = null


func before_each() -> void:
	entity = add_test_node(Node3D.new()) as Node3D
	navigation = NavigationAdapter.new()
	navigation.arrival_distance = 0.5
	entity.add_child(navigation)
	navigation.initialize(EntityContext.create(entity))


func test_it_starts_with_nowhere_to_be() -> void:
	assert_false(navigation.has_destination())
	assert_false(navigation.is_navigating())
	assert_eq(navigation.get_desired_direction(), Vector3.ZERO)
	assert_true(navigation.is_at_destination(), "nowhere to be is trivially arrived")


func test_setting_a_goal_announces_it() -> void:
	var announced: Array[Vector3] = []
	navigation.destination_set.connect(func(d: Vector3) -> void: announced.append(d))
	navigation.set_destination(Vector3.FORWARD * 10.0)
	assert_size(announced, 1)
	assert_true(navigation.is_navigating())


func test_setting_the_same_goal_twice_does_not_restart_it() -> void:
	# A brain calls this every tick; re-announcing would cancel its own path.
	var announced: Array[Vector3] = []
	navigation.destination_set.connect(func(d: Vector3) -> void: announced.append(d))
	navigation.set_destination(Vector3.FORWARD * 10.0)
	navigation.set_destination(Vector3.FORWARD * 10.0)
	assert_size(announced, 1)


func test_with_no_agent_it_steers_straight_at_the_goal() -> void:
	navigation.set_destination(Vector3.FORWARD * 10.0)
	assert_almost_eq(navigation.get_desired_direction().distance_to(Vector3.FORWARD), 0.0)


func test_steering_is_flattened() -> void:
	# Height is the mover's business. A navigator that pointed upward would
	# have every NPC trying to walk into the sky at a ramp.
	navigation.set_destination(Vector3(0.0, 20.0, -10.0))
	assert_almost_eq(navigation.get_desired_direction().y, 0.0)


func test_arrival_is_announced_once() -> void:
	var reached: Array[Vector3] = []
	navigation.destination_reached.connect(func(d: Vector3) -> void: reached.append(d))

	navigation.set_destination(Vector3.FORWARD * 10.0)
	navigation.tick(0.1)
	assert_empty(reached)

	entity.global_position = Vector3.FORWARD * 10.0
	navigation.tick(0.1)
	navigation.tick(0.1)
	assert_size(reached, 1)


func test_asking_the_way_never_declares_the_journey_over() -> void:
	# Separated on purpose: a query with a side effect is how a goal gets
	# marked reached by something that only wanted to know which way to face.
	var reached: Array[Vector3] = []
	navigation.destination_reached.connect(func(d: Vector3) -> void: reached.append(d))
	navigation.set_destination(Vector3.FORWARD * 10.0)
	entity.global_position = Vector3.FORWARD * 10.0
	navigation.get_desired_direction()
	assert_empty(reached)


func test_an_arrived_navigator_steers_nowhere() -> void:
	navigation.set_destination(Vector3.FORWARD * 10.0)
	entity.global_position = Vector3.FORWARD * 10.0
	navigation.tick(0.1)
	assert_eq(navigation.get_desired_direction(), Vector3.ZERO)


func test_remaining_distance_counts_down() -> void:
	navigation.set_destination(Vector3.FORWARD * 10.0)
	assert_almost_eq(navigation.get_remaining_distance(), 10.0)
	entity.global_position = Vector3.FORWARD * 6.0
	assert_almost_eq(navigation.get_remaining_distance(), 4.0)


func test_clearing_a_goal_stops_the_journey() -> void:
	navigation.set_destination(Vector3.FORWARD * 10.0)
	navigation.clear_destination()
	assert_false(navigation.has_destination())
	assert_eq(navigation.get_desired_direction(), Vector3.ZERO)
	assert_almost_eq(navigation.get_remaining_distance(), 0.0)


func test_a_goal_underfoot_is_reached_immediately() -> void:
	navigation.set_destination(Vector3.ZERO)
	assert_true(navigation.is_at_destination())
