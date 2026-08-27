extends FrameworkTestCase
## Covers WitnessComponent, CrimeContext, CombatCrimeAdapter and
## CrimeEventAdapter: who tells, who does not, and what the world hears.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var core: Node = null
var heat: HeatService = null
var assault: CrimeDefinition = null
var offender: Node3D = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	heat = CrimeFixtures.heat_service()
	add_test_node(heat)
	core.register_service(GameplayNames.SERVICE_CRIME, heat)

	assault = CrimeFixtures.crime(&"crime.assault", 25.0, 10.0)
	offender = CrimeFixtures.actor("Offender")
	add_test_node(offender)
	CrimeFixtures.assemble(offender, core)


func _witness(
	entity_name: String = "Bystander",
	sight_range: float = 0.0,
	position: Vector3 = Vector3.ZERO
) -> WitnessComponent:
	var entity := CrimeFixtures.witness(entity_name, heat, sight_range)
	entity.position = position
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	return CrimeFixtures.witness_of(entity)


# --- The context -----------------------------------------------------------

func test_a_context_counts_its_witnesses() -> void:
	var one := CrimeFixtures.actor("One")
	var two := CrimeFixtures.actor("Two")
	add_test_node(one)
	add_test_node(two)
	var context := CrimeFixtures.context(offender, assault, null, [one, two])
	assert_eq(context.get_witness_count(), 2)
	assert_true(context.has_witnesses())


func test_the_same_witness_twice_counts_once() -> void:
	var one := CrimeFixtures.actor("One")
	add_test_node(one)
	var context := CrimeFixtures.context(offender, assault, null, [one])
	assert_false(context.add_witness(one))
	assert_eq(context.get_witness_count(), 1)


func test_the_perpetrator_cannot_witness_their_own_crime() -> void:
	# Otherwise a witness component on the player reports the player to the
	# police for the player's own crimes, which is funny exactly once.
	var context := CrimeFixtures.context(offender, assault)
	assert_false(context.add_witness(offender))
	assert_false(context.has_witnesses())


func test_a_freed_witness_stops_counting() -> void:
	var one := CrimeFixtures.actor("One")
	add_test_node(one)
	var context := CrimeFixtures.context(offender, assault, null, [one])
	one.get_parent().remove_child(one)
	one.free()
	assert_eq(context.get_witness_count(), 0)


func test_a_context_reports_whether_it_is_reportable() -> void:
	assert_false(CrimeFixtures.context(offender, assault).is_reportable())
	assert_false(CrimeFixtures.context(null, assault).is_reportable())
	var camera := CrimeFixtures.crime(&"crime.speeding", 5.0, 0.0, false)
	assert_true(CrimeFixtures.context(offender, camera).is_reportable())


# --- Reporting -------------------------------------------------------------

func test_a_witness_reports_what_it_sees() -> void:
	var bystander := _witness()
	assert_ok(bystander.witness(offender, assault))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 25.0)


func test_a_witness_out_of_range_says_nothing() -> void:
	var far := _witness("Far", 10.0, Vector3(100.0, 0.0, 0.0))
	assert_err(far.witness(offender, assault), &"witness.did_not_see")
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 0.0)


func test_a_witness_in_range_does_see() -> void:
	var near := _witness("Near", 10.0, Vector3(5.0, 0.0, 0.0))
	assert_ok(near.witness(offender, assault))


func test_a_silenced_witness_says_nothing() -> void:
	# Silencing a witness is what a stealth game is, and the law never has to
	# know about it.
	var entity := CrimeFixtures.witness("Guard", heat)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	var component := CrimeFixtures.witness_of(entity)
	var state := CrimeFixtures.find(entity, SemanticState) as SemanticState

	state.set_state(GameplayNames.STATE_DEAD, true)
	assert_true(component.is_silenced())
	assert_err(component.witness(offender, assault), &"witness.silenced")
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 0.0)


func test_a_downed_witness_is_silenced_too() -> void:
	var entity := CrimeFixtures.witness("Guard", heat)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	var state := CrimeFixtures.find(entity, SemanticState) as SemanticState
	state.set_state(GameplayNames.STATE_DOWNED, true)
	assert_true(CrimeFixtures.witness_of(entity).is_silenced())


func test_a_witness_never_reports_itself() -> void:
	var entity := CrimeFixtures.witness("Player", heat)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	var component := CrimeFixtures.witness_of(entity)
	assert_err(component.witness(entity, assault), &"witness.self")


func test_a_witness_cools_down_between_reports() -> void:
	# One brawl is not fifty reports.
	var entity := CrimeFixtures.witness("Bystander", heat)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	var component := CrimeFixtures.witness_of(entity)
	component.report_cooldown = 5.0

	assert_ok(component.witness(offender, assault))
	assert_err(component.witness(offender, assault), &"witness.cooling_down")
	component.tick(5.0)
	assert_true(component.is_ready())
	assert_ok(component.witness(offender, CrimeFixtures.crime(&"crime.theft", 10.0)))


func test_a_withheld_report_is_announced_with_its_reason() -> void:
	# What a stealth HUD shows: "he didn't see you".
	var withheld: Array = []
	var far := _witness("Far", 10.0, Vector3(100.0, 0.0, 0.0))
	far.report_withheld.connect(
		func(_context: CrimeContext, reason: StringName) -> void: withheld.append(reason)
	)
	assert_err(far.witness(offender, assault), &"witness.did_not_see")
	assert_eq(withheld, [&"witness.did_not_see"])


func test_a_witness_with_no_law_to_report_to_refuses_cleanly() -> void:
	var entity := CrimeFixtures.witness("Bystander", null)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, null)
	assert_err(
		CrimeFixtures.witness_of(entity).witness(offender, assault), &"witness.no_service"
	)


func test_a_witness_only_reporting_for_its_own_faction_ignores_the_rest() -> void:
	var factions := CrimeFixtures.factions()
	add_test_node(factions)
	var entity := CrimeFixtures.witness(
		"Thief", heat, 0.0, &"faction.thieves", factions
	)
	add_test_node(entity)
	CrimeFixtures.assemble(entity, core)
	var component := CrimeFixtures.witness_of(entity)
	component.reports_for_others = false

	assert_err(component.witness(offender, assault), &"witness.not_their_business")

	var theirs := CrimeFixtures.crime(&"crime.mugging", 20.0)
	theirs.law_faction = &"faction.thieves"
	assert_ok(component.witness(offender, theirs))


func test_more_witnesses_make_the_same_crime_worse() -> void:
	var public := CrimeFixtures.crime(&"crime.affray", 20.0)
	public.witness_scale = 1.0
	public.maximum_witness_scale = 5.0

	var context := CrimeContext.create(offender, public)
	for index in 3:
		var seer := CrimeFixtures.actor("Seer%d" % index)
		add_test_node(seer)
		context.add_witness(seer)
	assert_ok(heat.report(context))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 60.0)


# --- Deaths ----------------------------------------------------------------

func _adapter(bus: Node = null) -> CombatCrimeAdapter:
	var adapter := CombatCrimeAdapter.new()
	adapter.name = "CombatCrimeAdapter"
	adapter.heat = heat
	adapter.murder = CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	adapter.event_bus = bus
	adapter.witness_range = 0.0
	add_test_node(adapter)
	return adapter


func test_a_witnessed_killing_is_murder() -> void:
	var adapter := _adapter()
	adapter.register_witness(_witness())
	var victim := CrimeFixtures.actor("Victim")
	add_test_node(victim)
	CrimeFixtures.assemble(victim, core)

	assert_ok(adapter.report_death(victim, offender))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 60.0)


func test_an_unwitnessed_killing_is_not_reported() -> void:
	var adapter := _adapter()
	var victim := CrimeFixtures.actor("Victim")
	add_test_node(victim)
	CrimeFixtures.assemble(victim, core)
	assert_err(adapter.report_death(victim, offender), &"crime.unwitnessed")


func test_a_killing_with_no_killer_is_nobodys_fault() -> void:
	var adapter := _adapter()
	adapter.register_witness(_witness())
	var victim := CrimeFixtures.actor("Victim")
	add_test_node(victim)
	assert_err(adapter.report_death(victim, null), &"crime.no_killer")


func test_a_self_inflicted_death_is_not_a_crime() -> void:
	# A suicide, or an explosion that killed the person who set it.
	var adapter := _adapter()
	adapter.register_witness(_witness())
	assert_err(adapter.report_death(offender, offender), &"crime.self_inflicted")


func test_killing_is_legal_with_no_offence_configured() -> void:
	# Correct for an arena shooter, and the default.
	var adapter := _adapter()
	adapter.murder = null
	adapter.register_witness(_witness())
	var victim := CrimeFixtures.actor("Victim")
	add_test_node(victim)
	assert_err(adapter.report_death(victim, offender), &"crime.not_a_crime")


func test_a_wartime_killing_can_be_a_different_offence() -> void:
	# So a project can make war legal, mildly illegal, or worse than murder,
	# none of them a special case in code.
	var factions := CrimeFixtures.factions()
	add_test_node(factions)
	# Both directions. FactionService keys relations as "subject>other" on
	# purpose -- a one-sided grudge is a real thing -- so setting only
	# police>thieves leaves the thief perfectly happy about the police, and the
	# killing reads as plain murder rather than an act of war.
	factions.set_relation(&"faction.police", &"faction.thieves", -100.0)
	factions.set_relation(&"faction.thieves", &"faction.police", -100.0)

	var thief := CrimeFixtures.actor("Thief", &"faction.thieves", factions)
	var constable := CrimeFixtures.actor("Constable", &"faction.police", factions)
	for entity in [thief, constable]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)

	var adapter := _adapter()
	adapter.wartime_murder = CrimeFixtures.crime(&"crime.war", 5.0, 1.0)
	adapter.register_witness(_witness())

	assert_ok(adapter.report_death(constable, thief))
	assert_almost_eq(
		heat.get_heat(&"thief", &"faction.police"), 5.0, 0.001, "war is cheap here"
	)


func test_witnesses_are_registered_rather_than_discovered() -> void:
	# Searching the scene for anybody nearby is exactly the scan M14 spent a
	# milestone avoiding.
	var adapter := _adapter()
	assert_eq(adapter.get_witness_count(), 0)
	var bystander := _witness()
	assert_true(adapter.register_witness(bystander))
	assert_false(adapter.register_witness(bystander), "the same one twice")
	assert_eq(adapter.get_witness_count(), 1)
	assert_true(adapter.unregister_witness(bystander))
	assert_eq(adapter.get_witness_count(), 0)


func test_only_witnesses_in_range_are_gathered() -> void:
	var adapter := _adapter()
	adapter.witness_range = 20.0
	adapter.register_witness(_witness("Near", 0.0, Vector3(5.0, 0.0, 0.0)))
	adapter.register_witness(_witness("Far", 0.0, Vector3(500.0, 0.0, 0.0)))
	assert_size(adapter.find_witnesses(Vector3.ZERO), 1)


# --- The bus seam ----------------------------------------------------------

func test_a_crime_becomes_a_cross_feature_fact() -> void:
	var bus := make_autoload(BUS_SCRIPT, "EventBus")
	var seen: Array = []
	bus.subscribe(
		GameplayNames.EVENT_CRIME_WITNESSED,
		func(event: FrameworkEvent) -> void: seen.append(event)
	)

	var adapter := CrimeEventAdapter.new()
	adapter.name = "CrimeEventAdapter"
	adapter.event_bus = bus
	adapter.service = heat
	add_test_node(adapter)

	assert_ok(_witness().witness(offender, assault))
	assert_size(seen, 1)
	assert_eq(seen[0].actor_id, &"offender")
	assert_eq(seen[0].crime_id, &"crime.assault")
	assert_eq(seen[0].witness_count, 1)
	assert_true(seen[0].has_crime_tag(&"crime.violent"))


func test_a_wanted_level_change_becomes_a_fact() -> void:
	var bus := make_autoload(BUS_SCRIPT, "EventBus")
	var seen: Array = []
	bus.subscribe(
		GameplayNames.EVENT_WANTED_CHANGED,
		func(event: FrameworkEvent) -> void: seen.append(event)
	)

	var adapter := CrimeEventAdapter.new()
	adapter.name = "CrimeEventAdapter"
	adapter.event_bus = bus
	adapter.service = heat
	add_test_node(adapter)

	heat.add_heat(&"offender", &"faction.police", 60.0)
	assert_size(seen, 1)
	assert_eq(seen[0].wanted_state, GameplayNames.STATE_WANTED)
	assert_true(seen[0].is_wanted())

	heat.clear_actor(&"offender")
	assert_size(seen, 2)
	assert_false(seen[1].is_wanted(), "and escaping is the absence of a state")


func test_the_bus_seam_is_deletable() -> void:
	var bus := make_autoload(BUS_SCRIPT, "EventBus")
	var seen: Array = []
	bus.subscribe(
		GameplayNames.EVENT_CRIME_WITNESSED,
		func(event: FrameworkEvent) -> void: seen.append(event)
	)

	assert_ok(_witness().witness(offender, assault))
	assert_almost_eq(heat.get_heat(&"offender", &"faction.police"), 25.0)
	assert_empty(seen, "the law works; nothing simply hears about it")
