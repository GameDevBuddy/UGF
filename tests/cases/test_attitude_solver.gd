extends FrameworkTestCase
## Covers AttitudeSolver: where the bands sit and what they mean.

func _resolve(standing: float) -> AttitudeSolver.Attitude:
	return AttitudeSolver.resolve(standing, -50.0, -15.0, 25.0, 70.0)


func test_the_bands_run_from_hostile_to_allied() -> void:
	assert_eq(_resolve(-100.0), AttitudeSolver.Attitude.HOSTILE)
	assert_eq(_resolve(-30.0), AttitudeSolver.Attitude.WARY)
	assert_eq(_resolve(0.0), AttitudeSolver.Attitude.NEUTRAL)
	assert_eq(_resolve(40.0), AttitudeSolver.Attitude.FRIENDLY)
	assert_eq(_resolve(90.0), AttitudeSolver.Attitude.ALLIED)


func test_the_boundaries_belong_to_the_stronger_feeling() -> void:
	# At exactly the hostile threshold, a guard draws. Ambiguity here is the
	# kind that ships as "sometimes they attack and sometimes they don't".
	assert_eq(_resolve(-50.0), AttitudeSolver.Attitude.HOSTILE)
	assert_eq(_resolve(-15.0), AttitudeSolver.Attitude.WARY)
	assert_eq(_resolve(25.0), AttitudeSolver.Attitude.FRIENDLY)
	assert_eq(_resolve(70.0), AttitudeSolver.Attitude.ALLIED)


func test_overlapping_bands_resolve_to_the_safer_reading() -> void:
	# Content with contradictory thresholds should make an NPC cautious, not
	# make it friendly to something it is also hostile to.
	assert_eq(
		AttitudeSolver.resolve(0.0, 50.0, 50.0, -50.0, -50.0),
		AttitudeSolver.Attitude.HOSTILE
	)


func test_hostility_and_friendliness_are_asked_by_name() -> void:
	assert_true(AttitudeSolver.is_hostile(AttitudeSolver.Attitude.HOSTILE))
	assert_false(AttitudeSolver.is_hostile(AttitudeSolver.Attitude.WARY))
	assert_true(AttitudeSolver.is_friendly(AttitudeSolver.Attitude.FRIENDLY))
	assert_true(AttitudeSolver.is_friendly(AttitudeSolver.Attitude.ALLIED))
	assert_false(AttitudeSolver.is_friendly(AttitudeSolver.Attitude.NEUTRAL))


func test_only_hostiles_and_the_wary_read_as_threatening() -> void:
	assert_true(AttitudeSolver.threat_scale(AttitudeSolver.Attitude.HOSTILE) > 1.0)
	assert_almost_eq(AttitudeSolver.threat_scale(AttitudeSolver.Attitude.WARY), 1.0)
	assert_almost_eq(AttitudeSolver.threat_scale(AttitudeSolver.Attitude.NEUTRAL), 0.0)
	assert_almost_eq(AttitudeSolver.threat_scale(AttitudeSolver.Attitude.ALLIED), 0.0)


func test_a_hostile_reads_as_more_dangerous_than_someone_merely_watching() -> void:
	# So an NPC picks the fight in front of it over the stronger thing
	# standing behind it doing nothing.
	assert_true(
		AttitudeSolver.threat_scale(AttitudeSolver.Attitude.HOSTILE)
		> AttitudeSolver.threat_scale(AttitudeSolver.Attitude.WARY)
	)


func test_prices_move_with_standing() -> void:
	assert_almost_eq(AttitudeSolver.price_scale(AttitudeSolver.Attitude.ALLIED, 0.2), 0.8)
	assert_almost_eq(AttitudeSolver.price_scale(AttitudeSolver.Attitude.FRIENDLY, 0.2), 0.9)
	assert_almost_eq(AttitudeSolver.price_scale(AttitudeSolver.Attitude.NEUTRAL, 0.2), 1.0)
	assert_almost_eq(AttitudeSolver.price_scale(AttitudeSolver.Attitude.WARY, 0.2), 1.1)
	assert_almost_eq(AttitudeSolver.price_scale(AttitudeSolver.Attitude.HOSTILE, 0.2), 1.2)


func test_a_zero_spread_charges_everyone_list_price() -> void:
	for attitude in AttitudeSolver.Attitude.values():
		assert_almost_eq(AttitudeSolver.price_scale(attitude, 0.0), 1.0)


func test_attitudes_have_semantic_names() -> void:
	assert_eq(AttitudeSolver.to_name(AttitudeSolver.Attitude.HOSTILE), &"attitude.hostile")
	assert_eq(AttitudeSolver.to_name(AttitudeSolver.Attitude.NEUTRAL), &"attitude.neutral")
