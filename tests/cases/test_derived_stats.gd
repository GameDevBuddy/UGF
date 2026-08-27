extends FrameworkTestCase
## Derived stats: a stat whose base is computed from other stats
## (Implementation Plan 12, "derived stats").
##
## Before this, every modifier in the framework carried a literal authored
## number and the only cross-stat derivation anywhere was
## [HealthComponent]'s [code]maximum_stat[/code] -- a hand-wired special case
## in another module that content could not author.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


func _stat(
	id: StringName, base: float = 0.0, derivation: StatDerivation = null
) -> StatDefinition:
	var definition := StatDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.default_base = base
	definition.minimum = -1000.0
	definition.maximum = 10000.0
	definition.derivation = derivation
	return definition


func _derivation(
	sources: Array[StringName], coefficients: Array[float], constant: float = 0.0
) -> StatDerivation:
	var derivation := StatDerivation.new()
	derivation.sources = sources
	derivation.coefficients = coefficients
	derivation.constant = constant
	return derivation


func _component(definitions: Array) -> StatsComponent:
	var profile := StatsProfile.new()
	var typed: Array[StatDefinition] = []
	typed.assign(definitions)
	profile.stats = typed

	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Character"
	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = profile
	stats.auto_tick = false
	entity.add_child(stats)
	stats.initialize(EntityContext.create(entity, null, core))
	return stats


# --- The arithmetic, with no entity at all --------------------------------

func test_a_derivation_is_a_weighted_sum() -> void:
	# Rule 33: the maths is testable with a plain dictionary and no scene.
	var derivation := _derivation([&"stat.strength", &"stat.endurance"], [2.0, 0.5], 10.0)
	var values := {&"stat.strength": 10.0, &"stat.endurance": 4.0}
	assert_eq(derivation.evaluate(values), 32.0, "2*10 + 0.5*4 + 10")


func test_a_source_the_entity_lacks_contributes_nothing() -> void:
	# A crate has no strength. The honest answer is the constant, not an error.
	var derivation := _derivation([&"stat.strength"], [2.0], 5.0)
	assert_eq(derivation.evaluate({}), 5.0)


func test_a_source_with_no_coefficient_contributes_nothing() -> void:
	# Rather than defaulting to 1.0. Silently weighting a stat because
	# somebody forgot a row is how carry weight ends up equal to intelligence.
	var derivation := _derivation([&"stat.strength", &"stat.wisdom"], [2.0])
	assert_eq(derivation.evaluate({&"stat.strength": 3.0, &"stat.wisdom": 100.0}), 6.0)


func test_a_derivation_can_round_down() -> void:
	var derivation := _derivation([&"stat.strength"], [0.37])
	derivation.whole_numbers = true
	assert_eq(derivation.evaluate({&"stat.strength": 10.0}), 3.0)


func test_a_derivation_can_be_clamped() -> void:
	var derivation := _derivation([&"stat.strength"], [10.0])
	derivation.minimum = 5.0
	derivation.maximum = 50.0
	assert_eq(derivation.evaluate({&"stat.strength": 100.0}), 50.0)
	assert_eq(derivation.evaluate({&"stat.strength": 0.0}), 5.0)


# --- On a live component --------------------------------------------------

func test_a_derived_stat_computes_from_its_sources() -> void:
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0], 5.0)),
	])
	assert_true(stats.is_derived(&"stat.carry"))
	assert_eq(stats.get_value(&"stat.carry"), 25.0)


func test_changing_a_source_changes_what_derives_from_it() -> void:
	# The cache invalidation that makes this a feature rather than a one-shot
	# calculation. Without the dependent map, carry weight keeps reading its
	# old value until something else happens to clear the cache.
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
	])
	assert_eq(stats.get_value(&"stat.carry"), 20.0)

	stats.set_base(&"stat.strength", 30.0)

	assert_eq(stats.get_value(&"stat.carry"), 60.0)


func test_a_modifier_on_the_source_reaches_the_derived_stat() -> void:
	# The whole point of deriving from the value rather than the base: a
	# strength buff has to make you carry more.
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
	])

	stats.add_modifier(
		StatModifier.create(&"stat.strength", StatModifier.Mode.FLAT, 5.0, &"buff.ox")
	)

	assert_eq(stats.get_value(&"stat.carry"), 30.0)


func test_removing_the_buff_takes_the_derived_value_back_down() -> void:
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
	])
	stats.add_modifier(
		StatModifier.create(&"stat.strength", StatModifier.Mode.FLAT, 5.0, &"buff.ox")
	)
	assert_eq(stats.get_value(&"stat.carry"), 30.0)

	stats.remove_modifiers_from(&"buff.ox")

	assert_eq(stats.get_value(&"stat.carry"), 20.0)


func test_a_derived_stat_still_takes_its_own_modifiers() -> void:
	# Derivation replaces the base, not the value. "+10% carry weight" must
	# work on a derived stat exactly as on any other.
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
	])

	stats.add_modifier(
		StatModifier.create(&"stat.carry", StatModifier.Mode.PERCENT_ADD, 0.5, &"perk.mule")
	)

	assert_eq(stats.get_value(&"stat.carry"), 30.0, "20 base, +50%")


func test_a_derived_stat_announces_its_change() -> void:
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
	])
	var changes: Array[StringName] = []
	stats.stat_changed.connect(
		func(stat: StringName, _value: float, _previous: float) -> void: changes.append(stat)
	)

	stats.set_base(&"stat.strength", 20.0)

	assert_has(changes, &"stat.carry", "Nothing told the UI the derived stat moved")


func test_a_chain_of_derivations_resolves() -> void:
	var stats := _component([
		_stat(&"stat.strength", 10.0),
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0])),
		_stat(&"stat.encumbrance", 0.0, _derivation([&"stat.carry"], [0.5])),
	])
	assert_eq(stats.get_value(&"stat.encumbrance"), 10.0)

	stats.set_base(&"stat.strength", 40.0)

	assert_eq(stats.get_value(&"stat.encumbrance"), 40.0, "The change travelled two hops")


func test_an_ordinary_stat_is_unaffected() -> void:
	var stats := _component([_stat(&"stat.strength", 10.0)])
	assert_false(stats.is_derived(&"stat.strength"))
	assert_eq(stats.get_value(&"stat.strength"), 10.0)


# --- Content validation ---------------------------------------------------

func test_a_derivation_cycle_is_rejected() -> void:
	var profile := StatsProfile.new()
	var list: Array[StatDefinition] = [
		_stat(&"stat.a", 1.0, _derivation([&"stat.b"], [1.0])),
		_stat(&"stat.b", 1.0, _derivation([&"stat.a"], [1.0])),
	]
	profile.stats = list

	var result := profile.validate()

	assert_true(result.has_errors())
	assert_true(result.format_report().contains("derive from each other"), result.format_report())


func test_a_cycle_that_slipped_through_returns_a_number_rather_than_hanging() -> void:
	# Validation is where an author is told. The runtime still has to survive
	# content that was never validated, and an engine hang is not surviving.
	var stats := _component([
		_stat(&"stat.a", 3.0, _derivation([&"stat.b"], [1.0])),
		_stat(&"stat.b", 7.0, _derivation([&"stat.a"], [1.0])),
	])
	var value := stats.get_value(&"stat.a")
	assert_true(is_finite(value), "The derivation recursed instead of breaking the loop")


func test_a_stat_deriving_from_itself_is_rejected() -> void:
	var derivation := _derivation([&"stat.a"], [1.0])
	assert_true(derivation.validate(&"stat.a").has_errors())


func test_mismatched_source_and_coefficient_rows_are_rejected() -> void:
	var derivation := _derivation([&"stat.a", &"stat.b"], [1.0])
	assert_true(derivation.validate(&"stat.c").has_errors())


func test_deriving_from_a_stat_the_profile_lacks_warns() -> void:
	# Not an error -- an absent source legitimately contributes nothing -- but
	# a derived stat quietly equal to its constant is a wrong number nobody
	# notices for months.
	var profile := StatsProfile.new()
	var list: Array[StatDefinition] = [
		_stat(&"stat.carry", 0.0, _derivation([&"stat.strength"], [2.0]))
	]
	profile.stats = list

	var result := profile.validate()

	assert_true(result.has_warnings())
	assert_false(result.has_errors())
