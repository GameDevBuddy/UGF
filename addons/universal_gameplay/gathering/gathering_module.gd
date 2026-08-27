extends FrameworkModule
## The Gathering module.
##
## Resource nodes that yield through M11's loot tables, wear the tool used on
## them, spend charges and respawn. Reusing loot tables rather than inventing a
## yield list is the point: "a weighted table with guaranteed entries" is one
## idea, and two implementations of it would drift apart (rule 23).
##
## Requires Items, Inventory and Loot. Interaction is optional and only how a
## player reaches a node; an AI or a script calls
## [method ResourceNode.harvest] directly.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.gathering"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Gathering"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Resource nodes with tool requirements, tool wear, charges and "
			+ "respawn, yielding through loot tables."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_LOOT,
		]
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_INTERACTION,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_LOOT,
		]
	return _manifest
