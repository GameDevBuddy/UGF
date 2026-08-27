extends FrameworkModule
## The Equipment module.
##
## Slots, loadouts, and the stat modifiers an item grants while worn.
##
## Requires Items for something to wear. Stats and Inventory are optional:
## without Stats an item equips and grants nothing, which is right for a
## mannequin; without Inventory the caller hands over an instance and gets it
## back, which is right for a fixed loadout that never goes in a bag (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.equipment"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Equipment"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Equipment slots and loadouts, with granted modifiers sourced per "
			+ "instance so two of the same item unequip independently."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_ITEMS,
		]
		_manifest.optional = [
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_INVENTORY,
		]
	return _manifest
