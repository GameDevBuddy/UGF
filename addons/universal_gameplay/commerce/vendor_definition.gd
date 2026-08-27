class_name VendorDefinition
extends FrameworkDefinition
## What a shop is: what it stocks, what it charges, and how often it refills.

## How the shelf is decided.
##
## The plan lists five stock policies: fixed, generated, rotating, finite and
## unlimited. Finite and unlimited are per-line and already live on
## [StockEntry] as its quantity -- minus one is unlimited, anything else is
## finite. The three here are per-shop, because they are decisions about the
## shelf rather than about one line on it.
enum StockMode {
	## Every authored line is on the shelf. What a shop is unless it says
	## otherwise.
	FIXED,
	## Only [member rotating_slots] of the authored lines are stocked at a
	## time, reshuffled on each restock. The travelling merchant whose wares
	## are different every week, authored as one list rather than seven.
	ROTATING,
	## The shelf is rolled from a loot table on each restock. The fence whose
	## stock is whatever came in, without anybody authoring what that is.
	GENERATED,
}

@export var stock_mode: StockMode = StockMode.FIXED

## The shelf. Copied per vendor at runtime, so one shop selling out does not
## empty every shop pointed at this resource.
##
## Under [constant StockMode.ROTATING] this is the pool to draw from rather
## than the shelf itself. Under [constant StockMode.GENERATED] it is the
## fallback for when the table cannot be resolved -- a shop with an empty
## shelf and no error is worse than a shop with its authored one.
@export var stock: Array[StockEntry] = []

@export_group("Rotating stock")
## How many authored lines are live at once. Zero or more than the pool means
## all of them, which makes rotation a no-op rather than an error.
@export_range(0, 999) var rotating_slots: int = 0

@export_group("Generated stock")
## Loot table rolled to build the shelf. Named by id rather than held, so
## Commerce and Loot do not have to load each other (rule 32).
@export var generated_table_id: StringName = &""

## Ceiling put on each generated line, so a lucky roll does not produce a shop
## with four hundred of something.
@export_range(1, 9999) var generated_maximum: int = 5

## What it charges. Null prices everything at base value, which is a valid
## shop and a very generous one.
@export var pricing: PricingPolicy

## Money it deals in.
@export var currency: StringName = &"currency.gold"

@export_group("Restocking")
## Seconds between restocks. Zero never restocks, which is right for a
## one-off cache and wrong for a town shop.
@export_range(0.0, 86400.0, 1.0, "or_greater") var restock_interval: float = 0.0

## Restock the moment the shop is opened if the interval has elapsed, rather
## than only while it is loaded. What stops a shop the player has not visited
## for an hour being empty.
@export var restocks_on_open: bool = true

@export_group("Funds")
## What the vendor can spend buying from the customer. Zero means unlimited,
## which is the usual case and stops "the shopkeeper is broke" being a bug
## report.
@export_range(0.0, 999999.0, 1.0, "or_greater") var purse: float = 0.0


func get_pricing() -> PricingPolicy:
	return pricing


## A live copy of the shelf. Every vendor gets its own.
##
## [param rng] and [param roll_table] are supplied by the component and are
## optional: with neither, a rotating shop stocks its whole pool and a
## generated one falls back to its authored lines. That is what keeps a
## definition rollable in a test with no registry and no RNG (rule 33).
func build_stock(
	rng: RandomNumberGenerator = null, roll_table: Callable = Callable()
) -> Array[StockEntry]:
	match stock_mode:
		StockMode.ROTATING:
			return _rotate(rng)
		StockMode.GENERATED:
			var generated := _generate(roll_table)
			if not generated.is_empty():
				return generated
			# Fall through to the authored shelf. A shop with nothing on it and
			# no error is a bug report reading "the merchant sells nothing".
	var copies: Array[StockEntry] = []
	for entry in stock:
		if entry != null:
			copies.append(entry.duplicate_entry())
	return copies


## Picks [member rotating_slots] lines from the pool, without repeats.
func _rotate(rng: RandomNumberGenerator) -> Array[StockEntry]:
	var pool: Array[StockEntry] = []
	for entry in stock:
		if entry != null:
			pool.append(entry)
	if rotating_slots <= 0 or rotating_slots >= pool.size() or rng == null:
		var all: Array[StockEntry] = []
		for entry in pool:
			all.append(entry.duplicate_entry())
		return all

	var chosen: Array[StockEntry] = []
	for _slot in rotating_slots:
		if pool.is_empty():
			break
		var index := rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index].duplicate_entry())
		pool.remove_at(index)
	return chosen


## Turns a loot roll into shelf lines.
##
## [param roll_table] takes the table id and returns the same
## item-id-and-quantity dictionaries [method LootTableDefinition.roll] does, so
## Commerce never learns what a loot table is -- only what one produces.
func _generate(roll_table: Callable) -> Array[StockEntry]:
	var built: Array[StockEntry] = []
	if generated_table_id == &"" or not roll_table.is_valid():
		return built

	var drops: Variant = roll_table.call(generated_table_id)
	if not (drops is Array):
		return built

	for drop in drops:
		var item_id: StringName = drop.get("item_id", &"")
		if item_id == &"":
			continue
		var quantity: int = mini(int(drop.get("quantity", 1)), generated_maximum)
		if quantity <= 0:
			continue
		var entry := StockEntry.new()
		entry.item_id = item_id
		entry.quantity = quantity
		entry.maximum = generated_maximum
		built.append(entry)
	return built


func validate() -> ValidationResult:
	var result := super()
	if stock.is_empty():
		result.add_warning(
			&"vendor.no_stock",
			(
				"%s stocks nothing, so it can only buy. Correct for a fence; "
				+ "probably not for a shop."
			) % get_debug_name(),
			resource_path,
			"stock"
		)
	if currency == &"":
		result.add_error(
			&"vendor.no_currency",
			"%s deals in no currency, so nothing can be paid for." % get_debug_name(),
			resource_path,
			"currency"
		)
	var seen: Dictionary[StringName, bool] = {}
	for entry in stock:
		if entry == null:
			result.add_warning(
				&"vendor.empty_stock_slot",
				"%s has an empty stock slot." % get_debug_name(),
				resource_path,
				"stock"
			)
			continue
		if entry.item_id != &"" and seen.has(entry.item_id):
			result.add_warning(
				&"vendor.duplicate_stock",
				(
					"%s stocks '%s' on two lines; they restock independently "
					+ "and will look like one shelf to a player."
				) % [get_debug_name(), entry.item_id],
				resource_path,
				"stock"
			)
		seen[entry.item_id] = true
		result.merge(entry.validate())
	if pricing != null:
		result.merge(pricing.validate())
	if restock_interval <= 0.0:
		var refills := false
		for entry in stock:
			if entry != null and not entry.is_unlimited():
				refills = true
				break
		if refills:
			result.add_info(
				&"vendor.never_restocks",
				"%s has limited stock and never restocks." % get_debug_name(),
				resource_path,
				"restock_interval"
			)
	return result

## Stock items and the currency this vendor trades in.
func get_referenced_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in stock:
		if entry != null and entry.item_id != &"":
			ids.append(entry.item_id)
	if currency != &"":
		ids.append(currency)
	return ids
