extends FrameworkTestCase
## Covers StatCalculator: the fixed order modifiers apply in, and the
## difference between additive and compounding percentages.
##
## This suite is the M3 exit gate for "modifiers stack predictably". The claim
## is only checkable because the arithmetic is a static function taking numbers
## and returning a number — no component, no entity, no frame.


func _flat(value: float, source: StringName = &"test") -> StatModifier:
	return StatModifier.flat(&"stat.power", value, source)


func _percent(value: float, source: StringName = &"test") -> StatModifier:
	return StatModifier.percent(&"stat.power", value, source)


func _multiplier(value: float, source: StringName = &"test") -> StatModifier:
	return StatModifier.multiplier(&"stat.power", value, source)


# --- The base case --------------------------------------------------------

func test_no_modifiers_returns_the_base() -> void:
	assert_almost_eq(StatCalculator.calculate(10.0, [], &"stat.power"), 10.0)


func test_a_flat_modifier_adds() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(5.0)], &"stat.power"), 15.0
	)


func test_flat_modifiers_sum() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(5.0), _flat(3.0)], &"stat.power"), 18.0
	)


func test_a_negative_flat_modifier_subtracts() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(-4.0)], &"stat.power"), 6.0
	)


# --- The distinction the whole design turns on ---------------------------

func test_additive_percentages_sum_rather_than_compound() -> void:
	# Two +10% additive give +20%, not +21%. This is what designers predict,
	# and gear bonuses are expected to behave this way.
	assert_almost_eq(
		StatCalculator.calculate(100.0, [_percent(0.1), _percent(0.1)], &"stat.power"),
		120.0,
		0.0001
	)


func test_compounding_percentages_multiply() -> void:
	# Two +10% compounding give +21%. Rarer, and reserved for effects that are
	# meant to snowball.
	assert_almost_eq(
		StatCalculator.calculate(
			100.0, [_multiplier(0.1), _multiplier(0.1)], &"stat.power"
		),
		121.0,
		0.0001
	)


func test_the_two_percentage_modes_are_genuinely_different() -> void:
	var additive := StatCalculator.calculate(
		100.0, [_percent(0.5), _percent(0.5)], &"stat.power"
	)
	var compounding := StatCalculator.calculate(
		100.0, [_multiplier(0.5), _multiplier(0.5)], &"stat.power"
	)
	assert_almost_eq(additive, 200.0, 0.0001)
	assert_almost_eq(compounding, 225.0, 0.0001)


# --- Order ----------------------------------------------------------------

func test_flat_applies_before_percentage() -> void:
	# (10 + 10) * 1.5 = 30, not 10 + (10 * 1.5) = 25. Fixed, documented, and
	# the reason a designer can reason about gear at all.
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(10.0), _percent(0.5)], &"stat.power"),
		30.0,
		0.0001
	)


func test_the_result_does_not_depend_on_the_order_they_were_added() -> void:
	# Two buffs applying in either order must reach the same number, or a stat
	# drifts every time effects overlap.
	var forward := StatCalculator.calculate(
		50.0, [_flat(10.0), _percent(0.2), _multiplier(0.1)], &"stat.power"
	)
	var backward := StatCalculator.calculate(
		50.0, [_multiplier(0.1), _percent(0.2), _flat(10.0)], &"stat.power"
	)
	assert_almost_eq(forward, backward, 0.0001)


func test_all_three_modes_together() -> void:
	# (100 + 20) * (1 + 0.5) * 1.1 = 198
	var value := StatCalculator.calculate(
		100.0, [_flat(20.0), _percent(0.5), _multiplier(0.1)], &"stat.power"
	)
	assert_almost_eq(value, 198.0, 0.0001)


# --- Filtering ------------------------------------------------------------

func test_modifiers_for_other_stats_are_ignored() -> void:
	# A caller hands over the whole modifier list without filtering it first.
	var other := StatModifier.flat(&"stat.speed", 100.0, &"test")
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(5.0), other], &"stat.power"), 15.0
	)


func test_an_empty_stat_filter_applies_everything() -> void:
	var other := StatModifier.flat(&"stat.speed", 5.0, &"test")
	assert_almost_eq(StatCalculator.calculate(10.0, [_flat(5.0), other]), 20.0)


func test_null_entries_are_skipped() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [null, _flat(5.0), null], &"stat.power"), 15.0
	)


# --- Clamping -------------------------------------------------------------

func test_the_result_is_clamped_to_the_maximum() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(100.0)], &"stat.power", 0.0, 50.0), 50.0
	)


func test_the_result_is_clamped_to_the_minimum() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(-100.0)], &"stat.power", 0.0, 50.0), 0.0
	)


func test_unclamped_by_default() -> void:
	assert_almost_eq(
		StatCalculator.calculate(10.0, [_flat(-100.0)], &"stat.power"), -90.0
	)


# --- Introspection --------------------------------------------------------

func test_collect_for_returns_only_the_matching_stat() -> void:
	var other := StatModifier.flat(&"stat.speed", 1.0, &"test")
	var collected := StatCalculator.collect_for([_flat(1.0), other, _percent(0.1)], &"stat.power")
	assert_size(collected, 2)


func test_collect_for_orders_flat_before_percentage() -> void:
	var collected := StatCalculator.collect_for(
		[_multiplier(0.1), _percent(0.1), _flat(1.0)], &"stat.power"
	)
	assert_eq(collected[0].mode, StatModifier.Mode.FLAT)
	assert_eq(collected[1].mode, StatModifier.Mode.PERCENT_ADD)
	assert_eq(collected[2].mode, StatModifier.Mode.PERCENT_MULTIPLY)


func test_affected_stats_lists_each_once() -> void:
	var stats := StatCalculator.affected_stats(
		[_flat(1.0), _flat(2.0), StatModifier.flat(&"stat.speed", 1.0, &"t")]
	)
	assert_size(stats, 2)
	assert_has(stats, &"stat.power")
	assert_has(stats, &"stat.speed")


func test_explain_shows_the_working() -> void:
	# "Why is my damage 47?" should be answerable without a debugger (rule 28).
	var report := StatCalculator.explain(
		100.0, [_flat(20.0), _percent(0.5)], &"stat.power"
	)
	assert_true(report.contains("base 100"))
	assert_true(report.contains("180"))


func test_explain_reports_a_clamp() -> void:
	var report := StatCalculator.explain(
		100.0, [_flat(500.0)], &"stat.power", 0.0, 200.0
	)
	assert_true(report.contains("clamped"))


# --- The modifier resource ------------------------------------------------

func test_a_modifier_needs_a_stat() -> void:
	var modifier := StatModifier.new()
	assert_true(modifier.validate().has_errors())


func test_a_modifier_without_a_source_is_a_warning() -> void:
	# Not an error: an innate modifier nothing ever removes is legitimate. But
	# removal is by source, so a blank one can never be taken back.
	var modifier := StatModifier.flat(&"stat.power", 1.0)
	var result := modifier.validate()
	assert_false(result.has_errors())
	assert_true(result.has_warnings())


func test_a_well_formed_modifier_validates_clean() -> void:
	assert_false(_flat(1.0).validate().has_warnings())
