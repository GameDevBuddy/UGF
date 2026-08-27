class_name PricingPolicy
extends Resource
## What something costs.
##
## A resource rather than a method on the vendor, so one pricing model is
## authored once and shared by every shop that uses it -- and so a project
## that prices by scarcity, by time of day or by a haggling minigame extends
## this instead of the framework growing a case for each (rule 24).
##
## [b]Buying and selling are asked separately.[/b] Every shop in every game
## buys for less than it sells, and a single [code]get_price[/code] with a
## direction flag would have every implementation branching on it anyway.

## What [param context] costs the customer to buy. Returns a per-unit price.
func get_buy_price(context: TradeContext, base_value: float) -> float:
	return base_value


## What the vendor will pay the customer for one unit.
func get_sell_price(context: TradeContext, base_value: float) -> float:
	return base_value


## Whether this vendor will trade in [param definition] at all.
##
## Here rather than on the vendor because "what a shop deals in" is usually
## the same decision as how it prices: an armourer that pays nothing for
## vegetables is better modelled as one that does not buy them.
func accepts(_context: TradeContext, _definition: ItemDefinition) -> bool:
	return true


func validate() -> ValidationResult:
	return ValidationResult.new()
