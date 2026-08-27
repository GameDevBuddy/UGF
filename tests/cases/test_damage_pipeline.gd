extends FrameworkTestCase
## Covers DamagePipeline and ResistanceProfile.
##
## This suite is the M3 exit gate for "damage is deterministic". Every test
## here is a pure function call: same context, same profile, same number, with
## no node, no frame and no RNG anywhere in the path.

var profile: ResistanceProfile = null


func before_each() -> void:
	profile = ResistanceProfile.new()
	profile.flat_armor = 0.0
	profile.maximum_resistance = 0.9


func _context(amount: float, tags: Array[StringName] = []) -> DamageContext:
	return DamageContext.create(amount, null, null, tags)


# --- Determinism ----------------------------------------------------------

func test_the_same_input_gives_the_same_output_every_time() -> void:
	profile.flat_armor = 5.0
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.25}
	var first := DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile)
	for _i in range(10):
		assert_almost_eq(
			DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile),
			first,
			0.0
		)


func test_no_profile_means_the_hit_lands_in_full() -> void:
	var context := DamagePipeline.mitigate(_context(40.0), null)
	assert_almost_eq(context.final_amount, 40.0)


func test_mitigate_returns_the_same_context_object() -> void:
	# One object travels the pipeline and whatever survives is what is applied.
	var context := _context(10.0)
	assert_eq(DamagePipeline.mitigate(context, profile), context)


func test_mitigating_null_returns_null_rather_than_erroring() -> void:
	assert_null(DamagePipeline.mitigate(null, profile))


# --- Flat armour ----------------------------------------------------------

func test_flat_armour_subtracts() -> void:
	profile.flat_armor = 8.0
	assert_almost_eq(DamagePipeline.preview(20.0, [], profile), 12.0)


func test_flat_armour_cannot_make_damage_negative() -> void:
	profile.flat_armor = 100.0
	assert_almost_eq(DamagePipeline.preview(20.0, [], profile), 0.0)


func test_armour_is_worth_more_against_many_small_hits() -> void:
	# The reason flat armour applies before percentage: the other order makes
	# armour better against big hits, which is backwards from what it is for.
	profile.flat_armor = 5.0
	var one_big := DamagePipeline.preview(50.0, [], profile)
	var five_small := 0.0
	for _i in range(5):
		five_small += DamagePipeline.preview(10.0, [], profile)
	assert_almost_eq(one_big, 45.0)
	assert_almost_eq(five_small, 25.0, 0.0001, "the same 50 damage, halved by armour")


# --- Percentage resistance ------------------------------------------------

func test_resistance_reduces_by_its_fraction() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.25}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile), 75.0
	)


func test_resistance_only_applies_to_matching_tags() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.5}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_COLD], profile), 100.0
	)


func test_untagged_damage_bypasses_tagged_resistance() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.5}
	assert_almost_eq(DamagePipeline.preview(100.0, [], profile), 100.0)


func test_resistances_sum_across_tags() -> void:
	# Summing is what designers predict; the cap is what stops it reaching
	# invulnerability.
	profile.resistances = {
		GameplayNames.DAMAGE_FIRE: 0.2,
		GameplayNames.DAMAGE_EXPLOSIVE: 0.2,
	}
	var tags: Array[StringName] = [
		GameplayNames.DAMAGE_FIRE, GameplayNames.DAMAGE_EXPLOSIVE
	]
	assert_almost_eq(DamagePipeline.preview(100.0, tags, profile), 60.0, 0.0001)


func test_resistance_is_capped() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 5.0}
	profile.maximum_resistance = 0.9
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile),
		10.0,
		0.0001,
		"never below a tenth"
	)


func test_vulnerability_increases_damage() -> void:
	profile.vulnerabilities = {GameplayNames.DAMAGE_FIRE: 0.5}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile), 150.0
	)


func test_vulnerability_and_resistance_offset() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.5}
	profile.vulnerabilities = {GameplayNames.DAMAGE_FIRE: 0.5}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile), 100.0
	)


# --- Immunity -------------------------------------------------------------

func test_immunity_removes_the_hit_entirely() -> void:
	profile.immunities = [GameplayNames.DAMAGE_POISON]
	assert_almost_eq(
		DamagePipeline.preview(1000.0, [GameplayNames.DAMAGE_POISON], profile), 0.0
	)


func test_immunity_beats_a_vulnerability_to_the_same_tag() -> void:
	# An immunity is absolute, not a 100% resistance a vulnerability can claw
	# back.
	profile.immunities = [GameplayNames.DAMAGE_FIRE]
	profile.vulnerabilities = {GameplayNames.DAMAGE_FIRE: 5.0}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile), 0.0
	)


func test_immunity_to_one_tag_does_not_block_another() -> void:
	profile.immunities = [GameplayNames.DAMAGE_POISON]
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile), 100.0
	)


# --- Extra resistance from stats -----------------------------------------

func test_extra_resistance_stacks_with_the_profile() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.2}
	assert_almost_eq(
		DamagePipeline.preview(100.0, [GameplayNames.DAMAGE_FIRE], profile, 0.3),
		50.0,
		0.0001
	)


func test_extra_resistance_works_with_no_profile() -> void:
	assert_almost_eq(DamagePipeline.preview(100.0, [], null, 0.25), 75.0)


func test_extra_resistance_is_capped_by_the_profile() -> void:
	profile.maximum_resistance = 0.5
	assert_almost_eq(DamagePipeline.preview(100.0, [], profile, 0.99), 50.0, 0.0001)


# --- Applying -------------------------------------------------------------

func test_apply_to_subtracts_the_final_amount() -> void:
	var context := DamagePipeline.mitigate(_context(30.0), profile)
	assert_almost_eq(DamagePipeline.apply_to(100.0, context), 70.0)


func test_health_never_goes_below_zero() -> void:
	var context := DamagePipeline.mitigate(_context(300.0), profile)
	assert_almost_eq(DamagePipeline.apply_to(100.0, context), 0.0)


func test_is_lethal_reports_a_killing_blow() -> void:
	var context := DamagePipeline.mitigate(_context(100.0), profile)
	assert_true(DamagePipeline.is_lethal(100.0, context))
	assert_false(DamagePipeline.is_lethal(101.0, context))


func test_nothing_is_lethal_to_something_already_at_zero() -> void:
	var context := DamagePipeline.mitigate(_context(100.0), profile)
	assert_false(DamagePipeline.is_lethal(0.0, context))


func test_a_fully_absorbed_hit_still_happened() -> void:
	# Zero damage is not an error; armour eating a shot is a real outcome and
	# the context survives to say so.
	profile.flat_armor = 100.0
	var context := DamagePipeline.mitigate(_context(10.0), profile)
	assert_false(context.is_effective())
	assert_almost_eq(context.amount, 10.0, 0.0001, "what was requested is still there")


# --- Profile validation ---------------------------------------------------

func test_a_sensible_profile_validates_clean() -> void:
	profile.flat_armor = 5.0
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.25}
	var result := profile.validate()
	assert_false(result.has_errors())
	assert_false(result.has_warnings())


func test_negative_armour_is_an_error() -> void:
	profile.flat_armor = -5.0
	assert_true(profile.validate().has_errors())


func test_a_negative_resistance_is_a_warning() -> void:
	profile.resistances = {GameplayNames.DAMAGE_FIRE: -0.5}
	assert_true(profile.validate().has_warnings())


func test_an_immunity_that_shadows_a_resistance_is_flagged() -> void:
	profile.immunities = [GameplayNames.DAMAGE_FIRE]
	profile.resistances = {GameplayNames.DAMAGE_FIRE: 0.5}
	var result := profile.validate()
	assert_true(result.has_warnings())
	assert_true(result.format_report().contains("immunity wins"))
