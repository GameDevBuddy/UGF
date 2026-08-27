extends FrameworkTestCase
## Vertical slice D of Implementation Plan 36: the sandbox loop, from the car
## door to the save file.
##
## Every module used here already passes its own suite. What this one asks is
## whether they compose. Getting in is Interaction's pipeline moving Input's
## context stack and Vehicles' seats; driving is the same input seam traffic AI
## drives through; the purchase is Commerce moving a wallet and a bag and
## announcing it on the bus; the killing outside the shop is Health publishing
## a death that Crime hears, Factions pays for and AI acts on; and the save is
## the persistence platform carrying all of it without naming any of it.
##
## [b]The chain is the assertion.[/b] Each step asserts what the step before it
## made possible — the engine is running because a driver sat down, the shop is
## in reach because the car was driven there, the constable is hostile because
## a reputation moved — so a link that quietly stops working fails here rather
## than surviving as a module whose own tests all still pass. The hostility
## check in particular is asserted before as well as after: a guard that was
## always going to attack proves nothing about crime.
##
## Two things here are the test's own. It moves the car, because
## [VehicleControllerAdapter] integrates speed and heading and deliberately
## applies neither — moving a body is a body's job, and a slice that needed a
## physics world would not run headless (rule 33). And it tells the world
## service where the observer is, because nothing in the framework polls a
## position to drive streaming; what is under test there is the answer, not the
## asking. Everything above those two lines is the framework's own.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const FakeInputSource := preload("res://tests/support/fake_input_source.gd")

const SUBURB: StringName = &"region.suburb"
const DOCKS: StringName = &"region.docks"
const POLICE: StringName = &"faction.police"
const PLAYER_ID: StringName = &"player"
const GOLD: StringName = &"currency.gold"
const REPAIR_KIT: StringName = &"item.repair_kit"

## Where the shop stands. Far enough that the car has to be driven there.
const SHOP_POSITION: Vector3 = Vector3(0.0, 0.0, 60.0)

var bus: Node = null
var core: Node = null
var source: InputSource = null
var router: InputRouter = null

var factions: FactionService = null
var heat: HeatService = null
var world: WorldStateService = null
var commerce: CommerceService = null
var saves: SaveService = null
var consequences: CrimeFactionAdapter = null
var killings: CombatCrimeAdapter = null

var player: Node3D = null
var car: Node3D = null
var shop: Node3D = null
var shopkeeper: Node3D = null
var bystander: Node3D = null
var constable: Node3D = null

var vehicle: VehicleComponent = null
var seats: SeatComponent = null
var driver: VehicleControllerComponent = null

## What the bus and the law were told, captured through their own signals
## rather than inspected afterwards.
var purchases: Array = []
var reports: Array = []


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	bus.register_event(GameplayNames.EVENT_ACTOR_DIED)
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	core.get_definition_registry().register(CommerceFixtures.gold())
	core.get_definition_registry().register(_repair_kit())

	source = FakeInputSource.new()
	router = InputRouter.new(source)
	add_test_node(router)
	# The stack is left empty on purpose. Seeding it with an on-foot context
	# here would pre-satisfy the first assertion of the slice, and what that
	# assertion is for is that the character's own controller is the thing
	# which puts a context on the router.
	core.register_service(GameplayNames.SERVICE_INPUT, router)

	factions = CrimeFixtures.factions()
	heat = CrimeFixtures.heat_service()
	world = WorldFixtures.world([
		_region(SUBURB, Vector3.ZERO), _region(DOCKS, SHOP_POSITION)
	])
	commerce = CommerceService.new()
	commerce.name = "CommerceService"
	for service in [factions, heat, world, commerce]:
		add_test_node(service)
	commerce.configure(core, bus, factions)
	core.register_service(GameplayNames.SERVICE_FACTION, factions)
	core.register_service(GameplayNames.SERVICE_CRIME, heat)
	core.register_service(GameplayNames.SERVICE_WORLD_STATE, world)
	core.register_service(GameplayNames.SERVICE_COMMERCE, commerce)

	# The town starts awake around the player and asleep around the docks, so
	# the drive has somewhere to arrive.
	world.refresh_activation(Vector3.ZERO)

	# The two deletable files that connect the law to everything else.
	consequences = CrimeFactionAdapter.new()
	consequences.name = "CrimeFactionAdapter"
	consequences.heat = heat
	consequences.factions = factions
	add_test_node(consequences)

	_build_world()

	killings = CombatCrimeAdapter.new()
	killings.name = "CombatCrimeAdapter"
	killings.heat = heat
	killings.event_bus = bus
	killings.murder = CrimeFixtures.crime(&"crime.murder", 60.0, 60.0)
	killings.witness_range = 30.0
	add_test_node(killings)
	killings.register_witness(CrimeFixtures.witness_of(bystander))

	bus.subscribe(
		GameplayNames.EVENT_ITEM_PURCHASED,
		func(event: FrameworkEvent) -> void: purchases.append(event)
	)
	heat.crime_reported.connect(
		func(context: CrimeContext) -> void: reports.append(context)
	)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)
	for pair in [
		[GameplayNames.SERVICE_CRIME, heat],
		[GameplayNames.SERVICE_FACTION, factions],
		[GameplayNames.SERVICE_WORLD_STATE, world],
	]:
		assert_ok(saves.register_service(pair[0], pair[1]))
	assert_ok(saves.register_entity(player))
	assert_ok(saves.register_entity(car))


# --- The slice ------------------------------------------------------------

func test_the_sandbox_loop_holds_from_the_car_door_to_the_save() -> void:
	var walker := _find(player, CharacterController) as CharacterController
	var hands := _find(player, InteractorComponent) as InteractorComponent
	var purse := CommerceFixtures.wallet_of(player)
	var bag := CommerceFixtures.inventory_of(player)
	var fuel := VehicleFixtures.fuel_of(car)
	var door := VehicleFixtures.find(car, InteractionComponent) as InteractionComponent
	var region := VehicleFixtures.find(car, RegionTracker) as RegionTracker
	var counter := _find(shop, InteractionComponent) as InteractionComponent
	var brain := (
		CrimeFixtures.find(constable, AIControllerComponent) as AIControllerComponent
	)
	var politics := (
		CrimeFixtures.find(constable, FactionAIAdapter) as FactionAIAdapter
	).get_provider()

	# --- 1. Enter the vehicle ---------------------------------------------
	assert_eq(router.get_depth(), 0, "nothing is holding the input stack yet")
	assert_ok(walker.take_control(), "the player starts the slice on foot")
	assert_eq(
		router.get_active_context_id(),
		GameplayNames.INPUT_CONTEXT_ON_FOOT,
		"holding the walking input context, which is the context it pushed itself"
	)
	assert_eq(router.get_depth(), 1, "one deep, because one controller has control")
	assert_false(vehicle.is_running(), "beside a parked car with its engine off")
	assert_eq(region.get_region_id(), SUBURB, "parked in the suburb it is about to leave")
	assert_false(world.is_active(DOCKS), "and the docks asleep on the far side of town")

	assert_ok(hands.begin(door), "pressing use on the car runs M5's interaction pipeline")
	assert_eq(seats.get_driver(), player, "which seated the player in the driver's seat")
	assert_false(walker.is_controlling(), "the character let go of the input stack")
	assert_true(driver.is_controlling(), "and the vehicle's controller took it")
	assert_eq(
		router.get_active_context_id(),
		GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER,
		"so the driving context is what input now resolves against"
	)
	assert_eq(
		router.get_depth(),
		1,
		"still one deep: the character let go before the vehicle took hold, "
		+ "so no player is ever two contexts deep in their own car"
	)
	assert_true(vehicle.is_running(), "a driver in the seat started the engine")

	# --- 2. Drive ---------------------------------------------------------
	var full_tank := fuel.get_level()
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	var arrived := false
	var driven := 0
	for step in 300:
		_advance(0.1)
		driven += 1
		if car.global_position.distance_to(SHOP_POSITION) <= 8.0:
			arrived = true
			break
	assert_true(
		arrived, "throttle through the input seam drove the car the 58m to the shop"
	)
	var cruising := vehicle.get_speed()
	assert_almost_eq(
		cruising,
		vehicle.get_handling().max_speed,
		0.001,
		"at the whole of the throttle the seam handed it rather than a fraction of one"
	)
	var throttled := full_tank - fuel.get_level()

	# Coasting first, for two reasons. Drag alone stops this car in three
	# seconds, so a handbrake measured over a longer window than that proves
	# nothing about the handbrake; and an engine burning fuel with the throttle
	# shut is the other half of what the solver does with a throttle.
	source.release(GameplayNames.ACTION_MOVE_FORWARD)
	var before_coasting := fuel.get_level()
	for step in 5:
		_advance(0.1)
	var coasting := vehicle.get_speed()
	var idled := before_coasting - fuel.get_level()
	assert_true(
		coasting > 0.5, "half a second off the throttle leaves the car still rolling"
	)

	source.press(GameplayNames.ACTION_JUMP)
	for step in 5:
		_advance(0.1)
		if vehicle.get_speed() <= 0.5:
			break
	source.release(GameplayNames.ACTION_JUMP)
	assert_almost_eq(
		vehicle.get_speed(),
		0.0,
		0.5,
		(
			"the handbrake, on the same seam, stopped it inside the half second "
			+ "in which coasting only took it from %.1f to %.1f m/s"
		) % [cruising, coasting]
	)
	assert_true(fuel.get_level() < full_tank, "and the drive cost fuel")
	assert_true(idled > 0.0, "an engine left running burns fuel with the throttle shut")
	assert_true(
		throttled / float(driven) > (idled / 5.0) * 2.0,
		(
			"burned by the throttle rather than by the clock: %.3f a step under "
			+ "power against %.3f a step idling"
		) % [throttled / float(driven), idled / 5.0]
	)

	# Streaming is the project's job: nothing in the framework polls positions,
	# so the test is the observer here. What is under test is the world service
	# answering a distance question about where the drive ended -- and, through
	# the tracker, the car reporting its own region, which is the framework's
	# own way round.
	world.refresh_activation(car.global_position)
	assert_true(world.is_active(DOCKS), "the drive woke the region it arrived in")
	assert_false(world.is_active(SUBURB), "and put the one it left to sleep")
	assert_true(region.refresh(), "the car, asked where it is, finds it has moved")
	assert_eq(
		region.get_region_id(),
		DOCKS,
		"the car covered real ground rather than sitting still with the wheels "
		+ "turning: it reports the docks now and reported the suburb when parked"
	)

	# --- 3. Vendor --------------------------------------------------------
	assert_ok(hands.begin(door), "pressing use again gets back out")
	assert_false(seats.contains(player), "leaving the seat empty")
	assert_true(walker.is_controlling(), "the character has its own context back")
	assert_eq(
		router.get_active_context_id(),
		GameplayNames.INPUT_CONTEXT_ON_FOOT,
		"and the stack is where it was before the journey"
	)
	assert_eq(router.get_depth(), 1, "one deep again, not a context left behind")

	var vendor := CommerceFixtures.vendor_of(shop)
	# The car is stopped at the kerb and the seat put the player out beside it,
	# a couple of metres from the counter and inside the reach an interactor
	# ships with. Standing where the slice started they are 58 metres short of
	# it, and this is the line that says so.
	assert_ok(
		hands.begin(counter),
		"the shop is close enough to press use on, which is the whole of why "
		+ "the drive had to happen: M5 refuses a target out of reach"
	)
	assert_true(vendor.is_open(), "and TradeAction opened it for whoever walked up")
	assert_eq(vendor.get_customer(), player, "the player being the one who did")

	var quoted := commerce.quote(player, shop, REPAIR_KIT)
	assert_ok(quoted, "the shop quotes a price for what is on its shelf")
	var bill := (quoted.payload as TradeContext).total
	assert_true(bill > 0.0, "and it is not giving stock away")
	var before_purse := purse.get_balance(GOLD)
	var before_stock := vendor.find_stock(REPAIR_KIT).quantity

	assert_ok(commerce.buy(player, shop, REPAIR_KIT), "the purchase goes through")
	assert_almost_eq(
		purse.get_balance(GOLD),
		before_purse - bill,
		0.001,
		"the wallet paid exactly what it was quoted"
	)
	assert_eq(bag.count(REPAIR_KIT), 1, "the goods are in the player's inventory")
	assert_eq(
		vendor.find_stock(REPAIR_KIT).quantity,
		before_stock - 1,
		"and off the vendor's shelf"
	)
	assert_size(purchases, 1, "and the trade was announced on the bus as item_purchased")

	# --- 4. Crime ---------------------------------------------------------
	assert_almost_eq(
		heat.get_heat(PLAYER_ID, POLICE), 0.0, 0.001, "the player has no record yet"
	)
	assert_false(
		politics.is_hostile(constable, player),
		"the constable's politics give him no quarrel with the player"
	)
	assert_false(
		brain.get_hostility_provider().is_hostile(constable, player),
		"and neither does the law hook wrapped over them"
	)

	var wound := DamageContext.create(500.0, player)
	assert_ok(
		_receiver(shopkeeper).receive(wound),
		"the player shoots the shopkeeper on the way out"
	)
	assert_true(_health(shopkeeper).is_dead(), "who dies of it")
	assert_size(
		reports,
		1,
		"and the death reached the law: health signalled, its adapter published, "
		+ "and CombatCrimeAdapter turned one bus event into one crime report"
	)
	if reports.is_empty():
		# Nothing below here means anything without a report, and reading one
		# that is not there would end the run in an engine error rather than a
		# failure somebody can act on.
		return

	var report := reports[0] as CrimeContext
	assert_has(
		report.witnesses,
		bystander,
		"the bystander is on the report because the WitnessComponent could see it"
	)
	assert_almost_eq(
		heat.get_heat(PLAYER_ID, POLICE), 60.0, 0.001, "the offence is on the record"
	)
	assert_true(heat.is_wanted(PLAYER_ID, POLICE), "and the player is wanted for it")
	assert_eq(
		heat.get_tier(PLAYER_ID, POLICE).state,
		GameplayNames.STATE_WANTED,
		"at the rung the heat ladder puts 60 points on"
	)

	# --- 5. Faction and AI response ---------------------------------------
	assert_almost_eq(
		factions.get_reputation(POLICE, PLAYER_ID),
		-60.0,
		0.001,
		"CrimeFactionAdapter spent the offence's reputation cost with the wronged faction"
	)
	assert_true(
		politics.is_hostile(constable, player),
		"which alone is enough for the constable's faction politics to turn hostile"
	)
	assert_true(
		brain.get_hostility_provider().is_hostile(constable, player),
		"so the brain's provider — the only thing AI ever asks — now answers enemy"
	)
	# Read as a number rather than as a yes: is_hostile saturates at true, so it
	# cannot show whether the law hook is adding to the politics underneath it
	# or has replaced them. A hostile standing is worth 1.5 and the warrant adds
	# the adapter's bonus on top, and only both halves working reads 2.5.
	assert_almost_eq(
		brain.get_hostility_provider().get_threat_scale(constable, player),
		AttitudeSolver.threat_scale(AttitudeSolver.Attitude.HOSTILE) + 1.0,
		0.001,
		"reading the player as a hostile the law also wants, rather than as one or the other"
	)

	# --- 6. Save ----------------------------------------------------------
	var burnt := fuel.get_level()
	assert_ok(saves.save(&"slot_sandbox"), "the whole session writes to a slot")

	heat.clear()
	factions.reset()
	purse.set_balance(GOLD, 0.0)
	bag.clear()
	fuel.fill()
	world.set_active(DOCKS, false)
	world.set_active(SUBURB, true)
	assert_false(heat.is_wanted(PLAYER_ID, POLICE), "the session is genuinely wiped")
	assert_false(
		politics.is_hostile(constable, player),
		"the constable's politics along with it"
	)
	assert_false(
		brain.get_hostility_provider().is_hostile(constable, player),
		"and the constable has forgotten the player entirely"
	)

	assert_ok(saves.load_slot(&"slot_sandbox"), "and loads back")
	assert_almost_eq(heat.get_heat(PLAYER_ID, POLICE), 60.0, 0.001, "heat came back")
	assert_true(heat.is_wanted(PLAYER_ID, POLICE), "with the warrant still standing")
	assert_almost_eq(
		factions.get_reputation(POLICE, PLAYER_ID), -60.0, 0.001, "reputation came back"
	)
	assert_almost_eq(
		purse.get_balance(GOLD), before_purse - bill, 0.001, "the wallet came back"
	)
	assert_eq(bag.count(REPAIR_KIT), 1, "the purchase came back")
	assert_almost_eq(
		fuel.get_level(), burnt, 0.001, "the tank came back where the drive left it"
	)
	assert_true(world.is_active(DOCKS), "the world came back awake where the drive left it")
	assert_false(world.is_active(SUBURB), "and asleep where it did not")
	assert_true(
		politics.is_hostile(constable, player),
		"the restored reputation is hostile again through the seam AI reads it by"
	)
	assert_true(
		brain.get_hostility_provider().is_hostile(constable, player),
		"and the constable, reading the restored services, still wants the player"
	)


func test_a_killing_nobody_sees_moves_none_of_it() -> void:
	# The witness is a load-bearing link rather than a formality. The same
	# killing with the only bystander out of sight produces no report, no
	# reputation loss and no change of mind — which is a stealth game working,
	# and the reason the chain above cannot be satisfied by a shortcut.
	bystander.global_position = Vector3(0.0, 0.0, 500.0)
	var brain := (
		CrimeFixtures.find(constable, AIControllerComponent) as AIControllerComponent
	)

	assert_ok(_receiver(shopkeeper).receive(DamageContext.create(500.0, player)))
	assert_true(_health(shopkeeper).is_dead(), "the shopkeeper dies just the same")
	assert_empty(reports, "but nobody reported it")
	assert_almost_eq(
		heat.get_heat(PLAYER_ID, POLICE), 0.0, 0.001, "so there is no heat"
	)
	assert_almost_eq(
		factions.get_reputation(POLICE, PLAYER_ID), 0.0, 0.001, "and no reputation lost"
	)
	assert_false(
		brain.get_hostility_provider().is_hostile(constable, player),
		"and the constable has no reason to mind"
	)


# --- Driving --------------------------------------------------------------

## One step of driving.
##
## [VehicleControllerAdapter] integrates speed and heading and applies neither:
## a vehicle with no physics body moves nothing, by design. The test stands in
## for the body, and for the seat attachment that carries whoever is aboard, so
## that every decision above this line — throttle, heading, fuel — is still the
## framework's.
func _advance(delta: float) -> void:
	driver.drive(delta)
	vehicle.tick(delta)
	var travel := vehicle.adapter.get_velocity() * delta
	car.global_position += travel
	for occupant in seats.get_occupants():
		var rider := occupant as Node3D
		if rider != null:
			rider.global_position += travel


# --- The world ------------------------------------------------------------

func _build_world() -> void:
	player = _player()
	player.position = Vector3.ZERO
	add_test_node(player)
	_assemble(player)

	car = VehicleFixtures.vehicle("Sedan", _sedan(), false, true)
	car.position = Vector3(0.0, 0.0, 2.0)
	add_test_node(car)
	VehicleFixtures.interactable(car, [_enter_interaction()])
	# The car reports its own region rather than the world scanning for it,
	# which is the framework's way round and the only component standing on
	# this slice's streaming path.
	var tracker := RegionTracker.new()
	tracker.name = "RegionTracker"
	tracker.world = world
	tracker.auto_tick = false
	car.add_child(tracker)
	VehicleFixtures.assemble(car, core)
	vehicle = VehicleFixtures.vehicle_of(car)
	seats = VehicleFixtures.seats_of(car)
	driver = (
		VehicleFixtures.find(car, VehicleControllerComponent) as VehicleControllerComponent
	)

	shop = CommerceFixtures.vendor(
		"Pawnbroker",
		CommerceFixtures.vendor_definition(
			&"vendor.pawnbroker", [CommerceFixtures.stock(REPAIR_KIT, 3)]
		),
		500.0
	)
	shop.position = SHOP_POSITION
	var counter := InteractionComponent.new()
	counter.name = "InteractionComponent"
	var offers: Array[InteractionDefinition] = [_trade_interaction()]
	counter.interactions_override = offers
	counter.auto_tick = false
	shop.add_child(counter)
	add_test_node(shop)
	CommerceFixtures.assemble(shop, core)

	# Standing outside the shop: somebody to kill, and somebody to tell.
	shopkeeper = _victim()
	shopkeeper.position = SHOP_POSITION + Vector3(0.0, 0.0, -2.0)
	add_test_node(shopkeeper)
	_assemble(shopkeeper)

	bystander = CrimeFixtures.witness("Bystander", heat, 20.0)
	bystander.position = SHOP_POSITION + Vector3(0.0, 0.0, -6.0)
	add_test_node(bystander)
	_assemble(bystander)

	constable = CrimeFixtures.guard("Constable", heat, POLICE, factions)
	constable.position = Vector3(20.0, 0.0, 30.0)
	add_test_node(constable)
	_assemble(constable)


## A player: a name the law can use, a wallet, a bag, hands, and a controller
## holding the input stack.
func _player() -> Node3D:
	var entity := Node3D.new()
	entity.name = "Player"

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = PLAYER_ID
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var movement := MovementComponent.new()
	movement.name = "MovementComponent"
	movement.semantic_state = state
	movement.auto_tick = false
	entity.add_child(movement)

	var controller := CharacterController.new()
	controller.name = "CharacterController"
	controller.movement = movement
	entity.add_child(controller)

	var hands := InteractorComponent.new()
	hands.name = "InteractorComponent"
	hands.auto_tick = false
	entity.add_child(hands)

	entity.add_child(CommerceFixtures.wallet(200.0))

	var bag := InventoryComponent.new()
	bag.name = "InventoryComponent"
	bag.profile_override = ItemFixtures.container(20)
	entity.add_child(bag)

	# The name a warrant is pinned to and the name reputation accrues to are
	# the same one, and this component owns it.
	var mark := FactionComponent.new()
	mark.name = "FactionComponent"
	mark.actor_id = PLAYER_ID
	mark.service = factions
	entity.add_child(mark)
	return entity


## Somebody who can be killed, and whose death the rest of the game hears.
##
## The [HealthEventAdapter] is the whole reason the crime step works: without
## it the shopkeeper still dies and nothing outside the entity ever knows.
func _victim() -> Node3D:
	var entity := CrimeFixtures.actor("Shopkeeper")

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 80.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)

	var events := HealthEventAdapter.new()
	events.name = "HealthEventAdapter"
	events.health = health
	events.event_bus = bus
	entity.add_child(events)
	return entity


# --- Content --------------------------------------------------------------

## A slow car on a large tank. Slow so the drive stops where the shop is rather
## than through it; large so a long drive does not run the engine dry mid-slice.
func _sedan() -> VehicleDefinition:
	var definition := VehicleFixtures.definition(&"vehicle.sedan", 2, 50.0)
	definition.handling = VehicleFixtures.handling(12.0, 8.0)
	return definition


## Getting in and out, through the same interaction both ways.
##
## Built here rather than taken from [VehicleFixtures] for one reason: this
## slice needs the occupant actually placed, so that getting out at the end of
## the drive leaves the player standing at the shop instead of back where the
## car was parked.
func _enter_interaction() -> InteractionDefinition:
	var interaction := InteractionDefinition.new()
	interaction.id = &"interaction.enter_vehicle"
	interaction.display_name = "Enter"
	interaction.verb = GameplayNames.VERB_ENTER
	interaction.prompt = "Get in"
	var action := EnterVehicleAction.new()
	action.toggles = true
	action.move_occupant = true
	interaction.action = action
	return interaction


## Trading, through the same pipeline the car door is opened with.
##
## [TradeAction] is the framework's own route from an interactor to
## [CommerceService], and going straight to the service instead would leave the
## purchase reachable from anywhere on the map -- nothing in
## [method CommerceService.validate] asks where the customer is standing.
func _trade_interaction() -> InteractionDefinition:
	var interaction := InteractionDefinition.new()
	interaction.id = &"interaction.trade"
	interaction.display_name = "Trade"
	interaction.verb = GameplayNames.VERB_TALK
	interaction.prompt = "Trade"
	interaction.action = TradeAction.new()
	return interaction


func _repair_kit() -> ItemDefinition:
	var definition := ItemFixtures.unique(REPAIR_KIT)
	definition.category = &"item.misc"
	definition.base_value = 45.0
	return definition


func _region(id: StringName, centre: Vector3) -> RegionDefinition:
	var definition := WorldFixtures.region(
		id, [&"region.urban"], {&"population.ambient": 8}, centre, 10.0
	)
	definition.activation_distance = 25.0
	return definition


# --- Lookups --------------------------------------------------------------

func _assemble(entity: Node) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


func _find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


func _receiver(entity: Node) -> DamageReceiverComponent:
	return _find(entity, DamageReceiverComponent) as DamageReceiverComponent


func _health(entity: Node) -> HealthComponent:
	return _find(entity, HealthComponent) as HealthComponent
