class_name CommerceService
extends FrameworkService
## Validates and executes trades. The only thing allowed to move money.
##
## [b]Every transaction is validate-then-mutate, with no step in between that
## can fail.[/b] Implementation Plan 17 asks for it and rule 17 is the general
## case: currency, stock, capacity and restrictions are all checked first, and
## only once every one of them has passed does anything change. A purchase that
## took the money and then found the bag full is the bug this shape exists to
## make impossible.
##
## A service rather than a component because a trade touches two wallets and
## two containers, and the thing that owns an atomic operation should not be
## one of its participants (rule 4).

signal purchased(context: TradeContext)
signal sold(context: TradeContext)
signal trade_refused(context: TradeContext, reason: StringName)

const CommerceEvent := preload(
	"res://addons/universal_gameplay/commerce/commerce_event.gd"
)

var _core: Node = null
var _bus: Node = null
var _factions: FactionService = null


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_COMMERCE


## Wires the service to the rest of the framework. Everything it needs arrives
## here rather than being looked up (rule 20).
func configure(
	core: Node = null, bus: Node = null, factions: FactionService = null
) -> void:
	_core = core
	_factions = factions
	set_bus(bus)


func set_bus(bus: Node) -> void:
	_bus = bus
	if _bus == null or not _bus.has_method("register_event"):
		return
	_bus.call("register_event", GameplayNames.EVENT_ITEM_PURCHASED)
	_bus.call("register_event", GameplayNames.EVENT_ITEM_SOLD)


func set_factions(factions: FactionService) -> void:
	_factions = factions


func get_bus() -> Node:
	return _bus


# --- Quoting --------------------------------------------------------------

## Works out what a trade would cost, without doing it.
##
## Public and side-effect free, because a shop UI asks this for every line it
## draws and a quote that moved stock would be a disaster.
func quote(
	customer: Node, vendor: Node, item_id: StringName, quantity: int = 1,
	direction: TradeContext.Direction = TradeContext.Direction.BUY
) -> FrameworkResult:
	var context := TradeContext.create(direction, customer, vendor, item_id, quantity)
	context.vendor_component = VendorComponent.find_on(vendor)
	if context.vendor_component == null:
		return FrameworkResult.fail(&"commerce.not_a_vendor", "That is not a shop.")
	context.currency = context.vendor_component.get_currency()

	var definition := _resolve_item(item_id)
	if definition == null:
		return FrameworkResult.fail(
			&"commerce.unknown_item", "No item is registered as '%s'." % item_id
		)

	var pricing := context.vendor_component.get_pricing()
	if pricing is StandardPricingPolicy:
		# Injected rather than looked up, so a policy resource stays a plain
		# value object and a project can price without factions installed.
		(pricing as StandardPricingPolicy).faction_service = _factions
	if pricing != null and not pricing.accepts(context, definition):
		return FrameworkResult.fail(
			&"commerce.not_accepted", "This vendor does not deal in that."
		)

	var base := _base_value(context, definition)
	if pricing == null:
		context.unit_price = base
	elif context.is_buy():
		context.unit_price = pricing.get_buy_price(context, base)
	else:
		context.unit_price = pricing.get_sell_price(context, base)
	return FrameworkResult.ok(context)


# --- Trading --------------------------------------------------------------

## The customer buys from the vendor.
func buy(
	customer: Node, vendor: Node, item_id: StringName, quantity: int = 1
) -> FrameworkResult:
	var quoted := quote(customer, vendor, item_id, quantity, TradeContext.Direction.BUY)
	if quoted.is_err():
		return quoted
	return execute(quoted.payload as TradeContext)


## The customer sells to the vendor.
func sell(
	customer: Node, vendor: Node, item_id: StringName, quantity: int = 1
) -> FrameworkResult:
	var quoted := quote(customer, vendor, item_id, quantity, TradeContext.Direction.SELL)
	if quoted.is_err():
		return quoted
	return execute(quoted.payload as TradeContext)


## Runs a quoted trade.
##
## Split from [method buy] so a project that adjusted a quote -- a haggle, a
## coupon, a bulk discount -- executes the price it showed the player rather
## than a freshly computed one that might differ.
func execute(context: TradeContext) -> FrameworkResult:
	var allowed := validate(context)
	if allowed.is_err():
		trade_refused.emit(context, allowed.code)
		return allowed

	# Everything below this line is mutation, and nothing below it can fail:
	# the checks above have already established that all four participants can
	# do their part.
	var definition := _resolve_item(context.item_id)
	var payer := context.get_payer_wallet()
	var payee := context.get_payee_wallet()

	if context.total > 0.0 and payer != null:
		payer.withdraw(context.currency, context.total)
		if payee != null:
			payee.deposit(context.currency, context.total)

	var instance: ItemInstance = null
	if context.is_buy():
		context.vendor_component.take_stock(context.item_id, context.quantity)
		instance = ItemInstance.create(definition, context.quantity)
		context.get_destination_inventory().add(instance)
	else:
		context.get_source_inventory().remove(context.item_id, context.quantity)
		instance = ItemInstance.create(definition, context.quantity)
		# Both: the shelf so it can be bought back, and the vendor's own
		# container so the goods exist somewhere. Listing without storing is
		# how a sold item ends up in neither place.
		context.vendor_component.give_stock(context.item_id, context.quantity)
		var vendor_bag := context.get_destination_inventory()
		if vendor_bag != null:
			vendor_bag.add(instance)

	context.moved = [instance]
	_announce(context)
	return FrameworkResult.ok(context)


## Everything that must hold before anything moves.
##
## Public because a shop UI greys out a line rather than letting the player
## click it and be told no.
func validate(context: TradeContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(&"commerce.no_context", "There is no trade.")
	if context.vendor_component == null:
		return FrameworkResult.fail(&"commerce.not_a_vendor", "That is not a shop.")
	if context.quantity <= 0:
		return FrameworkResult.fail(
			&"commerce.invalid_quantity", "A trade must move at least one."
		)

	var definition := _resolve_item(context.item_id)
	if definition == null:
		return FrameworkResult.fail(
			&"commerce.unknown_item", "No item is registered as '%s'." % context.item_id
		)

	var source := context.get_source_inventory()
	if context.is_buy():
		if not context.vendor_component.has_stock(context.item_id, context.quantity):
			return FrameworkResult.fail(
				&"commerce.out_of_stock", "The vendor does not have that many."
			)
	elif source == null or not source.has(context.item_id, context.quantity):
		return FrameworkResult.fail(
			&"commerce.nothing_to_sell", "You do not have that many."
		)

	var destination := context.get_destination_inventory()
	if context.is_buy():
		if destination == null:
			return FrameworkResult.fail(
				&"commerce.no_room", "There is nowhere to put it."
			)
		var fits := destination.can_fit(ItemInstance.create(definition, context.quantity))
		if fits.is_err():
			return fits

	var payer := context.get_payer_wallet()
	if context.total > 0.0:
		# The vendor's own limit is checked first on a sale, because it is the
		# more specific answer: on a sale the vendor is the payer, so a generic
		# "not enough funds" would fire first and say less.
		if not context.is_buy() and not _vendor_can_pay(context):
			return FrameworkResult.fail(
				&"commerce.vendor_broke", "The vendor cannot afford that."
			)
		if payer == null:
			return FrameworkResult.fail(
				&"commerce.no_wallet", "There is nothing to pay with."
			)
		if not payer.can_afford(context.currency, context.total):
			return FrameworkResult.fail(
				&"commerce.insufficient_funds", "That costs more than you have."
			)
	return FrameworkResult.ok(context)


# --- Internals ------------------------------------------------------------

func _vendor_can_pay(context: TradeContext) -> bool:
	if context.vendor_component.has_unlimited_funds():
		return true
	return context.vendor_component.get_available_funds() >= context.total


## An item's worth before any policy. The stock line's override wins, so a
## shop can charge what it likes for one line without a pricing policy of its
## own.
func _base_value(context: TradeContext, definition: ItemDefinition) -> float:
	var entry := context.vendor_component.find_stock(context.item_id)
	if entry != null and entry.price_override > 0.0:
		return entry.price_override
	return definition.base_value


func _resolve_item(item_id: StringName) -> ItemDefinition:
	if _core == null or not _core.has_method("get_definition"):
		return null
	return _core.call("get_definition", item_id) as ItemDefinition


func _announce(context: TradeContext) -> void:
	if context.is_buy():
		purchased.emit(context)
	else:
		sold.emit(context)
	if _bus == null or not _bus.has_method("publish"):
		return
	_bus.call("publish", CommerceEvent.create(context))
