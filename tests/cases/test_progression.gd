extends FrameworkTestCase
## Covers the Progression module: XP tracks, levels, skill points and perk
## unlock hooks (Implementation Plan 12).
##
## This module exists because the M0-M19 milestone roadmap never listed the
## plan's Progression section, and nobody noticed until the shooter-RPG slice
## gate asked for the XP leg and found nothing to call.

var hero: Node3D = null
var progression: ProgressionComponent = null
var stats: StatsComponent = null


func before_each() -> void:
	hero = ProgressionFixtures.hero()
	add_test_node(hero)
	ProgressionFixtures.assemble(hero)
	progression = ProgressionFixtures.progression_of(hero)
	stats = ProgressionFixtures.stats_of(hero)


# --- Curves ---------------------------------------------------------------

func test_a_linear_track_costs_the_same_every_level() -> void:
	var track := ProgressionFixtures.track(&"t", 5, 100.0)
	assert_eq(track.get_threshold(1), 0.0, "Level one is where a character starts")
	assert_eq(track.get_threshold(2), 100.0)
	assert_eq(track.get_threshold(3), 200.0)
	assert_eq(track.get_threshold(5), 400.0)


func test_a_geometric_track_sums_its_costs_rather_than_taking_the_nth_term() -> void:
	# The bug this guards: the threshold is what it costs to have *reached* a
	# level, so it is the running total. Taking the nth term instead makes
	# level 5 cost 1600 instead of 3100 -- wrong only at high level, by which
	# point somebody's save has the wrong number in it.
	var track := ProgressionFixtures.geometric_track(&"t", 5, 100.0, 2.0)
	assert_eq(track.get_threshold(2), 100.0, "100")
	assert_eq(track.get_threshold(3), 300.0, "100 + 200")
	assert_eq(track.get_threshold(4), 700.0, "100 + 200 + 400")
	assert_eq(track.get_threshold(5), 1500.0, "100 + 200 + 400 + 800")


func test_an_explicit_track_reads_its_thresholds() -> void:
	var costs: Array[float] = [50.0, 500.0, 5000.0]
	var track := ProgressionFixtures.explicit_track(costs)
	assert_eq(track.get_threshold(2), 50.0)
	assert_eq(track.get_threshold(3), 500.0)
	assert_eq(track.get_threshold(4), 5000.0)


func test_a_curve_reports_the_level_an_amount_buys() -> void:
	var track := ProgressionFixtures.track(&"t", 5, 100.0)
	assert_eq(track.get_level_for(0.0), 1)
	assert_eq(track.get_level_for(99.0), 1, "One short is still level one")
	assert_eq(track.get_level_for(100.0), 2)
	assert_eq(track.get_level_for(1000.0), 5, "Clamped to the maximum")


func test_the_fraction_through_a_level_is_reported_for_a_progress_bar() -> void:
	var track := ProgressionFixtures.track(&"t", 5, 100.0)
	assert_almost_eq(track.get_fraction(150.0), 0.5)
	assert_eq(track.get_fraction(400.0), 1.0, "A finished track draws a full bar")


# --- Awarding -------------------------------------------------------------

func test_experience_accumulates_and_levels() -> void:
	assert_eq(progression.get_level(&"track.hero"), 1)
	assert_ok(progression.award(&"track.hero", 250.0))
	assert_eq(progression.get_experience(&"track.hero"), 250.0)
	assert_eq(progression.get_level(&"track.hero"), 3)


func test_every_level_crossed_is_announced_in_order() -> void:
	# One award crossing three boundaries must report 2, 3, 4 -- not one jump
	# from 1 to 4. A listener granting a reward per level would pay out once.
	var seen: Array[int] = []
	progression.level_gained.connect(
		func(_track: StringName, level: int, _previous: int) -> void: seen.append(level)
	)

	progression.award(&"track.hero", 350.0)

	assert_eq(seen, [2, 3, 4] as Array[int])


func test_points_are_granted_for_each_level() -> void:
	progression.award(&"track.hero", 300.0)
	assert_eq(progression.get_level(&"track.hero"), 4)
	assert_eq(progression.get_unspent_points(&"track.hero"), 3, "Three levels gained")


func test_experience_stops_at_the_top_rather_than_growing_forever() -> void:
	progression.award(&"track.hero", 10000.0)
	assert_eq(progression.get_level(&"track.hero"), 5)
	assert_eq(
		progression.get_experience(&"track.hero"),
		400.0,
		"Experience past the last level would be a number that only grows"
	)


func test_a_mastered_track_refuses_further_awards() -> void:
	progression.award(&"track.hero", 400.0)
	assert_err(progression.award(&"track.hero", 100.0), &"progression.track_mastered")


func test_an_unknown_track_is_refused_rather_than_silently_created() -> void:
	assert_err(progression.award(&"track.nothing", 10.0), &"progression.unknown_track")


func test_a_non_positive_award_is_refused() -> void:
	assert_err(progression.award(&"track.hero", 0.0), &"progression.not_an_award")
	assert_err(progression.award(&"track.hero", -50.0), &"progression.not_an_award")


func test_mastering_a_track_sets_its_state_and_announces_it() -> void:
	var track := ProgressionFixtures.track(&"track.hero", 2, 100.0)
	track.mastered_state = &"state.master"
	var entity := ProgressionFixtures.hero(ProgressionFixtures.profile([track]))
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)

	var mastered: Array[StringName] = []
	var component := ProgressionFixtures.progression_of(entity)
	component.track_mastered.connect(
		func(id: StringName) -> void: mastered.append(id)
	)
	component.award(&"track.hero", 100.0)

	assert_eq(mastered, [&"track.hero"] as Array[StringName])
	assert_true(ProgressionFixtures.state_of(entity).has_state(&"state.master"))


func test_a_track_can_raise_a_stat_every_level() -> void:
	var track := ProgressionFixtures.track(&"track.hero", 5, 100.0)
	track.stat_per_level_id = &"stat.power"
	track.stat_per_level = 2.0
	var entity := ProgressionFixtures.hero(ProgressionFixtures.profile([track]))
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)

	ProgressionFixtures.progression_of(entity).award(&"track.hero", 200.0)

	assert_eq(
		ProgressionFixtures.stats_of(entity).get_base(&"stat.power"),
		14.0,
		"Base ten plus two levels at two each"
	)


func test_a_character_with_no_stats_still_levels() -> void:
	# Rule 31: a missing optional module is a valid state. An NPC that levels
	# but carries no numbers is a perfectly ordinary NPC.
	var entity := ProgressionFixtures.hero(null, false)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)

	var component := ProgressionFixtures.progression_of(entity)
	assert_ok(component.award(&"track.hero", 250.0))
	assert_eq(component.get_level(&"track.hero"), 3)
	assert_eq(component.get_unspent_points(&"track.hero"), 2)


func test_a_character_can_start_above_the_first_level() -> void:
	var track := ProgressionFixtures.track(&"track.hero", 10, 100.0)
	track.starting_level = 5
	var entity := ProgressionFixtures.hero(ProgressionFixtures.profile([track]))
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)

	var component := ProgressionFixtures.progression_of(entity)
	assert_eq(component.get_level(&"track.hero"), 5)
	assert_eq(
		component.get_unspent_points(&"track.hero"),
		4,
		"Four levels' worth already earned"
	)


func test_a_level_can_be_set_directly() -> void:
	assert_ok(progression.set_level(&"track.hero", 4))
	assert_eq(progression.get_level(&"track.hero"), 4)
	assert_eq(progression.get_unspent_points(&"track.hero"), 3)


func test_setting_a_level_down_does_not_claw_back_spent_points() -> void:
	# The points may already be spent, and a refund that cannot be paid would
	# leave a negative balance nothing could spend out of.
	progression.set_level(&"track.hero", 4)
	progression.set_level(&"track.hero", 2)
	assert_eq(progression.get_level(&"track.hero"), 2)
	assert_eq(progression.get_unspent_points(&"track.hero"), 3)


# --- Skills ---------------------------------------------------------------

func _skilled(skills: Array, starting: Array = []) -> ProgressionComponent:
	var entity := ProgressionFixtures.hero(
		ProgressionFixtures.profile([ProgressionFixtures.track()], skills, starting)
	)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)
	return ProgressionFixtures.progression_of(entity)


func test_a_skill_costs_points_and_grants_its_modifiers() -> void:
	var entity := ProgressionFixtures.hero(
		ProgressionFixtures.profile(
			[ProgressionFixtures.track()], [ProgressionFixtures.buffing_skill(&"skill.strong")]
		)
	)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)
	var component := ProgressionFixtures.progression_of(entity)
	var numbers := ProgressionFixtures.stats_of(entity)

	component.award(&"track.hero", 100.0)
	assert_eq(numbers.get_value(&"stat.power"), 10.0, "Before")

	assert_ok(component.unlock(&"skill.strong"))

	assert_true(component.has_skill(&"skill.strong"))
	assert_eq(component.get_unspent_points(&"track.hero"), 0, "The point was spent")
	assert_eq(numbers.get_value(&"stat.power"), 15.0, "After")


func test_a_skill_below_its_level_requirement_is_refused() -> void:
	var component := _skilled([ProgressionFixtures.skill(&"skill.late", &"track.hero", 3)])
	component.award(&"track.hero", 100.0)
	assert_err(component.unlock(&"skill.late"), &"progression.level_too_low")


func test_a_skill_with_no_points_to_pay_for_it_is_refused() -> void:
	var component := _skilled([ProgressionFixtures.skill(&"skill.any")])
	assert_err(component.unlock(&"skill.any"), &"progression.not_enough_points")


func test_a_skill_missing_its_prerequisite_is_refused() -> void:
	var basic := ProgressionFixtures.skill(&"skill.basic")
	var advanced := ProgressionFixtures.skill(&"skill.advanced")
	var required: Array[StringName] = [&"skill.basic"]
	advanced.requires_skills = required

	var component := _skilled([basic, advanced])
	component.award(&"track.hero", 200.0)

	assert_err(component.unlock(&"skill.advanced"), &"progression.missing_prerequisite")
	assert_ok(component.unlock(&"skill.basic"))
	assert_ok(component.unlock(&"skill.advanced"))


func test_a_conflict_is_honoured_from_either_side() -> void:
	# Only one side of a branch has to declare the exclusion, so a designer
	# cannot half-author it and get a character holding both.
	var light := ProgressionFixtures.skill(&"skill.light")
	var heavy := ProgressionFixtures.skill(&"skill.heavy")
	var conflicts: Array[StringName] = [&"skill.heavy"]
	light.conflicts_with = conflicts

	var component := _skilled([light, heavy])
	component.award(&"track.hero", 400.0)

	assert_ok(component.unlock(&"skill.heavy"))
	assert_err(component.unlock(&"skill.light"), &"progression.conflicting_skill")


func test_a_skill_gated_on_a_flag_waits_for_it() -> void:
	var narrative := NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)

	var gated := ProgressionFixtures.skill(&"skill.secret")
	var flags: Array[StringName] = [&"flag.taught"]
	gated.required_flags = flags

	var entity := ProgressionFixtures.hero(
		ProgressionFixtures.profile([ProgressionFixtures.track()], [gated]), true, narrative
	)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)
	var component := ProgressionFixtures.progression_of(entity)
	component.award(&"track.hero", 100.0)

	assert_err(component.unlock(&"skill.secret"), &"progression.flag_not_set")
	narrative.set_flag(&"flag.taught")
	assert_ok(component.unlock(&"skill.secret"))


func test_unlocking_the_same_skill_twice_is_refused() -> void:
	var component := _skilled([ProgressionFixtures.skill(&"skill.once")])
	component.award(&"track.hero", 200.0)
	assert_ok(component.unlock(&"skill.once"))
	assert_err(component.unlock(&"skill.once"), &"progression.already_unlocked")


func test_starting_skills_are_held_without_paying_for_them() -> void:
	var component := _skilled(
		[ProgressionFixtures.skill(&"skill.innate", &"track.hero", 5, 3)], [&"skill.innate"]
	)
	assert_true(component.has_skill(&"skill.innate"), "Granted despite level and cost")
	assert_eq(component.get_unspent_points(&"track.hero"), 0, "And nothing was spent")


func test_available_skills_are_the_ones_that_could_be_taken_now() -> void:
	var cheap := ProgressionFixtures.skill(&"skill.cheap", &"track.hero", 1, 1)
	var dear := ProgressionFixtures.skill(&"skill.dear", &"track.hero", 4, 1)
	var component := _skilled([cheap, dear])
	component.award(&"track.hero", 100.0)

	var available := component.get_available_skills()
	assert_has(available, &"skill.cheap")
	assert_has_not(available, &"skill.dear")


# --- Refunds --------------------------------------------------------------

func test_a_refund_takes_back_exactly_what_the_skill_gave() -> void:
	# Removal is by source, and the source is the skill's own id, so two
	# skills buffing the same stat cannot take back each other's contribution.
	var first := ProgressionFixtures.buffing_skill(&"skill.first", &"stat.power", 5.0)
	var second := ProgressionFixtures.buffing_skill(&"skill.second", &"stat.power", 3.0)
	var entity := ProgressionFixtures.hero(
		ProgressionFixtures.profile([ProgressionFixtures.track()], [first, second])
	)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)
	var component := ProgressionFixtures.progression_of(entity)
	var numbers := ProgressionFixtures.stats_of(entity)

	component.award(&"track.hero", 400.0)
	component.unlock(&"skill.first")
	component.unlock(&"skill.second")
	assert_eq(numbers.get_value(&"stat.power"), 18.0)

	assert_ok(component.refund(&"skill.first"))

	assert_eq(numbers.get_value(&"stat.power"), 13.0, "Only the first was taken back")
	assert_false(component.has_skill(&"skill.first"))
	assert_true(component.has_skill(&"skill.second"))


func test_a_refund_returns_the_points() -> void:
	var component := _skilled([ProgressionFixtures.skill(&"skill.costly", &"track.hero", 1, 2)])
	component.award(&"track.hero", 300.0)
	component.unlock(&"skill.costly")
	assert_eq(component.get_unspent_points(&"track.hero"), 1)

	component.refund(&"skill.costly")

	assert_eq(component.get_unspent_points(&"track.hero"), 3)


func test_a_skill_something_else_depends_on_cannot_be_refunded() -> void:
	var basic := ProgressionFixtures.skill(&"skill.basic")
	var advanced := ProgressionFixtures.skill(&"skill.advanced")
	var required: Array[StringName] = [&"skill.basic"]
	advanced.requires_skills = required

	var component := _skilled([basic, advanced])
	component.award(&"track.hero", 400.0)
	component.unlock(&"skill.basic")
	component.unlock(&"skill.advanced")

	assert_err(component.refund(&"skill.basic"), &"progression.has_dependents")


func test_refunding_something_not_held_is_refused() -> void:
	var component := _skilled([ProgressionFixtures.skill(&"skill.any")])
	assert_err(component.refund(&"skill.any"), &"progression.not_unlocked")


# --- Persistence ----------------------------------------------------------

func test_experience_points_and_skills_survive_a_round_trip() -> void:
	var build := func() -> Node3D:
		var entity := ProgressionFixtures.hero(
			ProgressionFixtures.profile(
				[ProgressionFixtures.track()],
				[ProgressionFixtures.buffing_skill(&"skill.strong", &"stat.power", 5.0)]
			)
		)
		add_test_node(entity)
		ProgressionFixtures.assemble(entity)
		return entity

	var before := build.call() as Node3D
	var source := ProgressionFixtures.progression_of(before)
	source.award(&"track.hero", 250.0)
	source.unlock(&"skill.strong")
	var saved := source.capture_state()

	var after := build.call() as Node3D
	var restored := ProgressionFixtures.progression_of(after)
	restored.restore_state(saved)

	assert_eq(restored.get_experience(&"track.hero"), 250.0)
	assert_eq(restored.get_level(&"track.hero"), 3)
	assert_eq(restored.get_unspent_points(&"track.hero"), 1)
	assert_true(restored.has_skill(&"skill.strong"))


func test_a_restore_does_not_apply_a_skills_bonus_twice() -> void:
	# The trap EquipmentComponent and StatusEffectComponent both avoid: saving
	# the modifiers as well as the fact would double every bonus on load.
	var entity := ProgressionFixtures.hero(
		ProgressionFixtures.profile(
			[ProgressionFixtures.track()],
			[ProgressionFixtures.buffing_skill(&"skill.strong", &"stat.power", 5.0)]
		)
	)
	add_test_node(entity)
	ProgressionFixtures.assemble(entity)
	var component := ProgressionFixtures.progression_of(entity)
	var numbers := ProgressionFixtures.stats_of(entity)

	component.award(&"track.hero", 100.0)
	component.unlock(&"skill.strong")
	assert_eq(numbers.get_value(&"stat.power"), 15.0)

	component.restore_state(component.capture_state())

	assert_eq(numbers.get_value(&"stat.power"), 15.0, "Not 20")


func test_a_restored_level_is_derived_from_experience_rather_than_saved() -> void:
	# Two numbers that must agree are one number that can disagree. The curve
	# is the authority on which level an amount of experience buys.
	var saved := {"experience": {"track.hero": 250.0}, "points": {}, "skills": []}
	progression.restore_state(saved)
	assert_eq(progression.get_level(&"track.hero"), 3)


# --- Content validation ---------------------------------------------------

func test_a_profile_rejects_two_tracks_with_one_id() -> void:
	var built := ProgressionFixtures.profile(
		[ProgressionFixtures.track(&"track.same"), ProgressionFixtures.track(&"track.same")]
	)
	assert_true(built.validate().has_errors())


func test_a_profile_rejects_a_skill_whose_track_it_does_not_carry() -> void:
	var orphan := ProgressionFixtures.skill(&"skill.lost", &"track.elsewhere")
	var built := ProgressionFixtures.profile([ProgressionFixtures.track()], [orphan])
	assert_true(built.validate().has_errors())


func test_a_profile_rejects_a_prerequisite_cycle() -> void:
	# A cycle is not a slow unlock, it is an unreachable one, and it reads as
	# "the skill just does nothing" until somebody traces the chain by hand.
	var first := ProgressionFixtures.skill(&"skill.a")
	var second := ProgressionFixtures.skill(&"skill.b")
	var needs_b: Array[StringName] = [&"skill.b"]
	var needs_a: Array[StringName] = [&"skill.a"]
	first.requires_skills = needs_b
	second.requires_skills = needs_a

	var built := ProgressionFixtures.profile([ProgressionFixtures.track()], [first, second])
	var result := built.validate()

	assert_true(result.has_errors())
	assert_true(result.format_report().contains("require each other"), result.format_report())


func test_a_track_starting_above_its_maximum_is_rejected() -> void:
	var track := ProgressionFixtures.track(&"track.odd", 3)
	track.starting_level = 9
	assert_true(track.validate().has_errors())


func test_explicit_thresholds_that_do_not_ascend_are_rejected() -> void:
	var costs: Array[float] = [100.0, 50.0]
	assert_true(ProgressionFixtures.explicit_track(costs).validate().has_errors())


func test_a_skill_that_requires_and_conflicts_with_the_same_thing_is_rejected() -> void:
	var contradictory := ProgressionFixtures.skill(&"skill.impossible")
	var both: Array[StringName] = [&"skill.other"]
	contradictory.requires_skills = both
	contradictory.conflicts_with = both
	assert_true(contradictory.validate().has_errors())
