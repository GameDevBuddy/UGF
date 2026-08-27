extends FrameworkTestCase
## Block, parry, dodge, poise and stagger: Implementation Plan 14's Defense
## line, which M6 did not build.
##
## [b]The seam is the point.[/b] Health has no idea what a parry is and Combat
## has no idea what hit points are. [DamageReceiverComponent] announces an
## incoming blow and offers a scale; [DefenseComponent] decides what that scale
## should be; [DefenseDamageAdapter] is the deletable piece that connects them.
## Remove the adapter and both modules still work -- the defender simply takes
## every blow in full.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


func _profile() -> DefenseProfile:
	var profile := DefenseProfile.new()
	profile.block_reduction = 0.5
	profile.block_arc_degrees = 100.0
	profile.block_stamina_per_damage = 1.0
	profile.guard_break_stagger = 1.0
	profile.parry_window = 0.2
	profile.parry_reduction = 1.0
	profile.parry_stagger = 1.2
	profile.dodge_invulnerable = 0.3
	profile.dodge_duration = 0.6
	profile.dodge_stamina_cost = 20.0
	profile.poise = 0.0
	profile.poise_break_stagger = 0.5
	return profile


## A defender with health, a stamina bar and a guard.
func _defender(
	profile: DefenseProfile = null, stamina: float = 100.0, with_adapter: bool = true
) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Defender"

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	var stamina_stat := StatDefinition.new()
	stamina_stat.id = &"stat.stamina"
	stamina_stat.display_name = "Stamina"
	stamina_stat.default_base = stamina
	stamina_stat.minimum = 0.0
	stamina_stat.depletable = true
	var stats_profile := StatsProfile.new()
	var list: Array[StatDefinition] = [stamina_stat]
	stats_profile.stats = list
	stats.profile_override = stats_profile
	stats.auto_tick = false
	entity.add_child(stats)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)

	var defense := DefenseComponent.new()
	defense.name = "DefenseComponent"
	defense.profile_override = profile if profile != null else _profile()
	defense.auto_tick = false
	entity.add_child(defense)

	if with_adapter:
		var adapter := DefenseDamageAdapter.new()
		adapter.name = "DefenseDamageAdapter"
		entity.add_child(adapter)

	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


func _defense_of(entity: Node) -> DefenseComponent:
	for child in entity.get_children():
		if child is DefenseComponent:
			return child as DefenseComponent
	return null


func _health_of(entity: Node) -> HealthComponent:
	for child in entity.get_children():
		if child is HealthComponent:
			return child as HealthComponent
	return null


func _receiver_of(entity: Node) -> DamageReceiverComponent:
	for child in entity.get_children():
		if child is DamageReceiverComponent:
			return child as DamageReceiverComponent
	return null


func _stats_of(entity: Node) -> StatsComponent:
	for child in entity.get_children():
		if child is StatsComponent:
			return child as StatsComponent
	return null


## An attacker standing in front of the defender, so the block arc covers it.
func _attacker(defender: Node3D, in_front: bool = true) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Attacker"
	# The defender faces -Z by default, so an attacker in front is at -Z.
	entity.global_position = defender.global_position + (
		Vector3(0.0, 0.0, -3.0) if in_front else Vector3(0.0, 0.0, 3.0)
	)
	return entity


func _hit(defender: Node3D, attacker: Node3D, amount: float = 20.0) -> void:
	_receiver_of(defender).receive(DamageContext.create(amount, attacker))


# --- Undefended -----------------------------------------------------------

func test_an_undefended_blow_lands_in_full() -> void:
	var defender := _defender()
	_hit(defender, _attacker(defender), 30.0)
	assert_eq(_health_of(defender).get_current(), 70.0)


# --- Block ----------------------------------------------------------------

func test_a_held_block_halves_the_blow() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	assert_ok(defense.begin_block())
	# Past the parry window, so this is a block rather than a parry.
	defense.tick(0.5)

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 80.0, "Half of forty got through")


func test_blocking_costs_stamina() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.5)

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(
		_stats_of(defender).get_current(&"stat.stamina"),
		80.0,
		"Twenty absorbed at one stamina per point"
	)


func test_a_blow_from_behind_is_not_blocked() -> void:
	# A shield that worked from every angle would make facing irrelevant and
	# blocking strictly better than not blocking.
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.5)

	_hit(defender, _attacker(defender, false), 40.0)

	assert_eq(_health_of(defender).get_current(), 60.0, "It landed in full")


func test_running_out_of_stamina_breaks_the_guard() -> void:
	# The blow lands in full rather than being partly blocked: charging partial
	# stamina for partial mitigation would let a defender block forever at a
	# trickle, which is what the cost exists to prevent.
	var defender := _defender(null, 5.0)
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.5)
	var broken: Array[bool] = []
	defense.guard_broken.connect(func() -> void: broken.append(true))

	_hit(defender, _attacker(defender), 40.0)

	assert_size(broken, 1)
	assert_eq(_health_of(defender).get_current(), 60.0, "The whole blow landed")
	assert_true(defense.is_staggered(), "And it staggered")


func test_a_staggered_defender_cannot_block() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.stagger(1.0)
	assert_err(defense.begin_block(), &"defense.staggered")


# --- Parry ----------------------------------------------------------------

func test_a_blow_inside_the_parry_window_is_nullified() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.1)

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 100.0, "A parry lets nothing through")


func test_the_parry_window_closes() -> void:
	# The difference between a parry and a block is entirely timing, so this is
	# the assertion that proves the window is real rather than always open.
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.25)

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 80.0, "Blocked, not parried")


func test_a_parry_staggers_the_attacker() -> void:
	# The reward. A parry that granted no opening would be a block with harder
	# timing and no payoff.
	var defender := _defender()
	var attacker := _defender(null, 100.0, false)
	attacker.name = "Aggressor"
	attacker.global_position = defender.global_position + Vector3(0.0, 0.0, -3.0)

	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.1)

	_receiver_of(defender).receive(DamageContext.create(40.0, attacker))

	assert_true(
		_defense_of(attacker).is_staggered(),
		"The parry left the attacker wide open and nothing happened"
	)


func test_parrying_something_that_cannot_be_staggered_still_works() -> void:
	# A turret, a trap, a projectile's source. The blow is still nullified; it
	# just does not open anything up.
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.1)

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 100.0)


# --- Dodge ----------------------------------------------------------------

func test_a_dodge_makes_a_blow_miss_entirely() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	assert_ok(defense.dodge())

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 100.0)


func test_the_invulnerable_window_is_shorter_than_the_dodge() -> void:
	# The recovery tail is what stops dodging being spammable, so a dodge that
	# was invulnerable throughout would be strictly better than blocking.
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.dodge()
	defense.tick(0.4)

	assert_true(defense.is_dodging(), "Still rolling")
	assert_false(defense.is_invulnerable(), "But no longer untouchable")

	_hit(defender, _attacker(defender), 40.0)

	assert_eq(_health_of(defender).get_current(), 60.0)


func test_a_dodge_costs_stamina_and_is_refused_without_it() -> void:
	var defender := _defender(null, 5.0)
	assert_err(_defense_of(defender).dodge(), &"defense.exhausted")


func test_a_dodge_ends() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.dodge()
	defense.tick(0.7)
	assert_false(defense.is_dodging())


# --- Poise ----------------------------------------------------------------

func test_with_no_poise_every_hit_staggers() -> void:
	var defender := _defender()
	_hit(defender, _attacker(defender), 5.0)
	assert_true(_defense_of(defender).is_staggered())


func test_poise_absorbs_hits_until_it_breaks() -> void:
	var profile := _profile()
	profile.poise = 50.0
	var defender := _defender(profile)
	var defense := _defense_of(defender)
	var attacker := _attacker(defender)

	_hit(defender, attacker, 20.0)
	assert_false(defense.is_staggered(), "Twenty of fifty")

	_hit(defender, attacker, 20.0)
	assert_false(defense.is_staggered(), "Forty of fifty")

	_hit(defender, attacker, 20.0)
	assert_true(defense.is_staggered(), "Sixty broke it")


func test_blocking_protects_poise_as_well_as_health() -> void:
	# Poise accumulates from what actually got through, which is why the order
	# in mitigate() is not arbitrary.
	var profile := _profile()
	profile.poise = 50.0
	var defender := _defender(profile)
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.5)

	_hit(defender, _attacker(defender), 80.0)

	assert_eq(defense.get_poise_damage(), 40.0, "Half of eighty counted towards poise")
	assert_false(defense.is_staggered())


func test_poise_recovers_after_a_lull() -> void:
	var profile := _profile()
	profile.poise = 50.0
	profile.poise_recovery_delay = 2.0
	var defender := _defender(profile)
	var defense := _defense_of(defender)

	_hit(defender, _attacker(defender), 40.0)
	assert_eq(defense.get_poise_damage(), 40.0)

	defense.tick(2.5)

	assert_eq(defense.get_poise_damage(), 0.0)


func test_a_stagger_expires() -> void:
	var defender := _defender()
	var defense := _defense_of(defender)
	defense.stagger(0.5)
	assert_true(defense.is_staggered())
	defense.tick(0.6)
	assert_false(defense.is_staggered())


func test_being_staggered_sets_the_semantic_state() -> void:
	var defender := _defender()
	_defense_of(defender).stagger(0.5)
	var state: SemanticState = null
	for child in defender.get_children():
		if child is SemanticState:
			state = child as SemanticState
	assert_true(state.has_state(GameplayNames.STATE_STAGGERED))


# --- The seam -------------------------------------------------------------

func test_deleting_the_adapter_leaves_both_modules_working() -> void:
	# Rule 10 stated as a test. Without the adapter the defender still blocks,
	# still dodges, still has health -- the two simply stop talking, and every
	# blow lands in full.
	var defender := _defender(null, 100.0, false)
	var defense := _defense_of(defender)
	defense.begin_block()
	defense.tick(0.5)

	_hit(defender, _attacker(defender), 40.0)

	assert_true(defense.is_blocking(), "The guard is still up")
	assert_eq(_health_of(defender).get_current(), 60.0, "It just did not help")


func test_health_names_nothing_from_combat() -> void:
	# The reason the adapter exists. If Health ever imports a defence type, the
	# two modules are welded together and rule 9 is gone.
	var source := _read_without_comments(
		"res://addons/universal_gameplay/health_damage/damage_receiver_component.gd"
	)
	for forbidden in ["DefenseComponent", "DefenseProfile", "DefenseDamageAdapter"]:
		assert_false(source.contains(forbidden), "damage_receiver names %s" % forbidden)


func test_combat_names_nothing_from_health_in_the_defence_itself() -> void:
	var source := _read_without_comments(
		"res://addons/universal_gameplay/combat/defense_component.gd"
	)
	for forbidden in ["HealthComponent", "apply_damage"]:
		assert_false(source.contains(forbidden), "defense_component names %s" % forbidden)


# --- Content validation ---------------------------------------------------

func test_a_dodge_longer_invulnerable_than_it_lasts_is_rejected() -> void:
	var profile := _profile()
	profile.dodge_invulnerable = 1.0
	profile.dodge_duration = 0.5
	assert_true(profile.validate().has_errors())


func test_a_free_block_warns() -> void:
	var profile := _profile()
	profile.block_stamina_per_damage = 0.0
	assert_true(profile.validate().has_warnings())


func _read_without_comments(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var kept: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	file.close()
	return "\n".join(kept)
