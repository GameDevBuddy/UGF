extends FrameworkTestCase
## Covers FactionComponent and the two adapters, and holds the M10 exit gate:
## AI hostility and vendor pricing consuming faction results without either
## side importing the other.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var factions: FactionService = null


func before_each() -> void:
	factions = FactionFixtures.service()
	add_test_node(factions)


func _member(
	entity_name: String, faction_id: StringName, actor_id: StringName = &""
) -> Node3D:
	var entity := add_test_node(
		FactionFixtures.member(entity_name, faction_id, factions, actor_id)
	) as Node3D
	FactionFixtures.assemble(entity)
	return entity


# --- FactionComponent -----------------------------------------------------

func test_an_entity_knows_which_side_it_is_on() -> void:
	var guard := _member("Guard", &"faction.watch")
	assert_eq(FactionFixtures.faction_of(guard).get_faction(), &"faction.watch")
	assert_true(FactionFixtures.faction_of(guard).has_faction())


func test_an_entity_with_no_allegiance_is_neutral_to_everyone() -> void:
	var deer := _member("Deer", &"")
	var guard := _member("Guard", &"faction.watch")
	assert_false(FactionFixtures.faction_of(deer).has_faction())
	assert_eq(
		FactionFixtures.faction_of(deer).get_attitude_to(guard),
		AttitudeSolver.Attitude.NEUTRAL
	)


func test_attitude_between_entities_reads_their_factions() -> void:
	var guard := _member("Guard", &"faction.watch")
	var bandit := _member("Bandit", &"faction.bandits")
	assert_true(FactionFixtures.faction_of(guard).is_hostile_to(bandit))
	assert_true(FactionFixtures.faction_of(bandit).is_hostile_to(guard))


func test_two_members_of_one_faction_are_not_enemies() -> void:
	var first := _member("Guard A", &"faction.watch")
	var second := _member("Guard B", &"faction.watch")
	assert_false(FactionFixtures.faction_of(first).is_hostile_to(second))
	assert_true(FactionFixtures.faction_of(first).is_friendly_to(second))


func test_a_personal_reputation_outranks_the_side_someone_is_on() -> void:
	var bandit := _member("Bandit", &"faction.bandits")
	var turncoat := _member("Turncoat", &"faction.watch", &"actor.turncoat")
	assert_true(FactionFixtures.faction_of(bandit).is_hostile_to(turncoat))

	factions.set_reputation(&"faction.bandits", &"actor.turncoat", 60.0)
	assert_false(FactionFixtures.faction_of(bandit).is_hostile_to(turncoat))


func test_an_entity_can_change_sides() -> void:
	var changes: Array[StringName] = []
	var guard := _member("Guard", &"faction.watch")
	var mark := FactionFixtures.faction_of(guard)
	mark.faction_changed.connect(func(f: StringName) -> void: changes.append(f))

	mark.set_faction(&"faction.bandits")
	assert_eq(mark.get_faction(), &"faction.bandits")
	assert_size(changes, 1)


func test_reporting_a_crime_reaches_the_victims_friends() -> void:
	var guard := _member("Guard", &"faction.watch")
	FactionFixtures.faction_of(guard).report(&"actor.player", -40.0)

	assert_almost_eq(factions.get_reputation(&"faction.watch", &"actor.player"), -40.0)
	assert_true(factions.get_reputation(&"faction.merchants", &"actor.player") < 10.0)


func test_the_faction_comes_from_the_definition_when_not_overridden() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.guard"
	definition.faction = FactionFixtures.watch()

	var entity := add_test_node(Node3D.new())
	var mark := FactionComponent.new()
	mark.name = "FactionComponent"
	mark.service = factions
	entity.add_child(mark)
	FactionFixtures.assemble(entity, definition)

	assert_eq(mark.get_faction(), &"faction.watch")


func test_allegiance_survives_a_save() -> void:
	var guard := _member("Guard", &"faction.watch")
	var mark := FactionFixtures.faction_of(guard)
	var saved := mark.capture_state()

	mark.set_faction(&"faction.bandits")
	mark.restore_state(saved)
	assert_eq(mark.get_faction(), &"faction.watch")
	assert_true(mark.is_persistent())


# --- The AI adapter -------------------------------------------------------

func _npc(entity_name: String, faction_id: StringName) -> Node3D:
	var npc := add_test_node(
		AIFixtures.npc(entity_name, Vector3.ZERO, AIFixtures.guard())
	) as Node3D

	var mark := FactionComponent.new()
	mark.name = "FactionComponent"
	mark.faction_override = faction_id
	mark.service = factions
	npc.add_child(mark)

	var adapter := FactionAIAdapter.new()
	adapter.name = "FactionAIAdapter"
	adapter.service = factions
	npc.add_child(adapter)

	AIFixtures.assemble(npc)
	return npc


func test_without_the_adapter_an_npc_fights_everything_it_notices() -> void:
	# The framework default, and the right one for an arena shooter with no
	# social system installed.
	var npc := add_test_node(
		AIFixtures.npc("Berserker", Vector3.ZERO, AIFixtures.guard())
	) as Node3D
	AIFixtures.assemble(npc)
	var stranger := _member("Stranger", &"faction.watch")
	assert_true(AIFixtures.controller_of(npc).get_hostility_provider().is_hostile(npc, stranger))


func test_the_adapter_teaches_an_npc_to_fight_by_faction() -> void:
	var guard := _npc("Guard", &"faction.watch")
	var bandit := _member("Bandit", &"faction.bandits")
	var merchant := _member("Merchant", &"faction.merchants")
	var provider := AIFixtures.controller_of(guard).get_hostility_provider()

	assert_true(provider is FactionHostilityProvider)
	assert_true(provider.is_hostile(guard, bandit))
	assert_false(provider.is_hostile(guard, merchant))
	assert_true(provider.is_ally(guard, merchant))


func test_an_npc_with_no_allegiance_still_fights() -> void:
	# The shipped character scene carries a faction component that most
	# content leaves blank; it must not turn every NPC pacifist.
	var neutral := _npc("Neutral", &"")
	var bandit := _member("Bandit", &"faction.bandits")
	assert_true(
		AIFixtures.controller_of(neutral).get_hostility_provider().is_hostile(neutral, bandit)
	)


func test_things_with_no_faction_at_all_can_be_ignored() -> void:
	var guard := _npc("Guard", &"faction.watch")
	var deer := add_test_node(Node3D.new())
	var provider := AIFixtures.controller_of(guard).get_hostility_provider()
	assert_false(provider.is_hostile(guard, deer))

	provider.hostile_to_unaffiliated = true
	assert_true(provider.is_hostile(guard, deer))


func test_removing_the_adapter_restores_the_default() -> void:
	var guard := _npc("Guard", &"faction.watch")
	var merchant := _member("Merchant", &"faction.merchants")
	var adapter := guard.get_node("FactionAIAdapter") as FactionAIAdapter

	assert_false(AIFixtures.controller_of(guard).get_hostility_provider().is_hostile(guard, merchant))
	adapter.uninstall()
	assert_true(AIFixtures.controller_of(guard).get_hostility_provider().is_hostile(guard, merchant))


# --- The AI actually behaving differently ---------------------------------

func _see(observer: Node3D, target: Node3D, provider: FakePerceptionProvider) -> void:
	AIFixtures.perception_of(observer).set_provider(provider)
	provider.candidates.append(target)


func test_a_guard_charges_a_bandit_and_ignores_a_merchant() -> void:
	# The gate's first half, end to end: the same brain, the same perception,
	# two different targets, and the only difference is standing.
	var provider := FakePerceptionProvider.new()
	var guard := _npc("Guard", &"faction.watch")
	guard.global_position = Vector3.ZERO

	var merchant := _perceivable_member("Merchant", &"faction.merchants", Vector3.FORWARD * 5.0)
	_see(guard, merchant, provider)
	_run(guard)
	assert_ne(
		AIFixtures.controller_of(guard).get_ai_state(),
		GameplayNames.AI_STATE_ENGAGE,
		"a friendly merchant is not a fight"
	)

	var bandit := _perceivable_member("Bandit", &"faction.bandits", Vector3.FORWARD * 5.0)
	provider.candidates.append(bandit)
	_run(guard)
	assert_eq(AIFixtures.controller_of(guard).get_ai_state(), GameplayNames.AI_STATE_ENGAGE)


func _perceivable_member(
	entity_name: String, faction_id: StringName, position: Vector3
) -> Node3D:
	var entity := add_test_node(AIFixtures.actor(entity_name, position)) as Node3D
	var mark := FactionComponent.new()
	mark.name = "FactionComponent"
	mark.faction_override = faction_id
	mark.service = factions
	entity.add_child(mark)
	AIFixtures.assemble(entity)
	return entity


func _run(npc: Node3D, seconds: float = 0.6, step: float = 0.2) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		AIFixtures.perception_of(npc).sweep(step)
		AIFixtures.controller_of(npc).tick(step)
		elapsed += step


# --- The pricing adapter --------------------------------------------------

func test_pricing_reads_standing_without_commerce_existing() -> void:
	# The gate's second half. Commerce is M11; what a pricing policy needs
	# from Factions is one number, and it can be produced and tested now.
	var pricing := FactionPriceAdapter.create(factions, 0.2)

	assert_almost_eq(pricing.get_multiplier(&"faction.merchants", &"faction.watch"), 0.9)
	assert_almost_eq(pricing.get_multiplier(&"faction.merchants", &"faction.bandits"), 1.1)


func test_a_liked_customer_is_charged_less() -> void:
	var pricing := FactionPriceAdapter.create(factions, 0.2)
	assert_almost_eq(pricing.apply(100.0, &"faction.merchants", &"actor.player"), 100.0)

	factions.set_reputation(&"faction.merchants", &"actor.player", 80.0)
	assert_almost_eq(pricing.apply(100.0, &"faction.merchants", &"actor.player"), 80.0)

	factions.set_reputation(&"faction.merchants", &"actor.player", -60.0)
	assert_almost_eq(pricing.apply(100.0, &"faction.merchants", &"actor.player"), 120.0)


func test_pricing_between_two_entities_reads_their_components() -> void:
	var vendor := _member("Vendor", &"faction.merchants")
	var customer := _member("Customer", &"faction.watch")
	var pricing := FactionPriceAdapter.create(factions, 0.2)
	assert_almost_eq(pricing.get_multiplier_for(vendor, customer), 0.9)


func test_a_vendor_with_no_allegiance_charges_list_price() -> void:
	var vendor := _member("Vendor", &"")
	var customer := _member("Customer", &"faction.watch")
	assert_almost_eq(
		FactionPriceAdapter.create(factions).get_multiplier_for(vendor, customer), 1.0
	)


func test_pricing_with_no_service_charges_list_price() -> void:
	assert_almost_eq(
		FactionPriceAdapter.create(null).get_multiplier(&"faction.merchants", &"actor.player"),
		1.0
	)


func test_prices_come_back_as_whole_units() -> void:
	# A shop showing 12.7 gold is a bug every project fixes once.
	var pricing := FactionPriceAdapter.create(factions, 0.2)
	factions.set_reputation(&"faction.merchants", &"actor.player", 80.0)
	assert_almost_eq(pricing.apply(13.0, &"faction.merchants", &"actor.player"), 10.0)


# --- Faction facts on the bus ---------------------------------------------

func test_a_change_of_heart_reaches_the_bus() -> void:
	var bus := make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	var received: Array[FrameworkEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_ATTITUDE_CHANGED,
		func(event: FrameworkEvent) -> void: received.append(event)
	)

	var adapter := FactionEventAdapter.new()
	adapter.name = "FactionEventAdapter"
	adapter.event_bus = bus
	adapter.service = factions
	add_test_node(adapter)
	adapter.set_bus(bus)
	adapter.watch(factions)

	factions.modify_reputation(&"faction.watch", &"actor.player", -10.0)
	assert_empty(received, "still neutral")

	factions.modify_reputation(&"faction.watch", &"actor.player", -60.0)
	assert_size(received, 1)
	assert_eq(received[0].faction, &"faction.watch")
	assert_eq(received[0].other, &"actor.player")
	assert_true(received[0].is_hostile())
	assert_eq(received[0].attitude_name, &"attitude.hostile")


func test_the_service_works_with_the_event_adapter_deleted() -> void:
	factions.modify_reputation(&"faction.watch", &"actor.player", -60.0)
	assert_true(factions.is_hostile(&"faction.watch", &"actor.player"))
