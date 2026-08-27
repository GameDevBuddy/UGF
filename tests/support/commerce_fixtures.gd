class_name CommerceFixtures
extends RefCounted
## Builders for the shops, wallets and loot tables the M11 suites need.


# --- Currency and wallets -------------------------------------------------

static func gold() -> CurrencyDefinition:
	var definition := CurrencyDefinition.new()
	definition.id = &"currency.gold"
	definition.display_name = "Gold"
	definition.symbol = "g"
	definition.decimals = 0
	return definition


static func wallet(balance: float = 100.0, currency: CurrencyDefinition = null) -> WalletComponent:
	var money := currency if currency != null else gold()
	var component := WalletComponent.new()
	component.name = "WalletComponent"
	var ids: Array[StringName] = [money.id]
	var amounts: Array[float] = [balance]
	component.starting_currencies = ids
	component.starting_amounts = amounts
	var definitions: Array[CurrencyDefinition] = [money]
	component.currencies = definitions
	return component


# --- Stock and vendors ----------------------------------------------------

static func stock(
	item_id: StringName, quantity: int = 5, price: float = 0.0
) -> StockEntry:
	var entry := StockEntry.new()
	entry.item_id = item_id
	entry.quantity = quantity
	entry.maximum = maxi(quantity, 1)
	entry.price_override = price
	return entry


static func pricing(
	markup: float = 2.0, markdown: float = 0.5
) -> StandardPricingPolicy:
	var policy := StandardPricingPolicy.new()
	policy.buy_markup = markup
	policy.sell_markdown = markdown
	policy.minimum_price = 1.0
	return policy


static func vendor_definition(
	id: StringName = &"vendor.smith",
	entries: Array = [],
	restock_interval: float = 0.0
) -> VendorDefinition:
	var definition := VendorDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	var typed: Array[StockEntry] = []
	typed.assign(entries)
	definition.stock = typed
	definition.pricing = pricing()
	definition.currency = &"currency.gold"
	definition.restock_interval = restock_interval
	return definition


## A shopkeeper with a shelf, a purse and a faction.
static func vendor(
	entity_name: String = "Smith",
	definition: VendorDefinition = null,
	balance: float = 500.0,
	faction_id: StringName = &"",
	factions: FactionService = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var component := VendorComponent.new()
	component.name = "VendorComponent"
	component.vendor_override = definition
	component.auto_tick = false
	entity.add_child(component)

	entity.add_child(wallet(balance))

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(50)
	entity.add_child(inventory)

	if faction_id != &"":
		var mark := FactionComponent.new()
		mark.name = "FactionComponent"
		mark.faction_override = faction_id
		mark.service = factions
		entity.add_child(mark)
	return entity


## A shopper with a bag, a purse and optionally a name factions remember.
static func customer(
	entity_name: String = "Player",
	balance: float = 100.0,
	actor_id: StringName = &"",
	factions: FactionService = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	entity.add_child(wallet(balance))

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	if actor_id != &"":
		var mark := FactionComponent.new()
		mark.name = "FactionComponent"
		mark.actor_id = actor_id
		mark.service = factions
		entity.add_child(mark)
	return entity


# --- Loot -----------------------------------------------------------------

static func loot_entry(
	item_id: StringName,
	minimum: int = 1,
	maximum: int = 1,
	weight: float = 1.0,
	guaranteed: bool = false
) -> LootEntry:
	var entry := LootEntry.new()
	entry.item_id = item_id
	entry.minimum = minimum
	entry.maximum = maximum
	entry.weight = weight
	entry.guaranteed = guaranteed
	return entry


static func loot_table(
	id: StringName, entries: Array, rolls: int = 1
) -> LootTableDefinition:
	var definition := LootTableDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	var typed: Array[LootEntry] = []
	typed.assign(entries)
	definition.entries = typed
	definition.rolls = rolls
	return definition


# --- Lookups --------------------------------------------------------------

static func assemble(entity: Node, core: Node = null, definition: FrameworkDefinition = null) -> void:
	var context := EntityContext.create(entity, definition, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func wallet_of(entity: Node) -> WalletComponent:
	return WalletComponent.find_on(entity)


static func vendor_of(entity: Node) -> VendorComponent:
	return VendorComponent.find_on(entity)


static func inventory_of(entity: Node) -> InventoryComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null
