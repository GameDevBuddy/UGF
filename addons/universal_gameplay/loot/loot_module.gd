extends FrameworkModule
## The Loot module.
##
## Weighted tables with guaranteed entries and nested sub-tables, rolled with
## an injected [RandomNumberGenerator] so a drop is reproducible in a test and
## shareable across clients.
##
## Requires Items for something to drop and Inventory for somewhere to put it.
## Health is optional and is only how a corpse knows to roll -- observed
## through a local signal on a sibling component, so nothing here imports
## Combat (rule 7, rule 9).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.loot"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Loot"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Weighted loot tables rolled once per corpse, with guaranteed "
			+ "drops, nested tables and deterministic randomness."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
		]
		_manifest.optional = [
			# LootComponent reads narrative flags for conditional entries and
			# deposits currency into a wallet. Both are optional -- a drop with
			# no flag store is ineligible, a coin with no wallet lands nowhere
			# -- but both are compile-time references to a sibling.
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_COMMERCE,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
		]
	return _manifest
