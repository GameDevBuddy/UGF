class_name FactionPriceAdapter
extends RefCounted
## Turns faction standing into a price multiplier.
##
## [b]The other half of the M10 exit gate.[/b] Commerce does not exist yet, and
## this deliberately does not wait for it: what a pricing policy needs from
## Factions is one number, and the seam that produces it can be written, tested
## and shipped now. M11's pricing policy consumes
## [method get_multiplier] rather than growing its own thresholds.
##
## A [RefCounted] rather than a component, because pricing is asked about
## rather than attached to: a vendor's prices are computed when a shop opens,
## not maintained every frame.

## How far standing can move a price, as a fraction. 0.2 means an ally pays
## 20% less and someone hated pays 20% more.
var spread: float = 0.2

var service: FactionService = null


static func create(
	p_service: FactionService, p_spread: float = 0.2
) -> FactionPriceAdapter:
	var adapter := FactionPriceAdapter.new()
	adapter.service = p_service
	adapter.spread = p_spread
	return adapter


## Multiplier a vendor of [param vendor_faction] charges [param customer].
##
## One where there is no opinion either way, so a project with no factions
## installed gets list price rather than a division by zero (rule 31).
func get_multiplier(vendor_faction: StringName, customer: StringName) -> float:
	if service == null or vendor_faction == &"" or customer == &"":
		return 1.0
	return AttitudeSolver.price_scale(
		service.resolve_attitude(vendor_faction, customer), spread
	)


## Multiplier between two entities, reading both their faction components.
## What a vendor component will call with the customer that walked in.
func get_multiplier_for(vendor: Node, customer: Node) -> float:
	var vendor_mark := FactionComponent.find_on(vendor)
	if vendor_mark == null or not vendor_mark.has_faction():
		return 1.0
	return AttitudeSolver.price_scale(vendor_mark.get_attitude_to(customer), spread)


## Applies the multiplier to a price, rounded to whole units.
##
## Rounding here rather than at the call site because a shop showing 12.7 gold
## is a bug every project fixes once, and the framework may as well fix it.
func apply(price: float, vendor_faction: StringName, customer: StringName) -> float:
	return roundf(price * get_multiplier(vendor_faction, customer))
