extends FrameworkTestCase
## Covers the three delivery strategies against a fake world.
##
## The reason a [HitProvider] exists: a sword's arc, a shotgun's pellets and a
## bullet stopped by a wall are all decidable here, with no physics frame.

var provider: FakeHitProvider = null
var attacker: Node3D = null


func before_each() -> void:
	provider = FakeHitProvider.new()
	provider.wall = add_test_node(Node.new())
	attacker = add_test_node(Node3D.new()) as Node3D


func _target(position: Vector3, target_name: String = "Target") -> Node3D:
	var node := add_test_node(Node3D.new()) as Node3D
	node.name = target_name
	node.global_position = position
	provider.targets.append(node)
	return node


func _context(
	delivery: AttackDelivery,
	direction: Vector3 = Vector3.FORWARD,
	origin: Vector3 = Vector3.ZERO
) -> AttackContext:
	var definition := CombatFixtures.attack(&"attack.test", 10.0, delivery)
	var context := AttackContext.create(attacker, definition, origin, direction)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	context.rng = rng
	var none: Array[Node] = []
	context.exclude = none
	return context


# --- Melee ----------------------------------------------------------------

func test_a_swing_hits_what_is_in_front_of_it() -> void:
	var bandit := _target(Vector3.FORWARD * 1.0)
	var delivery := CombatFixtures.melee(2.0, 90.0)
	var hits := delivery.resolve(_context(delivery), provider)
	assert_size(hits, 1)
	assert_eq(hits[0].target, bandit)


func test_a_swing_misses_what_is_behind_it() -> void:
	_target(Vector3.BACK * 1.0)
	var delivery := CombatFixtures.melee(2.0, 90.0)
	assert_empty(delivery.resolve(_context(delivery), provider))


func test_a_swing_misses_what_is_out_of_reach() -> void:
	_target(Vector3.FORWARD * 5.0)
	var delivery := CombatFixtures.melee(2.0, 90.0)
	assert_empty(delivery.resolve(_context(delivery), provider))


func test_a_wide_swing_sweeps_several() -> void:
	_target(Vector3.FORWARD * 1.0, "A")
	_target(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(30.0)) * 1.5, "B")
	var delivery := CombatFixtures.melee(2.0, 120.0)
	assert_size(delivery.resolve(_context(delivery), provider), 2)


func test_a_capped_swing_takes_the_nearest() -> void:
	_target(Vector3.FORWARD * 1.8, "Far")
	var near := _target(Vector3.FORWARD * 0.5, "Near")
	var delivery := CombatFixtures.melee(2.0, 120.0, 1)
	var hits := delivery.resolve(_context(delivery), provider)
	assert_size(hits, 1)
	assert_eq(hits[0].target, near)


func test_a_swing_reports_the_distance_it_connected_at() -> void:
	_target(Vector3.FORWARD * 1.25)
	var delivery := CombatFixtures.melee(2.0, 90.0)
	assert_almost_eq(delivery.resolve(_context(delivery), provider)[0].distance, 1.25)


func test_edge_falloff_weakens_a_swing_that_barely_reached() -> void:
	_target(Vector3.FORWARD * 2.0)
	var delivery := CombatFixtures.melee(2.0, 120.0)
	delivery.edge_multiplier = 0.5
	assert_almost_eq(delivery.resolve(_context(delivery), provider)[0].damage_scale, 0.5)


func test_a_swing_excludes_the_attacker() -> void:
	provider.targets.append(attacker)
	var delivery := CombatFixtures.melee(2.0, 360.0)
	var context := _context(delivery)
	var only_attacker: Array[Node] = [attacker]
	context.exclude = only_attacker
	assert_empty(delivery.resolve(context, provider))


func test_a_melee_delivery_reports_its_reach() -> void:
	assert_almost_eq(CombatFixtures.melee(3.5).get_maximum_range(), 3.5)


func test_a_reachless_swing_is_a_content_error() -> void:
	var delivery := CombatFixtures.melee(0.0)
	assert_false(delivery.validate().is_valid())


func test_an_arcless_swing_is_a_content_error() -> void:
	assert_false(CombatFixtures.melee(2.0, 0.0).validate().is_valid())


# --- Hitscan --------------------------------------------------------------

func test_a_shot_hits_what_it_is_aimed_at() -> void:
	var target := _target(Vector3.FORWARD * 20.0)
	var delivery := CombatFixtures.hitscan(100.0)
	var hits := delivery.resolve(_context(delivery), provider)
	assert_size(hits, 1)
	assert_eq(hits[0].target, target)
	assert_almost_eq(hits[0].distance, 20.0)


func test_a_shot_misses_what_it_is_not_aimed_at() -> void:
	_target(Vector3.RIGHT * 20.0)
	var delivery := CombatFixtures.hitscan(100.0)
	assert_empty(delivery.resolve(_context(delivery), provider))


func test_a_shot_stops_short_of_its_range() -> void:
	_target(Vector3.FORWARD * 50.0)
	var delivery := CombatFixtures.hitscan(20.0)
	assert_empty(delivery.resolve(_context(delivery), provider))


func test_a_wall_stops_a_bullet() -> void:
	_target(Vector3.FORWARD * 20.0)
	provider.wall_distance = 10.0
	var delivery := CombatFixtures.hitscan(100.0)
	var hits := delivery.resolve(_context(delivery), provider)
	assert_size(hits, 1)
	assert_eq(hits[0].target, provider.wall)
	assert_false(hits[0].is_damageable())


func test_a_shotgun_fires_one_ray_per_pellet() -> void:
	var delivery := CombatFixtures.hitscan(100.0, 8, 5.0)
	delivery.resolve(_context(delivery), provider)
	assert_eq(provider.ray_calls, 8)


func test_pellets_go_in_different_directions() -> void:
	var delivery := CombatFixtures.hitscan(100.0, 8, 5.0)
	delivery.resolve(_context(delivery), provider)
	assert_ne(provider.ray_directions[0], provider.ray_directions[1])


func test_a_shotgun_can_land_several_pellets_on_one_target() -> void:
	# The point of pellets: eight rays, one body, several hits, each carrying
	# the attack's damage. A shotgun that dealt one hit's worth at point-blank
	# would be a rifle with extra steps.
	_target(Vector3.FORWARD * 3.0)
	provider.target_radius = 2.0
	var delivery := CombatFixtures.hitscan(100.0, 8, 5.0)
	assert_size(delivery.resolve(_context(delivery), provider), 8)


func test_the_weapons_own_spread_widens_the_shot() -> void:
	var delivery := CombatFixtures.hitscan(100.0, 1, 0.0)
	var context := _context(delivery)
	context.spread_degrees = 5.0
	delivery.resolve(context, provider)
	assert_ne(provider.ray_directions[0], Vector3.FORWARD)


func test_range_falloff_scales_the_hit() -> void:
	_target(Vector3.FORWARD * 45.0)
	var delivery := CombatFixtures.hitscan(100.0)
	delivery.falloff_start = 30.0
	delivery.falloff_end = 60.0
	delivery.minimum_multiplier = 0.5
	assert_almost_eq(delivery.resolve(_context(delivery), provider)[0].damage_scale, 0.75)


func test_inverted_falloff_is_a_content_error() -> void:
	var delivery := CombatFixtures.hitscan(100.0)
	delivery.falloff_start = 60.0
	delivery.falloff_end = 30.0
	assert_false(delivery.validate().is_valid())


func test_falloff_past_the_range_is_flagged() -> void:
	var delivery := CombatFixtures.hitscan(50.0)
	delivery.falloff_start = 10.0
	delivery.falloff_end = 80.0
	assert_true(delivery.validate().has_warnings())


func test_a_rangeless_shot_is_a_content_error() -> void:
	assert_false(CombatFixtures.hitscan(0.0).validate().is_valid())


# --- Projectile -----------------------------------------------------------

func test_a_projectile_delivery_resolves_no_immediate_hits() -> void:
	_target(Vector3.FORWARD * 5.0)
	var delivery := CombatFixtures.projectile_delivery()
	var context := _context(delivery)
	context.world = add_test_node(Node3D.new())
	assert_empty(delivery.resolve(context, provider))


func test_a_projectile_delivery_puts_something_in_the_world() -> void:
	var delivery := CombatFixtures.projectile_delivery(3)
	var world := add_test_node(Node3D.new()) as Node3D
	var context := _context(delivery)
	context.world = world
	delivery.resolve(context, provider)
	assert_size(world.get_children(), 3)
	assert_true(world.get_child(0) is Projectile)


func test_a_projectile_is_armed_with_the_attack_it_came_from() -> void:
	var delivery := CombatFixtures.projectile_delivery()
	var world := add_test_node(Node3D.new()) as Node3D
	var context := _context(delivery)
	context.world = world
	delivery.resolve(context, provider)
	var projectile := world.get_child(0) as Projectile
	assert_eq(projectile.get_attack_context(), context)


func test_a_projectile_spawns_ahead_of_the_muzzle() -> void:
	var delivery := CombatFixtures.projectile_delivery()
	delivery.muzzle_offset = 1.5
	var world := add_test_node(Node3D.new()) as Node3D
	var context := _context(delivery, Vector3.FORWARD, Vector3.ZERO)
	context.world = world
	delivery.resolve(context, provider)
	var projectile := world.get_child(0) as Projectile
	assert_almost_eq(projectile.global_position.distance_to(Vector3.ZERO), 1.5)


func test_a_projectile_delivery_with_no_world_spawns_nothing() -> void:
	# Better than spawning into a freed tree, which is what a component being
	# torn down mid-attack would otherwise do.
	var delivery := CombatFixtures.projectile_delivery()
	assert_empty(delivery.resolve(_context(delivery), provider))


func test_a_projectile_delivery_with_no_scene_is_a_content_error() -> void:
	assert_false(ProjectileDelivery.new().validate().is_valid())


func test_speed_can_be_overridden_per_weapon() -> void:
	var delivery := CombatFixtures.projectile_delivery()
	delivery.speed_override = 80.0
	var built := delivery.build(_context(delivery), provider, Vector3.FORWARD)
	assert_almost_eq(built.speed, 80.0)
	built.free()


# --- The base class -------------------------------------------------------

func test_the_base_delivery_reaches_nothing_and_hits_nothing() -> void:
	var delivery := AttackDelivery.new()
	assert_empty(delivery.resolve(_context(delivery), provider))
	assert_almost_eq(delivery.get_maximum_range(), 0.0)
	assert_true(delivery.validate().is_valid())
