class_name VendorComponent
extends FrameworkComponent
## Turns an NPC, a terminal or a market stall into a shop.
##
## Holds the live shelf -- its own copy, never the shared definition's -- and
## the restock clock. It executes no transactions: [CommerceService] does that,
## because a purchase touches two wallets and two containers and the thing that
## owns an atomic operation should not be one of its participants (rule 4).

## Emitted when somebody starts trading here, so presentation can open a shop
## without Commerce knowing what a UI is (rule 21).
signal shop_opened(customer: Node)
signal shop_closed(customer: Node)
## Emitted when the shelf changes, for a UI that is already open.
signal stock_changed
signal restocked(added: int)

## What this vendor sells. Takes precedence over the definition's.
@export var vendor_override: VendorDefinition

## Tick the restock clock from [method Node._physics_process]. Off when
## something else owns time, and irrelevant for a vendor that never restocks.
@export var auto_tick: bool = true

var _definition: VendorDefinition = null
var _stock: Array[StockEntry] = []
var _since_restock: float = 0.0
## Injected so a rotating or generated shop is reproducible in a test and
## identical on two network clients, the same reason LootComponent takes one.
var _rng: RandomNumberGenerator = null
var _customer: Node = null


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _restocks())


func initialize(context: EntityContext) -> void:
	super(context)
	_definition = _resolve_definition()
	if _stock.is_empty() and _definition != null:
		_stock = _definition.build_stock(get_rng(), _roll_table)
	set_physics_process(auto_tick and _restocks())


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

func get_vendor() -> VendorDefinition:
	return _definition


func is_open() -> bool:
	return _customer != null


func get_customer() -> Node:
	return _customer


func get_currency() -> StringName:
	return _definition.currency if _definition != null else &""


func get_pricing() -> PricingPolicy:
	return _definition.get_pricing() if _definition != null else null


## The live shelf. Mutating an entry mutates the shop, which is the point.
func get_stock() -> Array[StockEntry]:
	return _stock


func find_stock(item_id: StringName) -> StockEntry:
	for entry in _stock:
		if entry != null and entry.item_id == item_id:
			return entry
	return null


func has_stock(item_id: StringName, quantity: int = 1) -> bool:
	var entry := find_stock(item_id)
	return entry != null and entry.is_in_stock(quantity)


## What the vendor can spend. Its purse when one is authored, otherwise its
## wallet, otherwise unlimited.
func get_available_funds() -> float:
	if _definition != null and _definition.purse > 0.0:
		return _definition.purse
	var wallet := WalletComponent.find_on(get_entity())
	if wallet != null:
		return wallet.get_balance(get_currency())
	return -1.0


func has_unlimited_funds() -> bool:
	return get_available_funds() < 0.0


# --- Opening and closing --------------------------------------------------

## Starts a trading session. Presentation listens; nothing here draws anything.
func open(customer: Node) -> FrameworkResult:
	if customer == null:
		return FrameworkResult.fail(&"vendor.no_customer", "Nobody is shopping.")
	if is_open():
		return FrameworkResult.fail(
			&"vendor.busy", "This vendor is already serving somebody."
		)
	if _definition == null:
		return FrameworkResult.fail(
			&"vendor.not_a_shop", "This entity sells nothing."
		)
	if _definition.restocks_on_open:
		# A shop the player has not visited for an hour should not be empty
		# because nothing was ticking it while it was unloaded.
		restock_if_due()
	_customer = customer
	shop_opened.emit(customer)
	return FrameworkResult.ok(self)


func close() -> void:
	if not is_open():
		return
	var leaving := _customer
	_customer = null
	shop_closed.emit(leaving)


# --- Stock ----------------------------------------------------------------

## Takes units off the shelf. Called by [CommerceService] once a purchase has
## been validated, never before.
func take_stock(item_id: StringName, quantity: int) -> int:
	var entry := find_stock(item_id)
	if entry == null:
		return 0
	var taken := entry.take(quantity)
	if taken > 0:
		stock_changed.emit()
	return taken


## Puts units on the shelf. What a sale to the vendor does; a shop that buys
## something it never stocked grows a line for it, which is what makes a fence
## work without authoring every item in the game.
func give_stock(item_id: StringName, quantity: int) -> int:
	if item_id == &"" or quantity <= 0:
		return 0
	var entry := find_stock(item_id)
	if entry == null:
		entry = StockEntry.new()
		entry.item_id = item_id
		entry.quantity = 0
		entry.maximum = 9999
		_stock.append(entry)
	# Beyond the ceiling on purpose: a shop that refused the fourth sword
	# because its shelf holds three would take the player's sword and give
	# nothing back.
	var given := entry.give(quantity, true)
	if given > 0:
		stock_changed.emit()
	return given


## Refills every shelf line towards its ceiling.
##
## A rotating or generated shop rebuilds its shelf instead, because for those
## two "restock" means a new selection rather than more of the same. Topping up
## a rotating shop's current lines would make the rotation never happen.
func restock() -> int:
	if _definition != null and _definition.stock_mode != VendorDefinition.StockMode.FIXED:
		return _rebuild_shelf()

	var added := 0
	for entry in _stock:
		if entry != null:
			added += entry.restock()
	_since_restock = 0.0
	if added > 0:
		stock_changed.emit()
		restocked.emit(added)
	return added


## Replaces the shelf with a fresh selection, for a rotating or generated shop.
##
## Anything the customer sold to this vendor is kept. A fence that forgot what
## you sold it every time it rotated would eat the player's goods, and "the
## shop lost my sword" is a bug report nobody enjoys.
func _rebuild_shelf() -> int:
	var authored: Dictionary[StringName, bool] = {}
	if _definition != null:
		for entry in _definition.stock:
			if entry != null:
				authored[entry.item_id] = true

	var kept: Array[StockEntry] = []
	for entry in _stock:
		if entry != null and not authored.has(entry.item_id) and entry.quantity > 0:
			kept.append(entry)

	_stock = _definition.build_stock(get_rng(), _roll_table)
	_stock.append_array(kept)
	_since_restock = 0.0

	var total := 0
	for entry in _stock:
		if entry != null:
			total += maxi(0, entry.quantity)
	stock_changed.emit()
	restocked.emit(total)
	return total


## Restocks only if the interval has elapsed.
func restock_if_due() -> int:
	if not _restocks() or _since_restock < _definition.restock_interval:
		return 0
	return restock()


func get_time_until_restock() -> float:
	if not _restocks():
		return 0.0
	return maxf(0.0, _definition.restock_interval - _since_restock)


func tick(delta: float) -> void:
	if delta <= 0.0 or not _restocks():
		return
	_since_restock += delta
	restock_if_due()


## The generator behind a rotating or generated shelf.
##
## Created on first use rather than in [method initialize], so a fixed shop --
## the common case -- never allocates one.
func get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Rolls a loot table by id, for a generated shelf.
##
## Returns an empty array when Loot is not installed or the table is not
## registered, which makes the definition fall back to its authored shelf.
## Commerce never learns what a loot table is -- only what one produces
## (rule 9).
func _roll_table(table_id: StringName) -> Array:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return []
	var table: Object = core.call("get_definition", table_id)
	if table == null or not table.has_method("roll"):
		return []
	return table.call("roll", get_rng())


# --- Discovery ------------------------------------------------------------

static func find_on(node: Node) -> VendorComponent:
	if node == null:
		return null
	if node is VendorComponent:
		return node as VendorComponent
	for component in DefinitionBinder.collect_components(node):
		if component is VendorComponent:
			return component as VendorComponent
	return null


# --- Persistence ----------------------------------------------------------
#
# The shelf and the clock survive. A trading session does not: reloading into
# an open shop with a customer who may no longer exist is worse than closing
# it.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var lines: Array = []
	for entry in _stock:
		if entry != null:
			lines.append({"item": String(entry.item_id), "quantity": entry.quantity})
	return {"stock": lines, "since_restock": _since_restock}


func restore_state(data: Dictionary) -> void:
	_since_restock = float(data.get("since_restock", 0.0))
	if _stock.is_empty() and _definition != null:
		_stock = _definition.build_stock(get_rng(), _roll_table)
	# Matched by item id rather than by index, so a shelf reordered or extended
	# between versions restores what it can instead of putting the wrong count
	# on the wrong line.
	for line in data.get("stock", []):
		var entry := find_stock(StringName(line.get("item", "")))
		if entry != null:
			entry.quantity = int(line.get("quantity", entry.quantity))
		else:
			give_stock(StringName(line.get("item", "")), int(line.get("quantity", 0)))
	stock_changed.emit()


# --- Internals ------------------------------------------------------------

func _restocks() -> bool:
	return _definition != null and _definition.restock_interval > 0.0


## Read by property name rather than by casting, so a terminal or a machine
## with its own definition type can be a shop (rule 9).
func _resolve_definition() -> VendorDefinition:
	if vendor_override != null:
		return vendor_override
	var definition := get_definition()
	if definition != null and "vendor" in definition:
		var candidate: Variant = definition.get("vendor")
		if candidate is VendorDefinition:
			return candidate as VendorDefinition
	return null
