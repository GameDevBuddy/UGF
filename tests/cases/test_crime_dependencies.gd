extends FrameworkTestCase
## The M15 exit gate: crime alters faction and AI response without dependency
## cycles.
##
## [b]Two halves, and both matter.[/b] The behaviour half is easy to get right
## by accident — a guard attacks a murderer — and says nothing about the
## architecture. The structural half is the actual claim: no file in
## [code]combat/[/code], [code]ai/[/code] or [code]factions/[/code] mentions
## crime, heat or a wanted level, and Combat needed no change at all for this
## milestone.
##
## Both are asserted here, because either one alone would let the other rot.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var core: Node = null
var bus: Node = null
var heat: HeatService = null
var factions: FactionService = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	factions = CrimeFixtures.factions()
	add_test_node(factions)
	heat = CrimeFixtures.heat_service()
	add_test_node(heat)
	core.register_service(GameplayNames.SERVICE_CRIME, heat)


# --- The structural claim -------------------------------------------------

func _sources_in(directory: String) -> Dictionary:
	var found: Dictionary = {}
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		var path := directory.path_join(entry)
		if handle.current_is_dir():
			if not entry.begins_with("."):
				found.merge(_sources_in(path))
		elif entry.ends_with(".gd"):
			found[path] = FileAccess.get_file_as_string(path)
		entry = handle.get_next()
	handle.list_dir_end()
	return found


func test_no_module_crime_layers_on_top_of_mentions_it() -> void:
	# The cycle this forbids: Combat -> Crime -> Factions -> consumed by AI ->
	# issues the attacks. Every one of those arrows would be real if any of
	# these files named a crime.
	var forbidden := [
		"CrimeDefinition", "CrimeContext", "HeatService", "WantedTier",
		"HeatProfile", "WitnessComponent", "CrimeFactionAdapter",
		"CrimeAIAdapter", "WantedHostilityProvider", "SERVICE_CRIME",
	]
	for directory in [
		"res://addons/universal_gameplay/combat",
		"res://addons/universal_gameplay/ai",
		"res://addons/universal_gameplay/factions",
		"res://addons/universal_gameplay/health_damage",
	]:
		var sources := _sources_in(directory)
		assert_true(sources.size() > 0, "%s should have sources" % directory)
		for path in sources:
			for name in forbidden:
				assert_false(
					(sources[path] as String).contains(name),
					"%s names %s" % [(path as String).get_file(), name]
				)


func test_crime_reaches_ai_through_the_seam_ai_already_declared() -> void:
	# WantedHostilityProvider extends the base AI declared in M7. That
	# inheritance is the entire coupling, and it points the safe way.
	assert_true(WantedHostilityProvider.new() is HostilityProvider)


func test_the_crime_module_requires_nothing() -> void:
	var module: FrameworkModule = load(
		"res://addons/universal_gameplay/crime_heat/crime_module.gd"
	).new()
	var manifest := module.get_manifest()
	assert_eq(manifest.id, GameplayNames.MODULE_CRIME)
	assert_empty(manifest.requires, "an optional module that requires nothing")
	assert_has(manifest.optional, GameplayNames.MODULE_FACTIONS)
	assert_has(manifest.optional, GameplayNames.MODULE_AI)


func test_the_heat_service_does_not_depend_on_factions() -> void:
	# Reputation is the adapter's job. A project can have a wanted level with
	# no social system behind it at all.
	var source := FileAccess.get_file_as_string(
		"res://addons/universal_gameplay/crime_heat/heat_service.gd"
	)
	assert_true(source.length() > 0)
	assert_false(source.contains("FactionService"), "the service names Factions")


# --- The behavioural claim ------------------------------------------------

func test_a_killing_becomes_a_crime_without_combat_knowing() -> void:
	# Combat publishes actor_died and has since M3. Crime subscribes. Neither
	# file changed for this test to pass.
	var killer := CrimeFixtures.actor("Killer")
	var victim := CrimeFixtures.actor("Victim", &"faction.police", factions)
	var bystander := CrimeFixtures.witness("Bystander", heat)
	for entity in [killer, victim, bystander]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)

	var adapter := CombatCrimeAdapter.new()
	adapter.name = "CombatCrimeAdapter"
	adapter.heat = heat
	adapter.murder = CrimeFixtures.crime(&"crime.murder", 60.0, 30.0)
	adapter.event_bus = bus
	adapter.witness_range = 0.0
	add_test_node(adapter)
	adapter.register_witness(CrimeFixtures.witness_of(bystander))

	assert_false(heat.is_wanted(&"killer", &"faction.police"))

	# Published exactly the way HealthComponent's own adapter publishes it.
	bus.register_event(GameplayNames.EVENT_ACTOR_DIED)
	bus.publish(ActorDiedEvent.create(victim, DamageContext.create(10.0, killer)))

	assert_almost_eq(heat.get_heat(&"killer", &"faction.police"), 60.0)
	assert_true(heat.is_wanted(&"killer", &"faction.police"))


func test_a_wanted_actor_becomes_an_enemy_of_the_law() -> void:
	var offender := CrimeFixtures.actor("Offender")
	var constable := CrimeFixtures.guard("Constable", heat, &"faction.police", factions)
	for entity in [offender, constable]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)

	var brain := (
		CrimeFixtures.find(constable, AIControllerComponent) as AIControllerComponent
	)
	var provider := brain.get_hostility_provider()
	assert_false(provider.is_hostile(constable, offender), "not yet a criminal")

	heat.add_heat(&"offender", &"faction.police", 60.0)
	assert_true(provider.is_hostile(constable, offender), "now they are")


func test_the_law_hook_wraps_faction_politics_rather_than_replacing_them() -> void:
	# Otherwise installing a crime system makes every policeman forget who its
	# enemies already were.
	factions.set_relation(&"faction.police", &"faction.thieves", -80.0)
	var thief := CrimeFixtures.actor("Thief", &"faction.thieves", factions)
	var constable := CrimeFixtures.guard("Constable", heat, &"faction.police", factions)
	for entity in [thief, constable]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)

	var brain := (
		CrimeFixtures.find(constable, AIControllerComponent) as AIControllerComponent
	)
	assert_true(
		brain.get_hostility_provider().is_hostile(constable, thief),
		"a hated faction is still hated with no crime on record"
	)


func test_removing_the_law_hook_leaves_faction_politics_intact() -> void:
	factions.set_relation(&"faction.police", &"faction.thieves", -80.0)
	var thief := CrimeFixtures.actor("Thief", &"faction.thieves", factions)
	var constable := CrimeFixtures.guard("Constable", heat, &"faction.police", factions)
	for entity in [thief, constable]:
		add_test_node(entity)
		CrimeFixtures.assemble(entity, core)

	var law := CrimeFixtures.find(constable, CrimeAIAdapter) as CrimeAIAdapter
	law.uninstall()

	var brain := (
		CrimeFixtures.find(constable, AIControllerComponent) as AIControllerComponent
	)
	assert_true(
		brain.get_hostility_provider().is_hostile(constable, thief),
		"uninstalling the law must not uninstall the politics"
	)
	heat.add_heat(&"thief", &"faction.police", 100.0)
	var innocent := CrimeFixtures.actor("Innocent")
	add_test_node(innocent)
	CrimeFixtures.assemble(innocent, core)
	assert_false(
		brain.get_hostility_provider().is_hostile(constable, innocent),
		"and the warrant no longer counts"
	)


func test_crime_alters_faction_standing_through_factions_own_api() -> void:
	var adapter := CrimeFactionAdapter.new()
	adapter.name = "CrimeFactionAdapter"
	adapter.heat = heat
	adapter.factions = factions
	add_test_node(adapter)

	factions.set_relation(&"faction.thieves", &"faction.police", -100.0)
	var thief := CrimeFixtures.actor("Thief")
	add_test_node(thief)
	CrimeFixtures.assemble(thief, core)

	var bystander := CrimeFixtures.witness("Bystander", heat)
	add_test_node(bystander)
	CrimeFixtures.assemble(bystander, core)

	var crime := CrimeFixtures.crime(&"crime.assault", 25.0, 20.0)
	assert_ok(
		CrimeFixtures.witness_of(bystander).witness(thief, crime, null)
	)

	assert_true(
		factions.get_reputation(&"faction.police", &"thief") < 0.0,
		"the police mind"
	)
	assert_true(
		factions.get_reputation(&"faction.thieves", &"thief") > 0.0,
		"and their enemies are impressed"
	)


func test_everything_still_works_with_no_crime_module_installed() -> void:
	# Rule 10 and rule 31 together: the whole milestone is deletable. A guard
	# with no law hook fights by faction, exactly as it did in M10.
	factions.set_relation(&"faction.police", &"faction.thieves", -80.0)
	var thief := CrimeFixtures.actor("Thief", &"faction.thieves", factions)
	add_test_node(thief)
	CrimeFixtures.assemble(thief, core)

	var constable := CrimeFixtures.actor("Constable", &"faction.police", factions)
	var movement := MovementComponent.new()
	movement.name = "MovementComponent"
	movement.auto_tick = false
	constable.add_child(movement)
	var brain := AIControllerComponent.new()
	brain.name = "AIControllerComponent"
	brain.movement = movement
	brain.auto_tick = false
	constable.add_child(brain)
	var politics := FactionAIAdapter.new()
	politics.name = "FactionAIAdapter"
	politics.controller = brain
	politics.service = factions
	constable.add_child(politics)
	add_test_node(constable)
	CrimeFixtures.assemble(constable, core)

	assert_null(CrimeFixtures.find(constable, CrimeAIAdapter))
	assert_true(brain.get_hostility_provider().is_hostile(constable, thief))
