class_name StandardPricingPolicy
extends PricingPolicy
## The pricing every shop starts from: a markup, a markdown, and how much the
## vendor likes you.
##
## [b]This is where M10's price adapter is spent.[/b] Factions produced a
## multiplier a milestone early precisely so this policy could consume it
## rather than growing a second set of thresholds. Delete Factions and the
## multiplier is one and prices are flat, which is the correct failure mode
## (rule 10, rule 31).

## Multiplier on an item's base value when the customer is buying. Above one:
## shops sell dear.
@export_range(0.0, 10.0, 0.01, "or_greater") var buy_markup: float = 1.0

## Multiplier when the vendor is buying from the customer. Below one: shops
## buy cheap. The gap between the two is the shop's margin, and a project that
## sets both to one has a shop that launders items for free.
@export_range(0.0, 10.0, 0.01) var sell_markdown: float = 0.5

@export_group("Reputation")
## Whether standing moves prices at all.
@export var uses_reputation: bool = true

## How far standing can move a price, as a fraction. Passed straight to
## [FactionPriceAdapter].
@export_range(0.0, 1.0, 0.01) var reputation_spread: float = 0.2

@export_group("Restrictions")
## Item categories this vendor will buy. Empty buys anything.
@export var buys_categories: Array[StringName] = []

## Item tags this vendor refuses outright, whichever way the trade runs.
@export var refuses_tags: Array[StringName] = []

@export_group("Floors")
## Least a unit can cost, after every multiplier. Stops a beloved customer
## walking off with free swords.
@export_range(0.0, 9999.0, 0.01) var minimum_price: float = 1.0

## Standing service. Injected by [CommerceService] when one is registered;
## null prices everything flat.
var faction_service: FactionService = null


func get_buy_price(context: TradeContext, base_value: float) -> float:
	return maxf(minimum_price, base_value * buy_markup * _reputation_scale(context))


func get_sell_price(context: TradeContext, base_value: float) -> float:
	# The reputation scale is inverted when the vendor is buying: a shop that
	# likes you charges less and pays more, and applying the same multiplier
	# both ways would have it paying less the more it likes you.
	var scale := _reputation_scale(context)
	var favour := 2.0 - scale if scale > 0.0 else 1.0
	return maxf(0.0, base_value * sell_markdown * favour)


func accepts(context: TradeContext, definition: ItemDefinition) -> bool:
	if definition == null:
		return false
	for tag in refuses_tags:
		if definition.has_tag(tag):
			return false
	if context != null and context.is_buy():
		return true
	if buys_categories.is_empty():
		return true
	return buys_categories.has(definition.category)


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if sell_markdown >= buy_markup:
		result.add_warning(
			&"pricing.no_margin",
			(
				"This vendor pays at least what it charges, so anything bought "
				+ "can be sold straight back at a profit."
			),
			resource_path,
			"sell_markdown"
		)
	if buy_markup <= 0.0:
		result.add_error(
			&"pricing.free_goods",
			"A buy markup of zero gives everything away.",
			resource_path,
			"buy_markup"
		)
	return result


## The faction multiplier for this trade, or one when there is nothing to ask.
func _reputation_scale(context: TradeContext) -> float:
	if not uses_reputation or faction_service == null or context == null:
		return 1.0
	var adapter := FactionPriceAdapter.create(faction_service, reputation_spread)
	return adapter.get_multiplier_for(context.vendor, context.customer)
