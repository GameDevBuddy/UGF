extends FrameworkTestCase
## Covers CommerceService and VendorComponent, and holds the M11 exit gate:
## atomic purchase and sale, restocking, and reputation pricing.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var bus: Node = null
var core: Node = null
var factions: FactionService = null
var commerce: CommerceService = null
var shop: Node3D = null
var vendor: VendorComponent = null
var player: Node3D = null
var sword: ItemDefinition = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	sword = ItemFixtures.unique(&"item.sword")
	sword.category = &"item.weapon"
	sword.base_value = 50.0
	core.get_definition_registry().register(sword)
	core.get_definition_registry().register(CommerceFixtures.gold())

	factions = FactionFixtures.service()
	add_test_node(factions)

	commerce = CommerceService.new()
	add_test_node(commerce)
	commerce.configure(core, bus, factions)

	shop = add_test_node(
		CommerceFixtures.vendor(
			"Smith",
			CommerceFixtures.vendor_definition(
				&"vendor.smith", [CommerceFixtures.stock(&"item.sword", 3)]
			),
			500.0
		)
	) as Node3D
	CommerceFixtures.assemble(shop, core)
	vendor = CommerceFixtures.vendor_of(shop)

	player = add_test_node(CommerceFixtures.customer("Player", 200.0)) as Node3D
	CommerceFixtures.assemble(player, core)


func _purse() -> float:
	return CommerceFixtures.wallet_of(player).get_balance(&"currency.gold")


func _bag() -> InventoryComponent:
	return CommerceFixtures.inventory_of(player)


# --- Quoting --------------------------------------------------------------

func test_a_quote_applies_the_markup() -> void:
	var quoted := commerce.quote(player, shop, &"item.sword")
	assert_ok(quoted)
	assert_almost_eq((quoted.payload as TradeContext).unit_price, 100.0)


func test_a_quote_changes_nothing() -> void:
	# A shop UI asks this for every line it draws.
	for repeat in 5:
		commerce.quote(player, shop, &"item.sword")
	assert_almost_eq(_purse(), 200.0)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 3)


func test_a_stock_line_can_override_the_price() -> void:
	vendor.find_stock(&"item.sword").price_override = 10.0
	var quoted := commerce.quote(player, shop, &"item.sword")
	assert_almost_eq((quoted.payload as TradeContext).unit_price, 20.0)


func test_selling_uses_the_markdown() -> void:
	var quoted := commerce.quote(
		player, shop, &"item.sword", 1, TradeContext.Direction.SELL
	)
	assert_almost_eq((quoted.payload as TradeContext).unit_price, 25.0)


func test_quoting_something_unregistered_is_refused() -> void:
	assert_err(commerce.quote(player, shop, &"item.nothing"), &"commerce.unknown_item")


func test_quoting_at_something_that_is_not_a_shop_is_refused() -> void:
	var rock := add_test_node(Node3D.new())
	assert_err(commerce.quote(player, rock, &"item.sword"), &"commerce.not_a_vendor")


# --- Buying ---------------------------------------------------------------

func test_a_purchase_moves_money_stock_and_goods() -> void:
	assert_ok(commerce.buy(player, shop, &"item.sword"))
	assert_almost_eq(_purse(), 100.0)
	assert_almost_eq(
		CommerceFixtures.wallet_of(shop).get_balance(&"currency.gold"), 600.0
	)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 2)
	assert_eq(_bag().count(&"item.sword"), 1)


func test_buying_several_at_once() -> void:
	var arrows := ItemFixtures.stackable(&"item.arrow", 99)
	arrows.base_value = 1.0
	core.get_definition_registry().register(arrows)
	vendor.give_stock(&"item.arrow", 50)

	assert_ok(commerce.buy(player, shop, &"item.arrow", 20))
	assert_eq(_bag().count(&"item.arrow"), 20)
	assert_almost_eq(_purse(), 160.0)


func test_unlimited_stock_never_runs_out() -> void:
	CommerceFixtures.wallet_of(player).set_balance(&"currency.gold", 1000.0)
	vendor.find_stock(&"item.sword").quantity = -1
	for purchase in 3:
		assert_ok(commerce.buy(player, shop, &"item.sword"))
	assert_true(vendor.find_stock(&"item.sword").is_unlimited())


# --- Atomicity ------------------------------------------------------------

func test_a_purchase_that_cannot_be_afforded_changes_nothing() -> void:
	CommerceFixtures.wallet_of(player).set_balance(&"currency.gold", 10.0)
	assert_err(commerce.buy(player, shop, &"item.sword"), &"commerce.insufficient_funds")

	assert_almost_eq(_purse(), 10.0)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 3)
	assert_eq(_bag().count(&"item.sword"), 0)


func test_a_purchase_the_bag_cannot_hold_changes_nothing() -> void:
	# The bug this whole shape exists to prevent: money taken, then the bag
	# found full.
	var tiny := add_test_node(CommerceFixtures.customer("Pauper", 9999.0)) as Node3D
	CommerceFixtures.inventory_of(tiny).profile_override = ItemFixtures.container(1)
	CommerceFixtures.assemble(tiny, core)
	CommerceFixtures.inventory_of(tiny).add(ItemInstance.create(sword, 1))

	var before := CommerceFixtures.wallet_of(tiny).get_balance(&"currency.gold")
	assert_err(commerce.buy(tiny, shop, &"item.sword"))
	assert_almost_eq(CommerceFixtures.wallet_of(tiny).get_balance(&"currency.gold"), before)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 3)


func test_buying_more_than_is_stocked_changes_nothing() -> void:
	assert_err(commerce.buy(player, shop, &"item.sword", 10), &"commerce.out_of_stock")
	assert_almost_eq(_purse(), 200.0)
	assert_eq(_bag().count(&"item.sword"), 0)


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array[StringName] = []
	commerce.trade_refused.connect(
		func(_c: TradeContext, reason: StringName) -> void: refusals.append(reason)
	)
	CommerceFixtures.wallet_of(player).set_balance(&"currency.gold", 0.0)
	commerce.buy(player, shop, &"item.sword")
	assert_size(refusals, 1)
	assert_eq(refusals[0], &"commerce.insufficient_funds")


# --- Selling --------------------------------------------------------------

func test_a_sale_moves_money_goods_and_stock() -> void:
	_bag().add(ItemInstance.create(sword, 1))
	assert_ok(commerce.sell(player, shop, &"item.sword"))

	assert_almost_eq(_purse(), 225.0)
	assert_almost_eq(
		CommerceFixtures.wallet_of(shop).get_balance(&"currency.gold"), 475.0
	)
	assert_eq(_bag().count(&"item.sword"), 0)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 4)


func test_selling_something_you_do_not_have_changes_nothing() -> void:
	assert_err(commerce.sell(player, shop, &"item.sword"), &"commerce.nothing_to_sell")
	assert_almost_eq(_purse(), 200.0)


func test_a_vendor_that_cannot_pay_refuses() -> void:
	CommerceFixtures.wallet_of(shop).set_balance(&"currency.gold", 5.0)
	var definition := vendor.get_vendor()
	definition.purse = 5.0
	_bag().add(ItemInstance.create(sword, 1))

	assert_err(commerce.sell(player, shop, &"item.sword"), &"commerce.vendor_broke")
	assert_eq(_bag().count(&"item.sword"), 1)


func test_a_fence_grows_a_line_for_something_it_never_stocked() -> void:
	var trinket := ItemFixtures.unique(&"item.trinket")
	trinket.base_value = 10.0
	core.get_definition_registry().register(trinket)
	_bag().add(ItemInstance.create(trinket, 1))

	assert_ok(commerce.sell(player, shop, &"item.trinket"))
	assert_not_null(vendor.find_stock(&"item.trinket"))
	assert_eq(vendor.find_stock(&"item.trinket").quantity, 1)


func test_a_vendor_can_refuse_a_whole_category() -> void:
	var policy := vendor.get_pricing() as StandardPricingPolicy
	var accepted: Array[StringName] = [&"item.weapon"]
	policy.buys_categories = accepted

	var vegetable := ItemFixtures.stackable(&"item.turnip", 99)
	vegetable.category = &"item.food"
	vegetable.base_value = 1.0
	core.get_definition_registry().register(vegetable)
	_bag().add(ItemInstance.create(vegetable, 1))

	assert_err(commerce.sell(player, shop, &"item.turnip"), &"commerce.not_accepted")
	assert_ok(commerce.quote(player, shop, &"item.sword", 1, TradeContext.Direction.SELL))


# --- Restocking -----------------------------------------------------------

func test_a_shelf_refills_on_its_interval() -> void:
	var definition := CommerceFixtures.vendor_definition(
		&"vendor.timed", [CommerceFixtures.stock(&"item.sword", 3)], 10.0
	)
	var timed_shop := add_test_node(CommerceFixtures.vendor("Timed", definition)) as Node3D
	CommerceFixtures.assemble(timed_shop, core)
	var timed := CommerceFixtures.vendor_of(timed_shop)

	timed.take_stock(&"item.sword", 3)
	assert_eq(timed.find_stock(&"item.sword").quantity, 0)

	timed.tick(5.0)
	assert_eq(timed.find_stock(&"item.sword").quantity, 0)
	timed.tick(6.0)
	assert_eq(timed.find_stock(&"item.sword").quantity, 3)


func test_restocking_is_announced() -> void:
	var definition := CommerceFixtures.vendor_definition(
		&"vendor.timed", [CommerceFixtures.stock(&"item.sword", 3)], 10.0
	)
	var timed_shop := add_test_node(CommerceFixtures.vendor("Timed", definition)) as Node3D
	CommerceFixtures.assemble(timed_shop, core)
	var timed := CommerceFixtures.vendor_of(timed_shop)

	var refills: Array[int] = []
	timed.restocked.connect(func(added: int) -> void: refills.append(added))
	timed.take_stock(&"item.sword", 2)
	timed.tick(11.0)
	assert_size(refills, 1)
	assert_eq(refills[0], 2)


func test_opening_a_shop_restocks_it_if_it_is_due() -> void:
	# A shop the player has not visited for an hour should not be empty
	# because nothing was ticking it while it was unloaded.
	var definition := CommerceFixtures.vendor_definition(
		&"vendor.timed", [CommerceFixtures.stock(&"item.sword", 3)], 10.0
	)
	var timed_shop := add_test_node(CommerceFixtures.vendor("Timed", definition)) as Node3D
	CommerceFixtures.assemble(timed_shop, core)
	var timed := CommerceFixtures.vendor_of(timed_shop)

	timed.take_stock(&"item.sword", 3)
	timed.tick(11.0)
	timed.take_stock(&"item.sword", 3)
	timed.tick(11.0)
	assert_eq(timed.find_stock(&"item.sword").quantity, 3)


func test_a_shop_that_never_restocks_stays_empty() -> void:
	vendor.take_stock(&"item.sword", 3)
	vendor.tick(1000.0)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 0)


func test_one_shop_selling_out_does_not_empty_another() -> void:
	# Live stock is a copy. Without that, a definition mutated at runtime
	# would drain every shop pointed at it (rule 2).
	var definition := CommerceFixtures.vendor_definition(
		&"vendor.shared", [CommerceFixtures.stock(&"item.sword", 3)]
	)
	var first := add_test_node(CommerceFixtures.vendor("First", definition)) as Node3D
	var second := add_test_node(CommerceFixtures.vendor("Second", definition)) as Node3D
	CommerceFixtures.assemble(first, core)
	CommerceFixtures.assemble(second, core)

	CommerceFixtures.vendor_of(first).take_stock(&"item.sword", 3)
	assert_eq(CommerceFixtures.vendor_of(second).find_stock(&"item.sword").quantity, 3)


# --- Opening and closing --------------------------------------------------

func test_opening_a_shop_announces_it_and_draws_nothing() -> void:
	var opened: Array[Node] = []
	vendor.shop_opened.connect(func(customer: Node) -> void: opened.append(customer))
	assert_ok(vendor.open(player))
	assert_true(vendor.is_open())
	assert_size(opened, 1)

	vendor.close()
	assert_false(vendor.is_open())


func test_a_vendor_serves_one_customer_at_a_time() -> void:
	vendor.open(player)
	assert_err(vendor.open(add_test_node(Node3D.new())), &"vendor.busy")


func test_a_shop_is_opened_through_the_same_interaction_a_door_uses() -> void:
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	var trade := InteractionFixtures.definition(
		&"interaction.trade", GameplayNames.VERB_USE, "Trade"
	)
	trade.action = TradeAction.new()
	var offered: Array[InteractionDefinition] = [trade]
	interaction.interactions_override = offered
	interaction.auto_tick = false
	shop.add_child(interaction)
	interaction.initialize(EntityContext.create(shop))

	assert_ok(interaction.interact_by(player))
	assert_true(vendor.is_open())
	assert_eq(vendor.get_customer(), player)


# --- Reputation pricing ---------------------------------------------------

func test_a_liked_customer_pays_less_and_is_paid_more() -> void:
	# The M10 adapter, spent. A shop that likes you charges less and pays
	# more; applying the same multiplier both ways would have it paying less
	# the more it liked you.
	var friendly_shop := add_test_node(
		CommerceFixtures.vendor(
			"Merchant",
			CommerceFixtures.vendor_definition(
				&"vendor.merchant", [CommerceFixtures.stock(&"item.sword", 5)]
			),
			500.0,
			&"faction.merchants",
			factions
		)
	) as Node3D
	CommerceFixtures.assemble(friendly_shop, core)

	var regular := add_test_node(
		CommerceFixtures.customer("Regular", 500.0, &"actor.regular", factions)
	) as Node3D
	CommerceFixtures.assemble(regular, core)

	var list_price := (
		commerce.quote(regular, friendly_shop, &"item.sword").payload as TradeContext
	).unit_price

	factions.set_reputation(&"faction.merchants", &"actor.regular", 80.0)
	var buy_price := (
		commerce.quote(regular, friendly_shop, &"item.sword").payload as TradeContext
	).unit_price
	assert_true(buy_price < list_price, "a friend pays less")

	var sell_price := (
		commerce.quote(
			regular, friendly_shop, &"item.sword", 1, TradeContext.Direction.SELL
		).payload as TradeContext
	).unit_price
	assert_true(sell_price > 25.0, "and is paid more")


func test_a_hated_customer_pays_more() -> void:
	var shop_with_side := add_test_node(
		CommerceFixtures.vendor(
			"Merchant",
			CommerceFixtures.vendor_definition(
				&"vendor.merchant", [CommerceFixtures.stock(&"item.sword", 5)]
			),
			500.0,
			&"faction.merchants",
			factions
		)
	) as Node3D
	CommerceFixtures.assemble(shop_with_side, core)

	var outlaw := add_test_node(
		CommerceFixtures.customer("Outlaw", 500.0, &"actor.outlaw", factions)
	) as Node3D
	CommerceFixtures.assemble(outlaw, core)

	factions.set_reputation(&"faction.merchants", &"actor.outlaw", -80.0)
	var price := (
		commerce.quote(outlaw, shop_with_side, &"item.sword").payload as TradeContext
	).unit_price
	assert_true(price > 100.0)


func test_pricing_works_with_no_factions_at_all() -> void:
	commerce.set_factions(null)
	var quoted := commerce.quote(player, shop, &"item.sword")
	assert_almost_eq((quoted.payload as TradeContext).unit_price, 100.0)


# --- Events ---------------------------------------------------------------

func test_a_purchase_reaches_the_bus() -> void:
	var received: Array[FrameworkEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_ITEM_PURCHASED,
		func(event: FrameworkEvent) -> void: received.append(event)
	)
	commerce.buy(player, shop, &"item.sword")

	assert_size(received, 1)
	assert_eq(received[0].item_id, &"item.sword")
	assert_almost_eq(received[0].total, 100.0)
	assert_eq(received[0].customer, player)


func test_a_sale_reaches_the_bus_under_its_own_name() -> void:
	var purchases: Array[FrameworkEvent] = []
	var sales: Array[FrameworkEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_ITEM_PURCHASED,
		func(event: FrameworkEvent) -> void: purchases.append(event)
	)
	bus.subscribe(
		GameplayNames.EVENT_ITEM_SOLD, func(event: FrameworkEvent) -> void: sales.append(event)
	)

	_bag().add(ItemInstance.create(sword, 1))
	commerce.sell(player, shop, &"item.sword")

	assert_empty(purchases)
	assert_size(sales, 1)


func test_a_mission_can_count_purchases_without_importing_commerce() -> void:
	# M9's objectives, reading M11's events. Neither module names the other.
	var missions := MissionService.new()
	add_test_node(missions)
	missions.configure(core, bus, null)
	missions.default_subject = player

	var objective := MissionFixtures.objective(
		&"objective.shop",
		GameplayNames.EVENT_ITEM_PURCHASED,
		[MissionFixtures.matcher(&"item_id", &"item.sword")]
	)
	missions.start(MissionFixtures.mission(&"mission.shopping", [objective]))

	commerce.buy(player, shop, &"item.sword")
	assert_true(missions.has_completed(&"mission.shopping"))


# --- Persistence ----------------------------------------------------------

func test_a_shelf_survives_a_save() -> void:
	vendor.take_stock(&"item.sword", 2)
	var saved := vendor.capture_state()

	vendor.restock()
	vendor.find_stock(&"item.sword").quantity = 3
	vendor.restore_state(saved)
	assert_eq(vendor.find_stock(&"item.sword").quantity, 1)


func test_stock_restores_by_item_id_not_by_index() -> void:
	vendor.give_stock(&"item.trinket", 4)
	var saved := vendor.capture_state()

	var rebuilt := add_test_node(
		CommerceFixtures.vendor(
			"Rebuilt",
			CommerceFixtures.vendor_definition(
				&"vendor.smith",
				[
					CommerceFixtures.stock(&"item.trinket", 0),
					CommerceFixtures.stock(&"item.sword", 0),
				]
			)
		)
	) as Node3D
	CommerceFixtures.assemble(rebuilt, core)
	CommerceFixtures.vendor_of(rebuilt).restore_state(saved)

	assert_eq(CommerceFixtures.vendor_of(rebuilt).find_stock(&"item.trinket").quantity, 4)
	assert_eq(CommerceFixtures.vendor_of(rebuilt).find_stock(&"item.sword").quantity, 3)


func test_vendors_are_persistent() -> void:
	assert_true(vendor.is_persistent())
