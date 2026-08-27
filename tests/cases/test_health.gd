extends FrameworkTestCase
## Covers HealthComponent, DamageReceiverComponent and HealthEventAdapter —
## including the M3 exit gate that death publishes a cross-feature event, and
## the rule that health itself never touches the bus.

var entity: Node = null
var health: HealthComponent = null
var receiver: DamageReceiverComponent = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	health = HealthComponent.new()
	health.maximum_health = 100.0
	entity.add_child(health)
	receiver = DamageReceiverComponent.new()
	receiver.health = health
	entity.add_child(receiver)
	health.initialize(EntityContext.create(entity))
	receiver.initialize(EntityContext.create(entity))


func _hit(amount: float, tags: Array[StringName] = []) -> DamageContext:
	return DamageContext.create(amount, null, null, tags)


# --- Health ---------------------------------------------------------------

func test_starts_at_full() -> void:
	assert_almost_eq(health.get_current(), 100.0)
	assert_almost_eq(health.get_fraction(), 1.0)
	assert_true(health.is_alive())


func test_damage_reduces_health() -> void:
	receiver.receive(_hit(30.0))
	assert_almost_eq(health.get_current(), 70.0)


func test_health_changed_reports_current_and_maximum() -> void:
	var seen: Array = []
	health.health_changed.connect(
		func(c: float, m: float) -> void: seen.append([c, m])
	)
	receiver.receive(_hit(25.0))
	assert_size(seen, 1)
	assert_almost_eq(seen[0][0], 75.0)
	assert_almost_eq(seen[0][1], 100.0)


func test_reaching_zero_kills() -> void:
	receiver.receive(_hit(100.0))
	assert_true(health.is_dead())
	assert_almost_eq(health.get_current(), 0.0)


func test_death_fires_once() -> void:
	var fired := [0]
	health.died.connect(func(_c: DamageContext) -> void: fired[0] += 1)
	receiver.receive(_hit(200.0))
	receiver.receive(_hit(200.0))
	assert_eq(fired[0], 1)


func test_damage_to_the_dead_is_refused() -> void:
	health.kill()
	assert_err(health.apply_damage(_hit(10.0)), &"health.already_dead")


func test_death_carries_its_cause() -> void:
	var captured: Array = []
	health.died.connect(func(c: DamageContext) -> void: captured.append(c))
	var killer := add_test_node(Node.new())
	var context := DamageContext.create(500.0, killer)
	receiver.receive(context)
	assert_size(captured, 1)
	assert_eq(captured[0].instigator, killer)


func test_the_context_records_what_actually_landed() -> void:
	# Overkill reports the damage that was applied, not the damage requested,
	# so a killing blow does not report 500 against a 40-hit-point target.
	health.set_current(40.0)
	var context := _hit(500.0)
	receiver.receive(context)
	assert_almost_eq(context.final_amount, 40.0)
	assert_true(context.was_lethal)


func test_healing_restores_up_to_the_maximum() -> void:
	receiver.receive(_hit(50.0))
	assert_almost_eq(health.heal(500.0), 50.0)
	assert_true(health.is_full())


func test_healing_does_not_revive() -> void:
	health.kill()
	assert_almost_eq(health.heal(50.0), 0.0)
	assert_true(health.is_dead())


func test_revive_brings_it_back() -> void:
	health.kill()
	assert_ok(health.revive(0.5))
	assert_true(health.is_alive())
	assert_almost_eq(health.get_current(), 50.0)


func test_reviving_the_living_fails() -> void:
	assert_err(health.revive(), &"health.not_dead")


func test_an_undamageable_entity_refuses_damage() -> void:
	health.damageable = false
	assert_err(health.apply_damage(_hit(10.0)), &"health.not_damageable")
	assert_almost_eq(health.get_current(), 100.0)


func test_a_fully_absorbed_hit_is_announced_but_changes_nothing() -> void:
	var fired := [0]
	health.damage_absorbed.connect(func(_c: DamageContext) -> void: fired[0] += 1)
	health.apply_damage(_hit(0.0))
	assert_eq(fired[0], 1)
	assert_almost_eq(health.get_current(), 100.0)


func test_death_sets_the_semantic_state() -> void:
	var state := SemanticState.new()
	entity.add_child(state)
	var binder := DefinitionBinder.new()
	binder.bind_on_ready = false
	entity.add_child(binder)
	health.initialize(EntityContext.create(entity))

	health.kill()
	assert_true(state.has_state(GameplayNames.STATE_DEAD))
	health.revive()
	assert_false(state.has_state(GameplayNames.STATE_DEAD))


# --- Mitigation through the receiver --------------------------------------

func test_the_receiver_applies_armour_before_health_sees_it() -> void:
	var profile := ResistanceProfile.new()
	profile.flat_armor = 10.0
	receiver.profile_override = profile
	receiver.initialize(EntityContext.create(entity))

	receiver.receive(_hit(30.0))
	assert_almost_eq(health.get_current(), 80.0)


func test_an_immune_target_takes_nothing() -> void:
	var profile := ResistanceProfile.new()
	profile.immunities = [GameplayNames.DAMAGE_POISON]
	receiver.profile_override = profile
	receiver.initialize(EntityContext.create(entity))

	var fired := [0]
	receiver.damage_blocked.connect(func(_c: DamageContext) -> void: fired[0] += 1)
	receiver.receive(_hit(50.0, [GameplayNames.DAMAGE_POISON]))
	assert_almost_eq(health.get_current(), 100.0)
	assert_eq(fired[0], 1)


func test_receive_amount_is_a_convenience_for_the_same_path() -> void:
	receiver.receive_amount(20.0)
	assert_almost_eq(health.get_current(), 80.0)


func test_preview_does_not_apply_anything() -> void:
	var profile := ResistanceProfile.new()
	profile.flat_armor = 5.0
	receiver.profile_override = profile
	receiver.initialize(EntityContext.create(entity))

	assert_almost_eq(receiver.preview(20.0), 15.0)
	assert_almost_eq(health.get_current(), 100.0, 0.0001, "nothing was applied")


func test_a_receiver_with_no_health_is_not_broken() -> void:
	# A shield generator or a destructible prop may care about being hit
	# without having hit points.
	var lone := DamageReceiverComponent.new()
	var lone_entity := add_test_node(Node.new())
	lone_entity.add_child(lone)
	lone.initialize(EntityContext.create(lone_entity))
	assert_ok(lone.receive(_hit(10.0)))


func test_receiving_null_fails_cleanly() -> void:
	assert_err(receiver.receive(null), &"damage.null_context")


# --- Maximum from stats ---------------------------------------------------

func _with_stats(maximum: float) -> StatsComponent:
	var definition := StatDefinition.new()
	definition.id = GameplayNames.STAT_HEALTH_MAX
	definition.default_base = maximum
	definition.maximum = 10000.0
	var profile := StatsProfile.new()
	profile.stats = [definition]
	var stats := StatsComponent.new()
	stats.profile_override = profile
	stats.auto_tick = false
	entity.add_child(stats)
	stats.initialize(EntityContext.create(entity))
	return stats


func test_the_maximum_comes_from_stats_when_one_is_wired() -> void:
	health.stats = _with_stats(250.0)
	health.initialize(EntityContext.create(entity))
	assert_almost_eq(health.get_maximum(), 250.0)


func test_the_exported_maximum_is_used_with_no_stats() -> void:
	# A crate with 40 hit points and no attributes is a legitimate entity.
	assert_almost_eq(health.get_maximum(), 100.0)


func test_losing_a_max_health_buff_clamps_current_health_down() -> void:
	var stats := _with_stats(100.0)
	health.stats = stats
	health.initialize(EntityContext.create(entity))
	stats.add_modifier(
		StatModifier.flat(GameplayNames.STAT_HEALTH_MAX, 50.0, &"buff")
	)
	health.heal(500.0)
	assert_almost_eq(health.get_current(), 150.0)

	stats.remove_modifiers_from(&"buff")
	assert_almost_eq(health.get_current(), 100.0, 0.0001, "clamped, not left above max")


func test_gaining_a_max_health_buff_does_not_heal() -> void:
	# Raising the ceiling and filling the room are different decisions.
	var stats := _with_stats(100.0)
	health.stats = stats
	health.initialize(EntityContext.create(entity))
	receiver.receive(_hit(50.0))

	stats.add_modifier(
		StatModifier.flat(GameplayNames.STAT_HEALTH_MAX, 100.0, &"buff")
	)
	assert_almost_eq(health.get_maximum(), 200.0)
	assert_almost_eq(health.get_current(), 50.0, 0.0001, "still hurt")


# --- Rule: components do not touch the bus --------------------------------

func test_health_publishes_nothing_to_the_event_bus() -> void:
	# The testability half of the argument for keeping the bus out of
	# components. Health does its entire job, death included, and the bus
	# hears nothing until something above chooses to promote it.
	var bus := make_autoload(
		"res://addons/universal_gameplay/core/event_bus.gd", "BusUnderTest"
	)
	var published: Array = []
	bus.event_published.connect(func(e: FrameworkEvent) -> void: published.append(e))

	receiver.receive(_hit(500.0))

	assert_true(health.is_dead(), "it died")
	assert_empty(published, "...and told the bus nothing")


# --- The adapter that does promote it -------------------------------------

func test_the_adapter_publishes_a_death_to_the_bus() -> void:
	# The M3 exit gate: death publishes an event.
	var bus := make_autoload(
		"res://addons/universal_gameplay/core/event_bus.gd", "BusUnderTest"
	)
	var published: Array = []
	bus.actor_died.connect(func(e: ActorDiedEvent) -> void: published.append(e))

	var adapter := HealthEventAdapter.new()
	adapter.health = health
	adapter.set_bus(bus)
	entity.add_child(adapter)
	adapter.initialize(EntityContext.create(entity))

	receiver.receive(_hit(500.0))

	assert_size(published, 1)
	assert_eq(published[0].actor, entity)


func test_the_published_event_carries_the_killer() -> void:
	var bus := make_autoload(
		"res://addons/universal_gameplay/core/event_bus.gd", "BusUnderTest"
	)
	var published: Array = []
	bus.actor_died.connect(func(e: ActorDiedEvent) -> void: published.append(e))

	var adapter := HealthEventAdapter.new()
	adapter.health = health
	adapter.set_bus(bus)
	entity.add_child(adapter)
	adapter.initialize(EntityContext.create(entity))

	var killer := add_test_node(Node.new())
	receiver.receive(DamageContext.create(500.0, killer))

	assert_size(published, 1)
	assert_eq(published[0].get_instigator(), killer, "kill attribution survives")


func test_an_entity_can_opt_out_of_announcing_its_death() -> void:
	# Ambient population dying should not flood the bus.
	var bus := make_autoload(
		"res://addons/universal_gameplay/core/event_bus.gd", "BusUnderTest"
	)
	var published: Array = []
	bus.event_published.connect(func(e: FrameworkEvent) -> void: published.append(e))

	var adapter := HealthEventAdapter.new()
	adapter.health = health
	adapter.publish_death = false
	adapter.set_bus(bus)
	entity.add_child(adapter)
	adapter.initialize(EntityContext.create(entity))

	receiver.receive(_hit(500.0))
	assert_true(health.is_dead())
	assert_empty(published)


func test_the_adapter_is_inert_with_no_bus() -> void:
	# Deleting the bus, or running before it exists, must not break dying.
	var adapter := HealthEventAdapter.new()
	adapter.health = health
	entity.add_child(adapter)
	adapter.initialize(EntityContext.create(entity))

	receiver.receive(_hit(500.0))
	assert_true(health.is_dead(), "death still happened")


# --- Persistence ----------------------------------------------------------

func test_health_is_persistent() -> void:
	assert_true(health.is_persistent())


func test_health_and_death_round_trip() -> void:
	receiver.receive(_hit(35.0))
	var captured := health.capture_state()

	var restored := HealthComponent.new()
	restored.maximum_health = 100.0
	entity.add_child(restored)
	restored.initialize(EntityContext.create(entity))
	restored.restore_state(captured)

	assert_almost_eq(restored.get_current(), 65.0)
	assert_true(restored.is_alive())


func test_a_dead_entity_comes_back_dead() -> void:
	health.kill()
	var captured := health.capture_state()

	var restored := HealthComponent.new()
	restored.maximum_health = 100.0
	entity.add_child(restored)
	restored.initialize(EntityContext.create(entity))
	restored.restore_state(captured)

	assert_true(restored.is_dead())


func test_restore_tolerates_an_empty_save() -> void:
	health.restore_state({})
	assert_true(health.is_alive())
