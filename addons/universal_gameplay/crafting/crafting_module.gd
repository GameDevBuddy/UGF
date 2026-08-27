extends FrameworkModule
## The Crafting module.
##
## Recipes as content, stations as tags, and a queue that consumes up front so
## the same planks cannot be spent twice. Tools are ingredients that are not
## consumed, which is what makes tool wear a property of the ingredient rather
## than a special case beside it.
##
## Requires Items and Inventory: there is nothing to craft from without them.
## Narrative is optional and only gates which recipes are known.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.crafting"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Crafting"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Recipes, stations and timed crafts, validated before anything is "
			+ "consumed."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
		]
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_NARRATIVE,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_NARRATIVE,
		]
	return _manifest
