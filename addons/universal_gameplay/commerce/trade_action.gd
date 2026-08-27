class_name TradeAction
extends InteractionAction
## Opens a shop. The bridge between "press E on the shopkeeper" and commerce.
##
## An [InteractionAction], so a vendor is reached through exactly the pipeline
## a door and a conversation use. It lives in Commerce rather than in
## Interaction because that is the direction that keeps both removable: a
## project with no Commerce module never loads this file, and Interaction never
## learns that shops exist (rule 10).
##
## Opening a shop draws nothing. [signal VendorComponent.shop_opened] is what
## a project's UI listens to (rule 21).


func can_execute(context: InteractionContext) -> FrameworkResult:
	var vendor := _find_vendor(context)
	if vendor == null:
		return FrameworkResult.fail(
			&"trade.no_vendor", "There is nothing to trade with here."
		)
	if vendor.get_vendor() == null:
		return FrameworkResult.fail(&"trade.not_a_shop", "They are not selling.")
	if vendor.is_open():
		return FrameworkResult.fail(
			&"trade.busy", "They are already serving somebody."
		)
	return FrameworkResult.ok(null)


func execute(context: InteractionContext) -> FrameworkResult:
	var vendor := _find_vendor(context)
	if vendor == null:
		return FrameworkResult.fail(
			&"trade.no_vendor", "There is nothing to trade with here."
		)
	return vendor.open(context.interactor)


func _find_vendor(context: InteractionContext) -> VendorComponent:
	if context == null or context.target == null:
		return null
	return VendorComponent.find_on(context.target)
