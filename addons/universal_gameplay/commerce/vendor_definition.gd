class_name VendorDefinition
extends FrameworkDefinition
## What a shop is: what it stocks, what it charges, and how often it refills.

## The shelf. Copied per vendor at runtime, so one shop selling out does not
## empty every shop pointed at this resource.
@export var stock: Array[StockEntry] = []

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
func build_stock() -> Array[StockEntry]:
	var copies: Array[StockEntry] = []
	for entry in stock:
		if entry != null:
			copies.append(entry.duplicate_entry())
	return copies


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
