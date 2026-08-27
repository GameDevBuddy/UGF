extends FrameworkTestCase
## Covers StatsComponent: source-tracked modifiers, depletable resources with
## regeneration, and what stats put in a save.

var entity: Node = null
var component: StatsComponent = null
var profile: StatsProfile = null
var power: StatDefinition = null
var stamina: StatDefinition = null


func before_each() -> void:
	entity = add_test_node(Node.new())

	power = StatDefinition.new()
	power.id = &"stat.power"
	power.display_name = "Power"
	power.default_base = 10.0
	power.minimum = 0.0

	stamina = StatDefinition.new()
	stamina.id = &"stat.stamina"
	stamina.display_name = "Stamina"
	stamina.default_base = 100.0
	stamina.minimum = 0.0
	stamina.maximum = 500.0
	stamina.depletable = true
	stamina.regen_per_second = 10.0
	stamina.regen_delay = 0.0

	profile = StatsProfile.new()
	profile.stats = [power, stamina]

	component = StatsComponent.new()
	component.profile_override = profile
	component.auto_tick = false
	entity.add_child(component)
	component.initialize(EntityContext.create(entity))


# --- Setup ----------------------------------------------------------------

func test_stats_come_from_the_profile() -> void:
	assert_true(component.has_stat(&"stat.power"))
	assert_almost_eq(component.get_value(&"stat.power"), 10.0)


func test_a_stat_the_entity_does_not_have_returns_the_fallback() -> void:
	# Absent is not the same as zero. A crate has no strength, and returning
	# zero would let callers treat it as merely weak.
	assert_false(component.has_stat(&"stat.charisma"))
	assert_almost_eq(component.get_value(&"stat.charisma", -1.0), -1.0)


func test_a_base_override_beats_the_definition_default() -> void:
	var overridden := StatsProfile.new()
	overridden.stats = [power]
	overridden.base_overrides = {&"stat.power": 42.0}
	var other := StatsComponent.new()
	other.profile_override = overridden
	entity.add_child(other)
	other.initialize(EntityContext.create(entity))
	assert_almost_eq(other.get_value(&"stat.power"), 42.0)


func test_the_profile_comes_from_the_definition() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.guard"
	definition.stats = profile
	var from_data := StatsComponent.new()
	entity.add_child(from_data)
	from_data.initialize(EntityContext.create(entity, definition))
	assert_true(from_data.has_stat(&"stat.power"))


func test_a_component_with_no_profile_has_no_stats() -> void:
	var bare := StatsComponent.new()
	entity.add_child(bare)
	bare.initialize(EntityContext.create(entity))
	assert_empty(bare.get_stat_ids())
	assert_almost_eq(bare.get_value(&"stat.power", 7.0), 7.0)


func test_innate_modifiers_are_applied_from_the_profile() -> void:
	profile.innate_modifiers = [StatModifier.flat(&"stat.power", 5.0, &"species")]
	var innate := StatsComponent.new()
	innate.profile_override = profile
	entity.add_child(innate)
	innate.initialize(EntityContext.create(entity))
	assert_almost_eq(innate.get_value(&"stat.power"), 15.0)


# --- Modifiers ------------------------------------------------------------

func test_adding_a_modifier_changes_the_value() -> void:
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"buff"))
	assert_almost_eq(component.get_value(&"stat.power"), 15.0)


func test_removing_by_source_takes_back_exactly_that_source() -> void:
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"buff.a"))
	component.add_modifier(StatModifier.flat(&"stat.power", 3.0, &"buff.b"))
	assert_almost_eq(component.get_value(&"stat.power"), 18.0)

	assert_eq(component.remove_modifiers_from(&"buff.a"), 1)
	assert_almost_eq(component.get_value(&"stat.power"), 13.0, 0.0001, "b survived")


func test_two_overlapping_buffs_unwind_to_the_original_in_either_order() -> void:
	# The drift this design exists to prevent: a stat that ends a little off
	# every time two effects overlap, invisible until a save comes back wrong.
	var before := component.get_value(&"stat.power")
	component.add_modifier(StatModifier.percent(&"stat.power", 0.5, &"buff.a"))
	component.add_modifier(StatModifier.flat(&"stat.power", 20.0, &"buff.b"))
	component.remove_modifiers_from(&"buff.b")
	component.remove_modifiers_from(&"buff.a")
	assert_almost_eq(component.get_value(&"stat.power"), before, 0.0001)

	component.add_modifier(StatModifier.percent(&"stat.power", 0.5, &"buff.a"))
	component.add_modifier(StatModifier.flat(&"stat.power", 20.0, &"buff.b"))
	component.remove_modifiers_from(&"buff.a")
	component.remove_modifiers_from(&"buff.b")
	assert_almost_eq(component.get_value(&"stat.power"), before, 0.0001, "other order")


func test_removing_a_source_that_applied_nothing_removes_nothing() -> void:
	assert_eq(component.remove_modifiers_from(&"nothing"), 0)


func test_has_modifiers_from_reports_a_source() -> void:
	component.add_modifier(StatModifier.flat(&"stat.power", 1.0, &"buff"))
	assert_true(component.has_modifiers_from(&"buff"))
	assert_false(component.has_modifiers_from(&"other"))


func test_adding_null_fails_cleanly() -> void:
	assert_err(component.add_modifier(null), &"stats.null_modifier")


func test_a_modifier_for_an_absent_stat_is_inert_not_an_error() -> void:
	# An effect is written once and applied to anything; a target without the
	# stat should simply not be affected by that part of it.
	assert_ok(component.add_modifier(StatModifier.flat(&"stat.charisma", 5.0, &"buff")))
	assert_false(component.has_stat(&"stat.charisma"))


func test_stat_changed_fires_with_the_previous_value() -> void:
	var seen: Array = []
	component.stat_changed.connect(
		func(s: StringName, v: float, p: float) -> void: seen.append([s, v, p])
	)
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"buff"))
	assert_size(seen, 1)
	assert_eq(seen[0][0], &"stat.power")
	assert_almost_eq(seen[0][1], 15.0)


func test_clearing_removes_everything() -> void:
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"a"))
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"b"))
	component.clear_modifiers()
	assert_almost_eq(component.get_value(&"stat.power"), 10.0)
	assert_empty(component.get_modifiers())


func test_setting_a_base_is_progression_not_a_modifier() -> void:
	component.set_base(&"stat.power", 20.0)
	assert_almost_eq(component.get_value(&"stat.power"), 20.0)
	assert_empty(component.get_modifiers(), "and it added no modifier")


# --- Depletion ------------------------------------------------------------

func test_a_depletable_stat_starts_full() -> void:
	assert_true(component.is_depletable(&"stat.stamina"))
	assert_almost_eq(component.get_current(&"stat.stamina"), 100.0)
	assert_almost_eq(component.get_fraction(&"stat.stamina"), 1.0)


func test_spending_reduces_the_current_value() -> void:
	assert_almost_eq(component.spend(&"stat.stamina", 30.0), 30.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 70.0)


func test_spending_more_than_available_spends_what_there_is() -> void:
	assert_almost_eq(component.spend(&"stat.stamina", 500.0), 100.0)
	assert_true(component.is_depleted(&"stat.stamina"))


func test_can_spend_answers_before_committing() -> void:
	# Rule 17: validate the whole operation before mutating any of it.
	assert_true(component.can_spend(&"stat.stamina", 100.0))
	assert_false(component.can_spend(&"stat.stamina", 101.0))


func test_depletion_is_announced() -> void:
	var fired := [0]
	component.stat_depleted.connect(func(_s: StringName) -> void: fired[0] += 1)
	component.spend(&"stat.stamina", 100.0)
	assert_eq(fired[0], 1)


func test_restoring_refills_up_to_the_maximum() -> void:
	component.spend(&"stat.stamina", 50.0)
	assert_almost_eq(component.restore(&"stat.stamina", 200.0), 50.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 100.0)


func test_a_non_depletable_stat_reports_its_computed_value_as_current() -> void:
	assert_false(component.is_depletable(&"stat.power"))
	assert_almost_eq(component.get_current(&"stat.power"), 10.0)


# --- Regeneration ---------------------------------------------------------

func test_regeneration_refills_over_time() -> void:
	component.spend(&"stat.stamina", 50.0)
	component.tick(1.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 60.0, 0.0001)


func test_regeneration_stops_at_full() -> void:
	component.spend(&"stat.stamina", 5.0)
	component.tick(100.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 100.0)


func test_the_regen_delay_holds_it_back() -> void:
	# Without a delay a stamina bar refills between two frames of sprinting.
	stamina.regen_delay = 1.0
	var delayed := StatsComponent.new()
	delayed.profile_override = profile
	delayed.auto_tick = false
	entity.add_child(delayed)
	delayed.initialize(EntityContext.create(entity))

	delayed.spend(&"stat.stamina", 50.0)
	delayed.tick(0.5)
	assert_almost_eq(delayed.get_current(&"stat.stamina"), 50.0, 0.0001, "still waiting")
	delayed.tick(0.6)
	assert_true(delayed.get_current(&"stat.stamina") > 50.0, "and then it resumes")


func test_a_stat_that_does_not_regenerate_stays_where_it_is() -> void:
	stamina.regen_per_second = 0.0
	var static_stat := StatsComponent.new()
	static_stat.profile_override = profile
	static_stat.auto_tick = false
	entity.add_child(static_stat)
	static_stat.initialize(EntityContext.create(entity))
	static_stat.spend(&"stat.stamina", 50.0)
	static_stat.tick(10.0)
	assert_almost_eq(static_stat.get_current(&"stat.stamina"), 50.0)


func test_nothing_ticks_when_no_stat_regenerates() -> void:
	# Rule 26: a component with nothing to do costs nothing to have.
	stamina.regen_per_second = 0.0
	var idle := StatsComponent.new()
	idle.profile_override = profile
	entity.add_child(idle)
	idle.initialize(EntityContext.create(entity))
	assert_false(idle.is_physics_processing())


# --- Interaction between modifiers and depletion --------------------------

func test_raising_a_maximum_does_not_refill() -> void:
	# Raising the ceiling and filling the room are different decisions.
	# Conflating them makes every buff a free heal.
	component.spend(&"stat.stamina", 50.0)
	component.add_modifier(StatModifier.flat(&"stat.stamina", 100.0, &"buff"))
	assert_almost_eq(component.get_value(&"stat.stamina"), 200.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 50.0, 0.0001, "unchanged")


func test_lowering_a_maximum_clamps_the_current_value_down() -> void:
	component.add_modifier(StatModifier.flat(&"stat.stamina", -60.0, &"debuff"))
	assert_almost_eq(component.get_value(&"stat.stamina"), 40.0)
	assert_almost_eq(component.get_current(&"stat.stamina"), 40.0, 0.0001)


# --- Persistence ----------------------------------------------------------

func test_stats_are_persistent() -> void:
	assert_true(component.is_persistent())


func test_bases_and_current_values_round_trip() -> void:
	component.set_base(&"stat.power", 25.0)
	component.spend(&"stat.stamina", 40.0)
	var captured := component.capture_state()

	var restored := StatsComponent.new()
	restored.profile_override = profile
	restored.auto_tick = false
	entity.add_child(restored)
	restored.initialize(EntityContext.create(entity))
	restored.restore_state(captured)

	assert_almost_eq(restored.get_value(&"stat.power"), 25.0)
	assert_almost_eq(restored.get_current(&"stat.stamina"), 60.0)


func test_modifiers_are_not_saved() -> void:
	# Status effects and equipment restore their own state and reapply.
	# Persisting modifiers here too would double every buff on load.
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"buff"))
	var captured := component.capture_state()
	assert_has_not(captured.keys(), "modifiers")


func test_restore_tolerates_an_empty_save() -> void:
	component.restore_state({})
	assert_almost_eq(component.get_value(&"stat.power"), 10.0)


func test_restore_ignores_stats_this_entity_does_not_have() -> void:
	component.restore_state({"bases": {"stat.nonexistent": 99.0}})
	assert_false(component.has_stat(&"stat.nonexistent"))


# --- Explanation ----------------------------------------------------------

func test_explain_describes_a_real_stat() -> void:
	component.add_modifier(StatModifier.flat(&"stat.power", 5.0, &"buff"))
	assert_true(component.explain(&"stat.power").contains("buff"))


func test_explain_says_so_for_an_absent_stat() -> void:
	assert_true(component.explain(&"stat.charisma").contains("not a stat"))
