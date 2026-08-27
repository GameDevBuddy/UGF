extends FrameworkTestCase
## Slice B of the vertical slice gates (Implementation Plan 36): weapon ->
## damage -> loot -> equip -> XP/reputation -> mission.
##
## [b]Every module here already passes its own suite.[/b] What this file asks
## is whether they compose: whether one trigger pull, resolved by the real
## combat pipeline, travels the whole width of a shooter RPG and comes out the
## far side as a finished mission. The links are deliberately not stubbed. The
## shot goes through [CombatComponent] against a [FakeHitProvider], the death
## comes out of [HealthComponent], the drop comes out of [LootComponent]
## rolling a seeded table, the carbine is equipped through
## [EquipmentComponent], the level comes out of [ProgressionComponent], the
## standing comes out of [FactionService], and the mission is a real
## [MissionService] mission matching bus events by name.
##
## [b]The two adapters are the load-bearing pieces.[/b] [HealthEventAdapter]
## and [ProgressionEventAdapter] are the only reason Missions hears about a
## death or a level at all, and each carries a flag that switches its
## promotion off. Two tests here flip those flags and assert the chain stalls
## at exactly that point, because a gate that cannot fail proves nothing.
##
## [b]The one piece of glue is deliberate and named.[/b] The framework ships no
## combat-to-progression adapter, because what a bandit is worth is content
## rather than framework. So the project's own rule -- a kill by this shooter
## pays experience -- is a bus subscription made here, in
## [method _pay_experience_for_a_kill]. Everything downstream of it is the
## framework's own work.
##
## Reputation moves the way the framework actually moves it: the killing is
## reported by [CombatCrimeAdapter], accepted by [HeatService], and spent by
## [CrimeFactionAdapter] through [method FactionService.propagate_reputation].
## Nothing here calls [method FactionService.modify_reputation] by hand, which
## is the point -- the standing change has to be a consequence of the shot.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

## What the project pays for a bandit. The track costs 100 to reach level 2,
## so one kill crosses exactly one boundary and the mission objective can name
## the level it wants.
const KILL_EXPERIENCE: float = 120.0

## Seed for the corpse's table, so the drop is a fixed fact this file can
## assert rather than a probability it has to hedge against.
const LOOT_SEED: int = 4242

## Standing the killing costs with the victim's own faction.
const MURDER_REPUTATION_COST: float = 30.0

var bus: Node = null
var core: Node = null

var factions: FactionService = null
var heat: HeatService = null
var narrative: NarrativeStateService = null
var missions: MissionService = null
var law: CombatCrimeAdapter = null
var consequences: CrimeFactionAdapter = null

var provider: FakeHitProvider = null

var shooter: Node3D = null
var combat: CombatComponent = null
var weapon: WeaponComponent = null
var stats: StatsComponent = null
var pack: InventoryComponent = null
var equipment: EquipmentComponent = null
var progression: ProgressionComponent = null
var promoter: ProgressionEventAdapter = null

var bandit: Node3D = null
var bandit_health: HealthComponent = null
var corpse_bag: InventoryComponent = null
var pockets: LootComponent = null
var obituary: HealthEventAdapter = null

var sidearm: ItemDefinition = null
var carbine: ItemDefinition = null
var scrap: ItemDefinition = null
var trophy: ItemDefinition = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	_register_content()
	_build_services()
	_build_shooter()
	_build_bandit()

	# The project's own kill reward. Named, subscribed, and the only glue in
	# this file -- see the note at the top.
	assert_ok(
		bus.subscribe(GameplayNames.EVENT_ACTOR_DIED, _pay_experience_for_a_kill),
		"the project's kill reward is subscribed"
	)


# --- The world ------------------------------------------------------------

func _register_content() -> void:
	# The sidearm the shooter starts with. Equipped rather than jammed into
	# WeaponComponent as an override, because an override short-circuits the
	# equipment lookup and would make the equip link untestable.
	sidearm = ItemFixtures.weapon(&"item.sidearm", 2.0)
	sidearm.weapon = CombatFixtures.rifle(60.0, 5)

	# What the bandit is carrying. Better in both ways a weapon can be better:
	# a bigger stat bonus and a different WeaponProfile.
	carbine = ItemFixtures.weapon(&"item.bandit_carbine", 8.0)
	carbine.weapon = CombatFixtures.rifle(35.0, 8)

	scrap = ItemFixtures.stackable(&"item.scrap", 99)
	trophy = ItemFixtures.unique(&"item.trophy")

	for definition in [sidearm, carbine, scrap, trophy]:
		core.get_definition_registry().register(definition)


func _build_services() -> void:
	factions = FactionFixtures.service()
	factions.name = "FactionService"
	add_test_node(factions)

	heat = CrimeFixtures.heat_service()
	add_test_node(heat)

	narrative = NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)

	missions = MissionService.new()
	missions.name = "MissionService"
	add_test_node(missions)
	missions.configure(core, bus, narrative)

	# Killing is an offence against whoever the victim belonged to. The
	# definition names no law faction, so HeatService resolves it from the
	# corpse -- which is how one adapter covers murdering a bandit and
	# murdering a constable without a table of special cases.
	var murder := CrimeFixtures.crime(&"crime.murder", 60.0, MURDER_REPUTATION_COST, false)
	murder.law_faction = &""

	law = CombatCrimeAdapter.new()
	law.name = "CombatCrimeAdapter"
	law.heat = heat
	law.murder = murder
	law.event_bus = bus
	law.requires_witness = false
	add_test_node(law)

	consequences = CrimeFactionAdapter.new()
	consequences.name = "CrimeFactionAdapter"
	consequences.heat = heat
	consequences.factions = factions
	consequences.spread = 0.5
	add_test_node(consequences)


func _build_shooter() -> void:
	provider = FakeHitProvider.new()
	provider.wall = add_test_node(Node.new())

	shooter = CombatFixtures.fighter("Shooter", Vector3.ZERO, null) as Node3D

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"shooter"
	shooter.add_child(identity)

	stats = StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = ItemFixtures.stats_profile(10.0)
	stats.auto_tick = false
	shooter.add_child(stats)

	pack = InventoryComponent.new()
	pack.name = "InventoryComponent"
	pack.profile_override = ItemFixtures.container(20)
	shooter.add_child(pack)

	equipment = EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.loadout_override = ItemFixtures.loadout()
	equipment.stats = stats
	equipment.inventory = pack
	shooter.add_child(equipment)

	progression = ProgressionComponent.new()
	progression.name = "ProgressionComponent"
	progression.profile_override = ProgressionFixtures.profile(
		[ProgressionFixtures.track(&"track.gunplay", 5, 100.0, 1)]
	)
	shooter.add_child(progression)

	promoter = ProgressionEventAdapter.new()
	promoter.name = "ProgressionEventAdapter"
	promoter.progression = progression
	promoter.event_bus = bus
	shooter.add_child(promoter)

	add_test_node(shooter)
	_assemble(shooter)

	combat = CombatFixtures.combat_of(shooter)
	weapon = CombatFixtures.weapon_of(shooter)
	combat.set_hit_provider(provider)
	combat.set_rng(_rng(7))

	# Armed by equipping, not by injection, so WeaponComponent is reading the
	# loadout from the first shot onwards.
	assert_ok(equipment.equip(ItemInstance.create(sidearm)), "the shooter starts armed")


func _build_bandit() -> void:
	bandit = CombatFixtures.dummy("Bandit", Vector3.FORWARD * 12.0, 100.0) as Node3D

	var mark := Perceivable.new()
	mark.name = "Perceivable"
	var tags: Array[StringName] = [&"actor.bandit"]
	mark.tags = tags
	bandit.add_child(mark)

	var allegiance := FactionComponent.new()
	allegiance.name = "FactionComponent"
	allegiance.faction_override = &"faction.bandits"
	allegiance.service = factions
	bandit.add_child(allegiance)

	corpse_bag = InventoryComponent.new()
	corpse_bag.name = "InventoryComponent"
	corpse_bag.profile_override = ItemFixtures.container(10)
	bandit.add_child(corpse_bag)

	# Loot is added before the obituary so it is connected to `died` first: the
	# corpse has its pockets filled before anything downstream is told about
	# the death, which is the order a looter would expect.
	pockets = LootComponent.new()
	pockets.name = "LootComponent"
	pockets.table_override = _bandit_table()
	pockets.container = corpse_bag
	bandit.add_child(pockets)

	obituary = HealthEventAdapter.new()
	obituary.name = "HealthEventAdapter"
	obituary.event_bus = bus
	bandit.add_child(obituary)

	add_test_node(bandit)
	_assemble(bandit)

	bandit_health = CombatFixtures.health_of(bandit)
	pockets.set_rng(_rng(LOOT_SEED))
	provider.targets.append(bandit)


## A guaranteed carbine plus one weighted pick, so the drop proves both halves
## of a table: what always falls out, and what the seed decided.
func _bandit_table() -> LootTableDefinition:
	return CommerceFixtures.loot_table(
		&"loot.bandit",
		[
			CommerceFixtures.loot_entry(&"item.bandit_carbine", 1, 1, 0.0, true),
			CommerceFixtures.loot_entry(&"item.scrap", 1, 3, 50.0),
			CommerceFixtures.loot_entry(&"item.trophy", 1, 1, 50.0),
		],
		1
	)


## "Kill a bandit, then make corporal." One objective per module, matched off
## the bus by event name, with Missions importing neither Combat nor
## Progression.
func _bounty_mission() -> MissionDefinition:
	var rank := MissionFixtures.objective(
		&"objective.make_corporal",
		GameplayNames.EVENT_LEVEL_GAINED,
		[
			MissionFixtures.by_subject(&"actor"),
			MissionFixtures.matcher(&"track_id", &"track.gunplay"),
			MissionFixtures.matcher(&"level", 2, EventMatcher.Mode.GREATER_OR_EQUAL),
		]
	)
	return MissionFixtures.mission(
		&"mission.bounty", [MissionFixtures.kill_objective(1, &"actor.bandit"), rank]
	)


# --- Helpers --------------------------------------------------------------

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _assemble(entity: Node) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


## The project rule the framework deliberately does not ship: a kill by this
## shooter is worth experience. Subscribed to the bus rather than called from
## the tests, so the award is a consequence of the death and not of the test.
func _pay_experience_for_a_kill(event: FrameworkEvent) -> void:
	var death := event as ActorDiedEvent
	if death == null or death.get_instigator() != shooter:
		return
	progression.award(&"track.gunplay", KILL_EXPERIENCE)


## Two trigger pulls, with the weapon ticked between them so the rate limit is
## honoured rather than bypassed.
func _empty_the_sidearm_into_the_bandit() -> void:
	assert_ok(combat.attack(), "the first shot is allowed")
	weapon.tick(0.5)
	assert_ok(combat.attack(), "the second shot is allowed")


# --- 1 and 2: weapon and damage -------------------------------------------

func test_a_real_shot_resolves_into_damage_and_a_death() -> void:
	assert_eq(
		weapon.get_weapon_id(), &"item.sidearm",
		"the weapon came from the equipment slot, not from an injected profile"
	)
	assert_eq(weapon.get_magazine(), 5, "a full magazine before firing")

	assert_ok(combat.attack(), "the shot is allowed")
	assert_eq(weapon.get_magazine(), 4, "firing actually cost a round")
	assert_almost_eq(
		bandit_health.get_current(), 40.0, 0.001,
		"the hitscan reached the bandit and DamageReceiver applied it"
	)
	assert_false(bandit_health.is_dead(), "one shot is not enough")

	weapon.tick(0.5)
	assert_ok(combat.attack(), "the second shot is allowed once the rate limit clears")
	assert_true(bandit_health.is_dead(), "the second shot killed it")


func test_the_death_reaches_the_bus_through_the_adapter() -> void:
	var heard: Array[ActorDiedEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_ACTOR_DIED,
		func(event: FrameworkEvent) -> void: heard.append(event as ActorDiedEvent)
	)

	_empty_the_sidearm_into_the_bandit()

	assert_size(heard, 1, "HealthEventAdapter promoted the death exactly once")
	assert_eq(heard[0].actor, bandit, "the event names the bandit as the victim")
	assert_eq(
		heard[0].get_instigator(), shooter,
		"and credits the shooter, which is what every downstream module keys on"
	)


# --- 3: loot --------------------------------------------------------------

func test_the_corpse_rolls_its_table_when_it_dies() -> void:
	assert_true(corpse_bag.is_empty(), "the bandit carries nothing before dying")
	assert_false(pockets.has_rolled(), "and has not been looted")

	_empty_the_sidearm_into_the_bandit()

	assert_true(pockets.has_rolled(), "dying rolled the table, with nobody asking it to")
	assert_eq(
		corpse_bag.count(&"item.bandit_carbine"), 1,
		"the guaranteed entry dropped into the corpse's own container"
	)
	assert_eq(
		corpse_bag.count(&"item.scrap"), 1,
		"and seed %d picked scrap off the weighted entries, one of a possible three" % LOOT_SEED
	)
	assert_eq(
		corpse_bag.count(&"item.trophy"), 0,
		"the other weighted entry lost that roll"
	)


func test_the_same_seed_leaves_the_same_corpse() -> void:
	# The reproducibility the injected RNG exists for. Rolled directly here
	# because a corpse refuses to be looted twice.
	assert_eq(
		str(_bandit_table().roll(_rng(LOOT_SEED))),
		str(_bandit_table().roll(_rng(LOOT_SEED))),
		"two rolls of the same table on the same seed agree"
	)


# --- 4: equip -------------------------------------------------------------

func test_the_looted_carbine_is_carried_equipped_and_felt() -> void:
	assert_almost_eq(
		stats.get_value(&"stat.power"), 12.0, 0.001,
		"base power plus the sidearm before any of this"
	)

	_empty_the_sidearm_into_the_bandit()

	assert_ok(
		corpse_bag.transfer_to(pack, &"item.bandit_carbine", 1),
		"the shooter takes the drop off the corpse"
	)
	assert_eq(pack.count(&"item.bandit_carbine"), 1, "and is carrying it")
	assert_eq(corpse_bag.count(&"item.bandit_carbine"), 0, "the corpse no longer has it")

	var carried := pack.find(&"item.bandit_carbine")
	assert_not_null(carried, "the carried instance is findable")
	assert_ok(equipment.equip(carried), "and equippable")

	assert_almost_eq(
		stats.get_value(&"stat.power"), 18.0, 0.001,
		"the carbine's modifier landed on stats and the sidearm's came back off"
	)
	assert_eq(
		weapon.get_weapon_id(), &"item.bandit_carbine",
		"and WeaponComponent re-read the slot, so the shooter is holding the loot"
	)
	assert_eq(
		pack.count(&"item.sidearm"), 1,
		"the displaced sidearm went back into the pack rather than vanishing"
	)


# --- 5: XP and reputation -------------------------------------------------

func test_the_kill_pays_experience_and_crosses_a_level() -> void:
	var levels: Array = []
	progression.level_gained.connect(
		func(track: StringName, level: int, _previous: int) -> void:
			levels.append([track, level])
	)

	assert_eq(progression.get_level(&"track.gunplay"), 1, "the shooter starts at level 1")

	_empty_the_sidearm_into_the_bandit()

	assert_almost_eq(
		progression.get_experience(&"track.gunplay"), KILL_EXPERIENCE, 0.001,
		"the death paid experience"
	)
	assert_eq(progression.get_level(&"track.gunplay"), 2, "which crossed a level boundary")
	assert_eq(levels, [[&"track.gunplay", 2]], "and announced exactly that one level")
	assert_eq(
		progression.get_unspent_points(&"track.gunplay"), 1,
		"the level handed out its skill point"
	)


func test_the_level_is_promoted_to_the_bus() -> void:
	var promoted: Array = []
	bus.subscribe(
		GameplayNames.EVENT_LEVEL_GAINED,
		func(event: FrameworkEvent) -> void:
			promoted.append([event.get("actor"), event.get("track_id"), event.get("level")])
	)

	_empty_the_sidearm_into_the_bandit()

	assert_eq(
		promoted, [[shooter, &"track.gunplay", 2]],
		"ProgressionEventAdapter put the level on the bus as a plain fact"
	)


func test_the_kill_moves_standing_with_two_factions() -> void:
	assert_almost_eq(
		factions.get_reputation(&"faction.bandits", &"shooter"), -10.0, 0.001,
		"the bandits' default opinion of a stranger"
	)
	assert_almost_eq(
		factions.get_reputation(&"faction.watch", &"shooter"), 0.0, 0.001,
		"and the watch has no opinion at all"
	)

	_empty_the_sidearm_into_the_bandit()

	assert_almost_eq(
		heat.get_heat(&"shooter", &"faction.bandits"), 60.0, 0.001,
		"CombatCrimeAdapter reported the killing to the bandits' own law"
	)
	assert_almost_eq(
		factions.get_reputation(&"faction.bandits", &"shooter"), -40.0, 0.001,
		"CrimeFactionAdapter spent the reputation cost with the wronged faction"
	)
	assert_almost_eq(
		factions.get_reputation(&"faction.watch", &"shooter"), 12.0, 0.001,
		"and propagation paid the watch, who hate bandits, for the same killing"
	)


# --- 6: mission -----------------------------------------------------------

func test_one_shot_finishes_a_mission_that_spans_combat_and_progression() -> void:
	# The gate. Missions names neither Combat nor Progression; it matches two
	# event names off the bus, and both arrive because one trigger was pulled.
	missions.default_subject = shooter
	assert_ok(missions.start(_bounty_mission()), "the bounty is taken")

	var runtime := missions.get_runtime(&"mission.bounty")
	assert_not_null(runtime, "and is tracked")
	assert_false(runtime.is_finished(), "with nothing done yet")

	_empty_the_sidearm_into_the_bandit()

	assert_true(
		missions.has_completed(&"mission.bounty"),
		"the kill and the level both landed, so the bounty is finished"
	)
	assert_false(missions.is_active(&"mission.bounty"), "and it is off the active list")


func test_the_mission_stalls_when_the_death_is_never_promoted() -> void:
	# HealthEventAdapter is a component a project can delete. Switch its
	# promotion off and the bandit still dies -- everything downstream of the
	# bus stops, which is the failure mode the seam is supposed to have.
	obituary.publish_death = false
	missions.default_subject = shooter
	assert_ok(missions.start(_bounty_mission()))

	_empty_the_sidearm_into_the_bandit()

	assert_true(bandit_health.is_dead(), "the bandit died all the same")
	assert_eq(corpse_bag.count(&"item.bandit_carbine"), 1, "and still dropped its loot")
	assert_almost_eq(
		progression.get_experience(&"track.gunplay"), 0.0, 0.001,
		"but nothing heard about it, so no experience was paid"
	)
	assert_almost_eq(
		factions.get_reputation(&"faction.bandits", &"shooter"), -10.0, 0.001,
		"and no standing moved"
	)
	assert_false(
		missions.has_completed(&"mission.bounty"), "so the bounty is still open"
	)


func test_the_mission_stalls_when_the_level_is_never_promoted() -> void:
	# The other seam, and a sharper failure: the shooter genuinely levels, the
	# kill objective genuinely completes, and the mission is still unfinished
	# because nobody put the level on the bus.
	promoter.publish_levels = false
	missions.default_subject = shooter
	assert_ok(missions.start(_bounty_mission()))

	_empty_the_sidearm_into_the_bandit()

	assert_eq(
		progression.get_level(&"track.gunplay"), 2, "the shooter did reach level 2"
	)
	var runtime := missions.get_runtime(&"mission.bounty")
	assert_not_null(runtime, "the mission is still under way")
	assert_true(
		runtime.get_objective(&"objective.kill_bandits").is_complete(),
		"the combat objective completed"
	)
	assert_false(
		runtime.get_objective(&"objective.make_corporal").is_complete(),
		"the progression objective did not, because the level never reached the bus"
	)
	assert_false(missions.has_completed(&"mission.bounty"), "so the bounty is unfinished")
