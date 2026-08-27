extends FrameworkTestCase
## Covers Projectile: flight, impact, gravity and giving up.

var provider: FakeHitProvider = null
var world: Node3D = null
var shooter: Node3D = null


func before_each() -> void:
	provider = FakeHitProvider.new()
	provider.wall = add_test_node(Node.new())
	world = add_test_node(Node3D.new()) as Node3D
	shooter = add_test_node(Node3D.new()) as Node3D


func _launch(
	direction: Vector3 = Vector3.FORWARD, speed: float = 10.0
) -> Projectile:
	var projectile := CombatFixtures.projectile_scene().instantiate() as Projectile
	projectile.speed = speed
	world.add_child(projectile)
	var definition := CombatFixtures.attack(&"attack.rocket", 50.0, null)
	var context := AttackContext.create(shooter, definition)
	projectile.launch(context, provider, direction)
	return projectile


func _target(distance: float) -> Node3D:
	var node := add_test_node(Node3D.new()) as Node3D
	node.global_position = Vector3.FORWARD * distance
	provider.targets.append(node)
	return node


func test_a_projectile_travels() -> void:
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.tick(0.5)
	assert_almost_eq(projectile.global_position.z, -5.0)


func test_a_projectile_connects_with_what_is_in_its_path() -> void:
	var target := _target(5.0)
	var projectile := _launch(Vector3.FORWARD, 10.0)
	var hits: Array[CombatHit] = []
	projectile.hit_something.connect(
		func(hit: CombatHit, _c: AttackContext) -> void: hits.append(hit)
	)
	projectile.tick(1.0)
	assert_size(hits, 1)
	assert_eq(hits[0].target, target)
	assert_true(projectile.is_spent())


func test_a_projectile_stops_where_it_connected() -> void:
	_target(5.0)
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.tick(1.0)
	assert_almost_eq(projectile.global_position.z, -5.0)


func test_a_projectile_carries_the_attack_that_fired_it() -> void:
	# Six seconds after the trigger, the kill still belongs to whoever pulled it.
	_target(5.0)
	var projectile := _launch()
	var contexts: Array[AttackContext] = []
	projectile.hit_something.connect(
		func(_hit: CombatHit, context: AttackContext) -> void: contexts.append(context)
	)
	projectile.tick(1.0)
	assert_size(contexts, 1)
	assert_eq(contexts[0].instigator, shooter)


func test_a_projectile_sweeps_rather_than_teleporting_past() -> void:
	# A rocket at 40 m/s covers two thirds of a metre a frame; a thin wall is
	# exactly what an overlap test at the destination would skip straight
	# through.
	_target(1.0)
	var projectile := _launch(Vector3.FORWARD, 100.0)
	var hits: Array[CombatHit] = []
	projectile.hit_something.connect(
		func(hit: CombatHit, _c: AttackContext) -> void: hits.append(hit)
	)
	projectile.tick(1.0)
	assert_size(hits, 1)


func test_a_projectile_gives_up_at_its_range() -> void:
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.max_distance = 5.0
	var expired: Array[int] = []
	projectile.expired.connect(func() -> void: expired.append(1))
	projectile.tick(1.0)
	assert_size(expired, 1)
	assert_true(projectile.is_spent())


func test_a_projectile_gives_up_at_its_lifetime() -> void:
	var projectile := _launch(Vector3.FORWARD, 1.0)
	projectile.max_distance = 0.0
	projectile.lifetime = 0.5
	var expired: Array[int] = []
	projectile.expired.connect(func() -> void: expired.append(1))
	projectile.tick(1.0)
	assert_size(expired, 1)


func test_gravity_pulls_a_projectile_down() -> void:
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.gravity = 10.0
	projectile.tick(0.5)
	assert_true(projectile.global_position.y < 0.0)


func test_a_flat_projectile_stays_level() -> void:
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.tick(0.5)
	assert_almost_eq(projectile.global_position.y, 0.0)


func test_a_spent_projectile_stops_moving() -> void:
	_target(2.0)
	var projectile := _launch(Vector3.FORWARD, 10.0)
	projectile.free_on_hit = false
	projectile.tick(1.0)
	var resting := projectile.global_position
	projectile.tick(1.0)
	assert_almost_eq(projectile.global_position.distance_to(resting), 0.0)


func test_a_projectile_excludes_its_shooter() -> void:
	provider.targets.append(shooter)
	shooter.global_position = Vector3.FORWARD * 1.0
	var projectile := _launch(Vector3.FORWARD, 10.0)
	var hits: Array[CombatHit] = []
	projectile.hit_something.connect(
		func(hit: CombatHit, _c: AttackContext) -> void: hits.append(hit)
	)
	projectile.tick(0.5)
	assert_empty(hits)


func test_a_projectile_with_no_provider_just_flies() -> void:
	var projectile := CombatFixtures.projectile_scene().instantiate() as Projectile
	world.add_child(projectile)
	projectile.launch(null, null, Vector3.FORWARD)
	projectile.tick(0.1)
	assert_false(projectile.is_spent())
