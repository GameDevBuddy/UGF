class_name TradeContext
extends RefCounted
## One purchase or sale, start to finish.
##
## Built by [CommerceService], filled in as the quote is worked out, and read
## back by whatever announces the result. The same shape [DamageContext] has:
## every stage reads and rewrites one object, and what survives to the end is
## what actually happened.

enum Direction {
	## The customer is paying the vendor.
	BUY,
	## The vendor is paying the customer.
	SELL,
}

var direction: Direction = Direction.BUY

## The entity doing the buying or selling. Usually the player.
var customer: Node = null

## The vendor's entity.
var vendor: Node = null

## The vendor's component, for the stock it is drawing from.
var vendor_component: VendorComponent = null

var item_id: StringName = &""
var quantity: int = 1

var currency: StringName = &""

## Price for one unit, after every policy has had its say.
var unit_price: float = 0.0

## What the whole transaction costs. Recomputed rather than stored, so a
## quantity changed after a quote cannot leave a stale total behind.
var total: float:
	get:
		return unit_price * float(quantity)

## The instances that actually changed hands, filled in on success.
var moved: Array[ItemInstance] = []

## Free-form per-transaction bag, for a project's own pricing inputs.
var extras: Dictionary = {}


static func create(
	p_direction: Direction,
	p_customer: Node,
	p_vendor: Node,
	p_item_id: StringName,
	p_quantity: int = 1
) -> TradeContext:
	var context := TradeContext.new()
	context.direction = p_direction
	context.customer = p_customer
	context.vendor = p_vendor
	context.item_id = p_item_id
	context.quantity = maxi(1, p_quantity)
	return context


func is_buy() -> bool:
	return direction == Direction.BUY


## The wallet that pays.
func get_payer_wallet() -> WalletComponent:
	return WalletComponent.find_on(customer if is_buy() else vendor)


## The wallet that is paid.
func get_payee_wallet() -> WalletComponent:
	return WalletComponent.find_on(vendor if is_buy() else customer)


## The container the goods leave.
func get_source_inventory() -> InventoryComponent:
	return _inventory_of(vendor if is_buy() else customer)


## The container the goods arrive in.
func get_destination_inventory() -> InventoryComponent:
	return _inventory_of(customer if is_buy() else vendor)


func _inventory_of(node: Node) -> InventoryComponent:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _to_string() -> String:
	var verb := "buys" if is_buy() else "sells"
	var who := customer.name if customer != null else "<somebody>"
	return "TradeContext(%s %s %d x %s for %.2f)" % [
		who, verb, quantity, item_id, total
	]
