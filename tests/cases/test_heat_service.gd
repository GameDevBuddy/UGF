extends FrameworkTestCase
## Covers CrimeDefinition, WantedTier, HeatProfile and HeatService: what a
## crime costs, what tier it puts you at, and how it wears off.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var heat: HeatService = null
var profile: HeatProfile = null
var assault: CrimeDefinition = null
var offender: Node3D = null
var bystander: Node3D = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	profile = CrimeFixtures.heat_profile()
	heat = CrimeFixtures.heat_service(profile)
	add_test_node(heat)

	assault = CrimeFixtures.crime(&"crime.assault", 25.0, 10.0)
	offender = CrimeFixtures.actor("Offender")
	bystander = CrimeFixtures.actor("Bystander")
	for entity in [offender, bystander]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)


func _report(definition: CrimeDefinition = null, witnesses: Array = []) -> FrameworkResult:
	var seen: Array = witnesses if not witnesses.is_empty() else [bystander]
	return heat.report(
		CrimeFixtures.context(offender, definition if definition != null else assault, null, seen)
	)


# --- Definitions -----------------------------------------------------------

func test_a_costless_crime_is_a_warning() -> void:
	assert_true(CrimeFixtures.crime(&"crime.nothing", 0.0, 0.0).validate().has_warnings())


func test_a_witness_multiplier_below_one_is_an_error() -> void:
	var broken := CrimeFixtures.crime()
	broken.maximum_witness_scale = 0.5
	assert_true(broken.validate().has_errors())


func test_a_crime_that_supersedes_itself_is_an_error() -> void:
	var broken := CrimeFixtures.crime(&"crime.loop")
	var covers: Array[StringName] = [&"crime.loop"]
	broken.supersedes = covers
	assert_true(broken.validate().has_errors())


func test_more_witnesses_make_a_crime_worse() -> void:
	var public := CrimeFixtures.crime(&"crime.affray", 20.0)
	public.witness_scale = 0.5
	public.maximum_witness_scale = 3.0
	assert_almost_eq(public.get_heat_for(1), 20.0, 0.001, "the first is free")
	assert_almost_eq(public.get_heat_for(3), 40.0)


func test_the_witness_multiplier_is_capped() -> void:
	var public := CrimeFixtures.crime(&"crime.affray", 20.0)
	public.witness_scale = 0.5
	public.maximum_witness_scale = 2.0
	assert_almost_eq(public.get_heat_for(100), 40.0)


func test_an_unwitnessed_crime_costs_nothing_unless_it_needs_no_witness() -> void:
	assert_almost_eq(assault.get_heat_for(0), 0.0)
	var speeding := CrimeFixtures.crime(&"crime.speeding", 5.0, 0.0, false)
	assert_almost_eq(speeding.get_heat_for(0), 5.0, 0.001, "a camera saw it")


# --- Ladders ---------------------------------------------------------------

func test_a_ladder_with_no_tiers_is_an_error() -> void:
	var empty := HeatProfile.new()
	assert_true(empty.validate().has_errors())


func test_a_tier_is_resolved_by_threshold() -> void:
	assert_null(profile.resolve_tier(10.0), "below the first rung")
	assert_eq(profile.resolve_tier(20.0).state, &"state.suspected")
	assert_eq(profile.resolve_tier(49.0).state, &"state.suspected")
	assert_eq(profile.resolve_tier(50.0).state, GameplayNames.STATE_WANTED)
	assert_eq(profile.resolve_tier(500.0).state, &"state.hunted")


func test_authoring_order_does_not_change_behaviour() -> void:
	var shuffled := HeatProfile.new()
	var rungs: Array[WantedTier] = [
		CrimeFixtures.tier(&"state.hunted", 100.0),
		CrimeFixtures.tier(&"state.suspected", 20.0),
		CrimeFixtures.tier(GameplayNames.STATE_WANTED, 50.0),
	]
	shuffled.tiers = rungs
	assert_eq(shuffled.resolve_tier(60.0).state, GameplayNames.STATE_WANTED)


func test_the_next_threshold_is_reported() -> void:
	assert_almost_eq(profile.get_next_threshold(30.0), 50.0)
	assert_almost_eq(profile.get_next_threshold(500.0), 0.0, 0.001, "nothing above")


func test_duplicate_thresholds_are_a_warning() -> void:
	var muddled := HeatProfile.new()
	var rungs: Array[WantedTier] = [
		CrimeFixtures.tier(&"state.a", 50.0),
		CrimeFixtures.tier(&"state.b", 50.0),
	]
	muddled.tiers = rungs
	assert_true(muddled.validate().has_warnings())


func test_a_ceiling_below_the_top_tier_is_a_warning() -> void:
	profile.maximum_heat = 60.0
	assert_true(profile.validate().has_warnings())


func test_heat_is_capped_at_the_ceiling() -> void:
	profile.maximum_heat = 70.0
	heat.add_heat(&"offender", &"faction.police", 500.0)
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 70.0)


# --- Reporting -------------------------------------------------------------

func test_a_witnessed_crime_raises_heat() -> void:
	assert_ok(_report())
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 25.0)


func test_an_unwitnessed_crime_is_refused() -> void:
	# The whole fantasy of a stealth game.
	assert_err(
		heat.report(CrimeFixtures.context(offender, assault)), &"crime.unwitnessed"
	)
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 0.0)


func test_a_crime_needing_no_witness_goes_through_unseen() -> void:
	var speeding := CrimeFixtures.crime(&"crime.speeding", 5.0, 0.0, false)
	assert_ok(heat.report(CrimeFixtures.context(offender, speeding)))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 5.0)


func test_a_perpetrator_with_no_identity_is_refused() -> void:
	var nobody := Node3D.new()
	nobody.name = "Nobody"
	add_test_node(nobody)
	assert_err(
		heat.report(CrimeFixtures.context(nobody, assault, null, [bystander])),
		&"crime.no_identity"
	)


func test_a_crime_with_no_jurisdiction_is_refused() -> void:
	var stateless := CrimeFixtures.crime(&"crime.rude")
	stateless.law_faction = &""
	assert_err(
		heat.report(CrimeFixtures.context(offender, stateless, null, [bystander])),
		&"crime.no_jurisdiction"
	)


func test_a_faction_with_no_ladder_is_refused() -> void:
	var elsewhere := CrimeFixtures.crime(&"crime.trespass")
	elsewhere.law_faction = &"faction.militia"
	heat.set_profile(&"", null)
	assert_err(
		heat.report(CrimeFixtures.context(offender, elsewhere, null, [bystander])),
		&"crime.no_profile"
	)


func test_a_disabled_service_accepts_nothing() -> void:
	heat.enabled = false
	assert_err(_report(), &"crime.disabled")


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array = []
	heat.crime_rejected.connect(
		func(_context: CrimeContext, reason: StringName) -> void: refusals.append(reason)
	)
	assert_err(heat.report(CrimeFixtures.context(offender, assault)), &"crime.unwitnessed")
	assert_eq(refusals, [&"crime.unwitnessed"])


func test_a_refusal_costs_nothing() -> void:
	heat.add_heat(&"offender", &"faction.police", 30.0)
	assert_err(heat.report(CrimeFixtures.context(offender, assault)), &"crime.unwitnessed")
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 30.0)


func test_an_accepted_crime_is_announced() -> void:
	var reported: Array = []
	heat.crime_reported.connect(
		func(context: CrimeContext) -> void:
			reported.append([context.actor_id, context.get_crime_id()])
	)
	assert_ok(_report())
	assert_eq(reported, [[&"offender", &"crime.assault"]])


func test_a_worse_crime_supersedes_a_lesser_one() -> void:
	# Reporting a murder should not also charge the assault that preceded it.
	var murder := CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	var covers: Array[StringName] = [&"crime.assault"]
	murder.supersedes = covers

	assert_ok(_report(murder))
	assert_err(_report(assault), &"crime.superseded")
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 60.0)


func test_a_lesser_crime_first_does_not_block_the_worse_one() -> void:
	var murder := CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	var covers: Array[StringName] = [&"crime.assault"]
	murder.supersedes = covers

	assert_ok(_report(assault))
	assert_ok(_report(murder))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 85.0)


# --- Wanted state ----------------------------------------------------------

func test_crossing_a_rung_is_announced_once() -> void:
	var crossings: Array = []
	heat.wanted_changed.connect(
		func(_actor: StringName, _faction: StringName, tier: WantedTier) -> void:
			crossings.append(tier.state if tier != null else &"")
	)
	heat.add_heat(&"offender", &"faction.police", 25.0)
	heat.add_heat(&"offender", &"faction.police", 5.0)
	assert_eq(crossings, [&"state.suspected"], "one crossing, not one per point")

	heat.add_heat(&"offender", &"faction.police", 25.0)
	assert_eq(crossings, [&"state.suspected", GameplayNames.STATE_WANTED])


func test_being_wanted_is_a_semantic_state_not_a_number() -> void:
	# The whole interface to law AI.
	heat.add_heat(&"offender", &"faction.police", 60.0)
	assert_true(heat.is_wanted(&"offender", &"faction.police"))
	assert_eq(heat.get_tier(&"offender", &"faction.police").state, GameplayNames.STATE_WANTED)
	assert_has(heat.get_wanted_states(&"offender"), GameplayNames.STATE_WANTED)


func test_two_factions_can_want_you_independently() -> void:
	# And a guard of one should not care about the other's warrant.
	heat.add_heat(&"offender", &"faction.police", 60.0)
	heat.add_heat(&"offender", &"faction.militia", 10.0)
	assert_true(heat.is_wanted(&"offender", &"faction.police"))
	assert_false(heat.is_wanted(&"offender", &"faction.militia"))
	assert_eq(heat.get_wanted_factions(&"offender"), [&"faction.police"])
	assert_true(heat.is_wanted_anywhere(&"offender"))


func test_the_distance_to_the_next_rung_is_reported() -> void:
	# What every wanted UI wants and nobody should re-derive.
	heat.add_heat(&"offender", &"faction.police", 30.0)
	assert_almost_eq(heat.get_heat_to_next_tier(&"offender", &"faction.police"), 20.0)


func test_clearing_heat_clears_the_warrant() -> void:
	heat.add_heat(&"offender", &"faction.police", 60.0)
	assert_true(heat.clear_heat(&"offender", &"faction.police"))
	assert_false(heat.is_wanted(&"offender", &"faction.police"))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 0.0)


func test_clearing_is_announced() -> void:
	var cleared: Array = []
	heat.cleared.connect(
		func(actor: StringName, faction: StringName) -> void: cleared.append([actor, faction])
	)
	heat.add_heat(&"offender", &"faction.police", 60.0)
	heat.clear_heat(&"offender", &"faction.police")
	assert_eq(cleared, [[&"offender", &"faction.police"]])


func test_clearing_an_actor_clears_every_warrant() -> void:
	heat.add_heat(&"offender", &"faction.police", 60.0)
	heat.add_heat(&"offender", &"faction.militia", 60.0)
	heat.clear_actor(&"offender")
	assert_false(heat.is_wanted_anywhere(&"offender"))
	assert_almost_eq(heat.get_total_heat(&"offender"), 0.0)


func test_a_cleared_actor_can_offend_again() -> void:
	# Being pardoned is not being immune. The record is wiped with the heat.
	var murder := CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	var covers: Array[StringName] = [&"crime.assault"]
	murder.supersedes = covers
	assert_ok(_report(murder))
	heat.clear_actor(&"offender")
	assert_ok(_report(assault))


# --- Cooling off -----------------------------------------------------------

func test_heat_decays_over_time() -> void:
	heat.add_heat(&"offender", &"faction.police", 60.0)
	heat.tick(10.0)
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 50.0)


func test_decaying_below_a_rung_drops_the_tier() -> void:
	# Down a rung, not off the ladder. is_wanted() means the law is looking at
	# you in some capacity, and "suspected" is still a capacity -- what changes
	# is which state law AI sees.
	heat.add_heat(&"offender", &"faction.police", 55.0)
	assert_eq(
		heat.get_tier(&"offender", &"faction.police").state, GameplayNames.STATE_WANTED
	)
	heat.tick(10.0)
	assert_eq(heat.get_tier(&"offender", &"faction.police").state, &"state.suspected")
	assert_true(heat.is_wanted(&"offender", &"faction.police"), "still of interest")


func test_decaying_off_the_ladder_entirely_clears_the_warrant() -> void:
	heat.add_heat(&"offender", &"faction.police", 25.0)
	assert_true(heat.is_wanted(&"offender", &"faction.police"))
	heat.tick(30.0)
	assert_null(heat.get_tier(&"offender", &"faction.police"))
	assert_false(heat.is_wanted(&"offender", &"faction.police"))


func test_a_cooldown_delay_stops_a_murderer_cooling_off_in_four_seconds() -> void:
	var patient := HeatProfile.new()
	var rungs: Array[WantedTier] = [
		CrimeFixtures.tier(GameplayNames.STATE_WANTED, 50.0, 30.0)
	]
	patient.tiers = rungs
	patient.decay_per_second = 1.0
	heat.set_profile(&"", patient)

	heat.add_heat(&"offender", &"faction.police", 60.0)
	heat.tick(10.0)
	assert_almost_eq(
		heat.get_heat(&"offender", &"faction.police"), 60.0, 0.001, "still hunted"
	)
	heat.tick(25.0)
	assert_true(heat.get_heat(&"offender", &"faction.police") < 60.0)


func test_a_new_crime_restarts_the_cooldown() -> void:
	var patient := HeatProfile.new()
	var rungs: Array[WantedTier] = [
		CrimeFixtures.tier(GameplayNames.STATE_WANTED, 20.0, 30.0)
	]
	patient.tiers = rungs
	patient.decay_per_second = 1.0
	heat.set_profile(&"", patient)

	assert_ok(_report())
	heat.tick(25.0)
	assert_ok(_report(CrimeFixtures.crime(&"crime.theft", 25.0, 5.0)))
	heat.tick(25.0)
	assert_almost_eq(
		heat.get_heat(&"offender", &"faction.police"), 50.0, 0.001,
		"the second offence reset the clock"
	)


func test_heat_above_the_permanent_threshold_never_cools() -> void:
	profile.permanent_above = 90.0
	heat.add_heat(&"offender", &"faction.police", 100.0)
	heat.tick(1000.0)
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 100.0)


func test_decay_never_goes_below_zero() -> void:
	heat.add_heat(&"offender", &"faction.police", 5.0)
	heat.tick(1000.0)
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 0.0)


func test_the_service_does_not_process_every_frame() -> void:
	# Heat is exactly the low-rate simulation the plan says to tick, not frame.
	assert_false(heat.is_processing())
	assert_false(heat.is_physics_processing())


# --- Persistence -----------------------------------------------------------

func test_being_wanted_survives_a_save() -> void:
	# A save that forgot would be the cheapest possible escape from the police.
	assert_ok(_report())
	heat.add_heat(&"offender", &"faction.militia", 15.0)
	var saved := heat.capture_state()

	var other := CrimeFixtures.heat_service(profile)
	add_test_node(other)
	other.restore_state(saved)

	assert_true(heat.is_persistent())
	assert_almost_eq(other.get_heat(&"offender", &"faction.police"), 25.0)
	assert_almost_eq(other.get_heat(&"offender", &"faction.militia"), 15.0)


func test_a_criminal_record_survives_a_save() -> void:
	var murder := CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	var covers: Array[StringName] = [&"crime.assault"]
	murder.supersedes = covers
	assert_ok(_report(murder))
	var saved := heat.capture_state()

	var other := CrimeFixtures.heat_service(profile)
	add_test_node(other)
	other.restore_state(saved)
	other.learn(murder)

	assert_err(
		other.report(CrimeFixtures.context(offender, assault, null, [bystander])),
		&"crime.superseded"
	)


func test_a_restored_actor_is_still_wanted() -> void:
	heat.add_heat(&"offender", &"faction.police", 60.0)
	var saved := heat.capture_state()

	var other := CrimeFixtures.heat_service(profile)
	add_test_node(other)
	other.restore_state(saved)
	assert_true(other.is_wanted(&"offender", &"faction.police"))
