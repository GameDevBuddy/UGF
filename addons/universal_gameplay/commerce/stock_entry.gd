class_name StockEntry
extends Resource
## One line on a vendor's shelf.
##
## Named by item id rather than holding an [ItemDefinition], so a shop and its
## whole catalogue do not have to load each other and a vendor's save record
## is a list of names (rule 32).

## What is being sold.
@export var item_id: StringName = &""

## How many are on the shelf now. Negative means unlimited: the blacksmith who
## never runs out of nails.
@export_range(-1, 9999) var quantity: int = 1

## Ceiling a restock refills towards. Zero uses [member quantity] as authored,
## so a shelf restocks to what the designer typed.
@export_range(0, 9999) var maximum: int = 0

## Units added per restock. Zero refills to the maximum in one go.
@export_range(0, 9999) var restock_amount: int = 0

## Price for one unit, overriding the item's base value. Zero uses the item's.
@export_range(0.0, 999999.0, 0.01) var price_override: float = 0.0


func is_unlimited() -> bool:
	return quantity < 0


func get_maximum() -> int:
	return maximum if maximum > 0 else quantity


func is_in_stock(wanted: int = 1) -> bool:
	return is_unlimited() or quantity >= wanted


## Takes units off the shelf. Unlimited stock is not decremented.
func take(amount: int) -> int:
	if amount <= 0:
		return 0
	if is_unlimited():
		return amount
	var taken := mini(amount, quantity)
	quantity -= taken
	return taken


## Puts units on the shelf.
##
## [param beyond_maximum] is what a sale to the vendor passes: the ceiling is
## what a restock refills [i]towards[/i], not a cap on what a shop can hold.
## Without that distinction, selling to a shop whose shelf was already full
## destroyed the item -- it left the player's bag and arrived nowhere.
func give(amount: int, beyond_maximum: bool = false) -> int:
	if amount <= 0 or is_unlimited():
		return 0
	if beyond_maximum:
		quantity += amount
		return amount
	var room := maxi(0, get_maximum() - quantity)
	var added := mini(amount, room)
	quantity += added
	return added


## Refills towards the ceiling. Returns how many were added.
func restock() -> int:
	if is_unlimited():
		return 0
	var target := get_maximum()
	if quantity >= target:
		return 0
	var step := restock_amount if restock_amount > 0 else target - quantity
	return give(step)


## A copy, so a vendor's live stock is never the shared definition's.
##
## Without this, one shop selling out would empty every shop pointed at the
## same resource -- and a definition mutated at runtime is exactly what rule 2
## forbids.
func duplicate_entry() -> StockEntry:
	var copy := StockEntry.new()
	copy.item_id = item_id
	copy.quantity = quantity
	copy.maximum = maximum
	copy.restock_amount = restock_amount
	copy.price_override = price_override
	return copy


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if item_id == &"":
		result.add_error(
			&"stock.no_item",
			"A stock entry with no item id sells nothing.",
			resource_path,
			"item_id"
		)
	if maximum > 0 and quantity > maximum:
		result.add_warning(
			&"stock.over_maximum",
			(
				"'%s' starts above its ceiling, so its first restock will not "
				+ "top it up."
			) % item_id,
			resource_path,
			"quantity"
		)
	if is_unlimited() and restock_amount > 0:
		result.add_warning(
			&"stock.restocking_unlimited",
			"'%s' is unlimited, so its restock amount is never used." % item_id,
			resource_path,
			"restock_amount"
		)
	return result
