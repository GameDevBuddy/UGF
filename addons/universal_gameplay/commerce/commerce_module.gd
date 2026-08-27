extends FrameworkModule
## The Commerce module.
##
## Wallets, currencies, vendors, and one service that owns the transaction.
## Every trade is validate-then-mutate: currency, stock, capacity and
## restrictions are checked before anything moves, so a purchase that took the
## money and found the bag full cannot happen (rule 17).
##
## Requires Items and Inventory: there is nothing to trade without them.
## Factions is optional and is where reputation pricing comes from; without it
## the multiplier is one and prices are flat (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.commerce"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Commerce"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Atomic purchases and sales, vendor stock with restocking, and "
			+ "pricing that reads faction standing through the adapter M10 "
			+ "shipped for it."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
		]
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_FACTIONS,
			GameplayNames.MODULE_INTERACTION,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_FACTIONS,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_ITEMS,
		]
	return _manifest
