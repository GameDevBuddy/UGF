extends FrameworkTestCase
## Covers StatusEffectComponent: stacking policies, expiry, periodic damage,
## and the guarantee that overlapping effects unwind without drift.

var entity: Node = null
var stats: StatsComponent = null
var health: HealthComponent = null
var receiver: DamageReceiverComponent = null
var effects: StatusEffectComponent = null
var power: StatDefinition = null


func before_each() -> void:
	entity = add_test_node(Node.new())

	power = StatDefinition.new()
	power.id = &"stat.power"
	power.default_base = 10.0
	var profile := StatsProfile.new()
	profile.stats = [power]

	stats = StatsComponent.new()
	stats.profile_override = profile
	stats.auto_tick = false
	entity.add_child(stats)

	health = HealthComponent.new()
	health.maximum_health = 100.0
	entity.add_child(health)

	receiver = DamageReceiverComponent.new()
	receiver.health = health
	entity.add_child(receiver)

	effects = StatusEffectComponent.new()
	effects.stats = stats
	effects.damage_receiver = receiver
	effects.auto_tick = false
	entity.add_child(effects)

	for component in [stats, health, receiver, effects]:
		component.initialize(EntityContext.create(entity))


func _buff(id: StringName, amount: float, duration: float = 5.0) -> StatusEffectDefinition:
	var definition := StatusEffectDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.duration = duration
	definition.modifiers = [StatModifier.flat(&"stat.power", amount)]
	return definition


func _poison(dps: float, duration: float, interval: float = 1.0) -> StatusEffectDefinition:
	var definition := StatusEffectDefinition.new()
	definition.id = &"effect.poison"
	definition.display_name = "Poison"
	definition.duration = duration
	definition.damage_per_second = dps
	definition.tick_interval = interval
	definition.damage_tags = [GameplayNames.DAMAGE_POISON]
	return definition


# --- Applying -------------------------------------------------------------

func test_applying_an_effect_applies_its_modifiers() -> void:
	assert_ok(effects.apply(_buff(&"effect.strong", 5.0)))
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0)


func test_the_effect_is_tracked() -> void:
	effects.apply(_buff(&"effect.strong", 5.0))
	assert_true(effects.has_effect(&"effect.strong"))
	assert_has(effects.get_effect_ids(), &"effect.strong")


func test_applying_is_announced() -> void:
	var seen: Array = []
	effects.effect_applied.connect(
		func(i: StatusEffectInstance) -> void: seen.append(i.get_id())
	)
	effects.apply(_buff(&"effect.strong", 5.0))
	assert_eq(seen, [&"effect.strong"])


func test_applying_null_fails_cleanly() -> void:
	assert_err(effects.apply(null), &"status.null_definition")


func test_an_effect_with_no_id_is_refused() -> void:
	# Without an id nothing can remove it, and its modifiers would be permanent
	# by accident.
	var nameless := StatusEffectDefinition.new()
	nameless.duration = 5.0
	assert_err(effects.apply(nameless), &"status.unnamed_effect")


func test_modifiers_are_stamped_with_the_effect_id() -> void:
	# Authored modifiers leave source blank; getting it wrong by hand would
	# mean an expiring effect removes nothing, or removes another's work.
	effects.apply(_buff(&"effect.strong", 5.0))
	assert_true(stats.has_modifiers_from(&"effect.strong"))


# --- Stacking policies ----------------------------------------------------

func test_refresh_restarts_the_duration_without_stacking() -> void:
	var definition := _buff(&"effect.strong", 5.0, 10.0)
	definition.stacking = StatusEffectDefinition.Stacking.REFRESH
	effects.apply(definition)
	effects.tick(6.0)
	effects.apply(definition)

	assert_eq(effects.get_stacks(&"effect.strong"), 1)
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0, 0.0001, "still one buff")
	assert_almost_eq(effects.get_instance(&"effect.strong").remaining, 10.0)


func test_stack_accumulates_up_to_the_cap() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	definition.stacking = StatusEffectDefinition.Stacking.STACK
	definition.max_stacks = 3

	effects.apply(definition)
	effects.apply(definition)
	assert_eq(effects.get_stacks(&"effect.strong"), 2)
	assert_almost_eq(stats.get_value(&"stat.power"), 20.0)

	effects.apply(definition)
	effects.apply(definition)
	assert_eq(effects.get_stacks(&"effect.strong"), 3, "capped")
	assert_almost_eq(stats.get_value(&"stat.power"), 25.0)


func test_ignore_refuses_a_second_application() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	definition.stacking = StatusEffectDefinition.Stacking.IGNORE
	effects.apply(definition)
	assert_err(effects.apply(definition), &"status.already_active")
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0)


func test_separate_tracks_each_application_independently() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	definition.stacking = StatusEffectDefinition.Stacking.SEPARATE
	effects.apply(definition)
	effects.apply(definition)
	assert_size(effects.get_instances(), 2)
	assert_almost_eq(stats.get_value(&"stat.power"), 20.0)


# --- Expiry ---------------------------------------------------------------

func test_an_effect_expires_and_takes_its_modifiers_with_it() -> void:
	effects.apply(_buff(&"effect.strong", 5.0, 2.0))
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0)

	effects.tick(2.5)
	assert_false(effects.has_effect(&"effect.strong"))
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0, 0.0001, "back to base")


func test_expiry_is_announced_as_expired() -> void:
	var seen: Array = []
	effects.effect_removed.connect(
		func(id: StringName, expired: bool) -> void: seen.append([id, expired])
	)
	effects.apply(_buff(&"effect.strong", 5.0, 1.0))
	effects.tick(2.0)
	assert_size(seen, 1)
	assert_true(seen[0][1], "expired, not removed")


func test_removal_is_announced_as_not_expired() -> void:
	var seen: Array = []
	effects.effect_removed.connect(
		func(_id: StringName, expired: bool) -> void: seen.append(expired)
	)
	effects.apply(_buff(&"effect.strong", 5.0))
	effects.remove(&"effect.strong")
	assert_eq(seen, [false] as Array)


func test_a_permanent_effect_never_expires() -> void:
	effects.apply(_buff(&"effect.blessed", 5.0, 0.0))
	effects.tick(10000.0)
	assert_true(effects.has_effect(&"effect.blessed"))


func test_clear_removes_everything() -> void:
	effects.apply(_buff(&"effect.a", 5.0))
	effects.apply(_buff(&"effect.b", 5.0))
	effects.clear()
	assert_true(effects.is_empty())
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0)


# --- The drift this design prevents ---------------------------------------

func test_overlapping_effects_unwind_to_the_original_in_either_order() -> void:
	var before := stats.get_value(&"stat.power")
	var a := _buff(&"effect.a", 5.0, 1.0)
	var b := _buff(&"effect.b", 20.0, 2.0)

	effects.apply(a)
	effects.apply(b)
	effects.tick(1.5)
	assert_false(effects.has_effect(&"effect.a"), "the short one went first")
	effects.tick(1.0)

	assert_true(effects.is_empty())
	assert_almost_eq(stats.get_value(&"stat.power"), before, 0.0001)


func test_stacked_modifiers_all_come_back_off_together() -> void:
	var definition := _buff(&"effect.strong", 5.0, 2.0)
	definition.stacking = StatusEffectDefinition.Stacking.STACK
	definition.max_stacks = 3
	effects.apply(definition)
	effects.apply(definition)
	effects.apply(definition)
	assert_almost_eq(stats.get_value(&"stat.power"), 25.0)

	effects.tick(3.0)
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0, 0.0001, "all three stacks")


# --- Periodic damage ------------------------------------------------------

func test_poison_damages_on_its_interval() -> void:
	effects.apply(_poison(10.0, 10.0, 1.0))
	effects.tick(0.5)
	assert_almost_eq(health.get_current(), 100.0, 0.0001, "not yet")
	effects.tick(0.6)
	assert_almost_eq(health.get_current(), 90.0, 0.0001, "one tick of 10")


func test_periodic_damage_goes_through_mitigation() -> void:
	# A poison should meet armour the same way a hit does.
	var profile := ResistanceProfile.new()
	profile.resistances = {GameplayNames.DAMAGE_POISON: 0.5}
	receiver.profile_override = profile
	receiver.initialize(EntityContext.create(entity))

	effects.apply(_poison(10.0, 10.0, 1.0))
	effects.tick(1.0)
	assert_almost_eq(health.get_current(), 95.0, 0.0001, "halved")


func test_a_continuous_effect_scales_with_frame_time() -> void:
	effects.apply(_poison(10.0, 10.0, 0.0))
	effects.tick(0.5)
	assert_almost_eq(health.get_current(), 95.0, 0.0001)


func test_stacked_poison_hurts_more() -> void:
	var definition := _poison(10.0, 10.0, 1.0)
	definition.stacking = StatusEffectDefinition.Stacking.STACK
	definition.max_stacks = 2
	effects.apply(definition)
	effects.apply(definition)
	effects.tick(1.0)
	assert_almost_eq(health.get_current(), 80.0, 0.0001, "two stacks of 10")


func test_a_regeneration_effect_heals() -> void:
	# Negative damage per second, so regeneration needs no second field.
	receiver.receive_amount(50.0)
	assert_almost_eq(health.get_current(), 50.0)

	var regen := _poison(-10.0, 10.0, 1.0)
	regen.id = &"effect.regen"
	effects.apply(regen)
	effects.tick(1.0)
	assert_almost_eq(health.get_current(), 60.0, 0.0001)


func test_a_long_frame_applies_every_tick_it_covers() -> void:
	# A hitch must not silently skip damage.
	effects.apply(_poison(10.0, 100.0, 1.0))
	effects.tick(3.0)
	assert_almost_eq(health.get_current(), 70.0, 0.0001, "three ticks")


func test_periodic_damage_is_skipped_rather_than_bypassing_armour() -> void:
	var lone_entity := add_test_node(Node.new())
	var lone := StatusEffectComponent.new()
	lone.auto_tick = false
	lone_entity.add_child(lone)
	lone.initialize(EntityContext.create(lone_entity))
	lone.apply(_poison(10.0, 10.0, 1.0))
	lone.tick(2.0)
	assert_true(lone.has_effect(&"effect.poison"), "still running, just not landing")


# --- Interactions ---------------------------------------------------------

func test_an_effect_can_remove_another() -> void:
	effects.apply(_poison(10.0, 10.0))
	var cleanse := _buff(&"effect.cleanse", 0.0, 1.0)
	cleanse.removes = [&"effect.poison"]
	cleanse.modifiers = []
	cleanse.applied_states = [&"state.cleansed"]
	effects.apply(cleanse)
	assert_false(effects.has_effect(&"effect.poison"))


func test_semantic_states_are_applied_and_cleared() -> void:
	var state := SemanticState.new()
	entity.add_child(state)
	effects.semantic_state = state

	var definition := _buff(&"effect.burning", 0.0, 2.0)
	definition.modifiers = []
	definition.applied_states = [&"state.burning"]
	effects.apply(definition)
	assert_true(state.has_state(&"state.burning"))

	effects.tick(3.0)
	assert_false(state.has_state(&"state.burning"))


func test_effects_work_with_no_stats_at_all() -> void:
	# An effect with only state tags works on an entity with no attributes.
	var bare_entity := add_test_node(Node.new())
	var bare := StatusEffectComponent.new()
	bare.auto_tick = false
	bare_entity.add_child(bare)
	bare.initialize(EntityContext.create(bare_entity))
	assert_ok(bare.apply(_buff(&"effect.strong", 5.0)))
	assert_true(bare.has_effect(&"effect.strong"))


# --- Instance behaviour ---------------------------------------------------

func test_fraction_remaining_counts_down() -> void:
	effects.apply(_buff(&"effect.strong", 5.0, 10.0))
	var instance := effects.get_instance(&"effect.strong")
	assert_almost_eq(instance.get_fraction_remaining(), 1.0)
	effects.tick(5.0)
	assert_almost_eq(instance.get_fraction_remaining(), 0.5, 0.0001)


func test_a_permanent_instance_reports_full() -> void:
	effects.apply(_buff(&"effect.blessed", 5.0, 0.0))
	var instance := effects.get_instance(&"effect.blessed")
	assert_true(instance.is_permanent())
	assert_almost_eq(instance.get_fraction_remaining(), 1.0)


# --- Persistence ----------------------------------------------------------

func test_effects_are_persistent() -> void:
	assert_true(effects.is_persistent())


func test_capture_records_id_remaining_and_stacks() -> void:
	var definition := _buff(&"effect.strong", 5.0, 10.0)
	definition.stacking = StatusEffectDefinition.Stacking.STACK
	definition.max_stacks = 3
	effects.apply(definition)
	effects.apply(definition)
	effects.tick(2.0)

	var captured := effects.capture_state()
	var saved: Array = captured["effects"]
	assert_size(saved, 1)
	assert_eq(saved[0]["id"], "effect.strong")
	assert_eq(saved[0]["stacks"], 2)
	assert_almost_eq(saved[0]["remaining"], 8.0, 0.0001)


func test_an_effect_can_opt_out_of_being_saved() -> void:
	var definition := _buff(&"effect.transient", 5.0)
	definition.persistent = false
	effects.apply(definition)
	assert_empty(effects.capture_state()["effects"])


func test_modifiers_are_not_saved() -> void:
	# They are rebuilt from the definition on restore. Saving them too would
	# apply every buff twice on load.
	effects.apply(_buff(&"effect.strong", 5.0))
	var captured := effects.capture_state()
	assert_has_not(captured.keys(), "modifiers")


func test_restore_rebuilds_from_the_definition_registry() -> void:
	# Rule 32: the save holds ids, not resource paths, so moving the .tres does
	# not break existing saves.
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	var definition := _buff(&"effect.strong", 5.0, 10.0)
	assert_ok(core.register_definition(definition))

	var restored_entity := add_test_node(Node.new())
	var restored_stats := StatsComponent.new()
	var profile := StatsProfile.new()
	profile.stats = [power]
	restored_stats.profile_override = profile
	restored_stats.auto_tick = false
	restored_entity.add_child(restored_stats)
	var restored := StatusEffectComponent.new()
	restored.stats = restored_stats
	restored.auto_tick = false
	restored_entity.add_child(restored)
	restored_stats.initialize(EntityContext.create(restored_entity, null, core))
	restored.initialize(EntityContext.create(restored_entity, null, core))

	restored.restore_state({
		"effects": [{"id": "effect.strong", "remaining": 4.0, "stacks": 1}]
	})

	assert_true(restored.has_effect(&"effect.strong"))
	assert_almost_eq(restored.get_instance(&"effect.strong").remaining, 4.0)
	assert_almost_eq(restored_stats.get_value(&"stat.power"), 15.0)


func test_restore_tolerates_an_unknown_effect_id() -> void:
	# A save from a build that had an effect this one does not is not corrupt.
	effects.restore_state({"effects": [{"id": "effect.gone", "remaining": 1.0}]})
	assert_true(effects.is_empty())


# --- Definition validation ------------------------------------------------

func test_a_well_formed_effect_validates_clean() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	var result := definition.validate()
	assert_false(result.has_errors(), result.format_report())
	assert_false(result.has_warnings(), result.format_report())


func test_an_effect_that_does_nothing_is_flagged() -> void:
	var empty := StatusEffectDefinition.new()
	empty.id = &"effect.empty"
	empty.display_name = "Empty"
	var result := empty.validate()
	assert_true(result.has_warnings())
	assert_true(result.format_report().contains("does nothing"))


func test_stacking_with_one_stack_is_flagged() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	definition.stacking = StatusEffectDefinition.Stacking.STACK
	definition.max_stacks = 1
	assert_true(definition.validate().has_warnings())


func test_a_permanent_damage_over_time_effect_is_flagged() -> void:
	var definition := _poison(10.0, 0.0)
	assert_true(definition.validate().has_warnings())


func test_a_modifier_with_no_stat_is_an_error() -> void:
	var definition := _buff(&"effect.strong", 5.0)
	definition.modifiers = [StatModifier.new()]
	assert_true(definition.validate().has_errors())


func test_a_blank_source_on_an_authored_modifier_is_not_flagged() -> void:
	# build_modifiers() stamps the effect id over it, so blank is correct here
	# even though StatModifier.validate() warns about it in isolation.
	var definition := _buff(&"effect.strong", 5.0)
	assert_eq(definition.modifiers[0].source, &"")
	assert_false(definition.validate().has_warnings())
