extends FrameworkModule
## The Inventory module.
##
## One container capability, configured by profile into a backpack, a chest, a
## vehicle boot or a vendor's stock. Registers no services: a container belongs
## to the entity that holds it (rule 4), and a global inventory manager would
## own every bag in the game while answering to none of them.
##
## Requires Items, because a container with nothing to put in it is not a
## container. That dependency is declared rather than discovered (rule 36).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.inventory"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Inventory"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Containers with slot, weight and category limits, and transfers "
			+ "that are atomic across both sides."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_ITEMS,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_ITEMS,
		]
	return _manifest
