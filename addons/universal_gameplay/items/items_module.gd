extends FrameworkModule
## The Items module.
##
## Provides the item definition, the per-instance state that goes with it, and
## the world pickup. Registers no services: an item instance belongs to
## whatever holds it (rule 4).
##
## Requires nothing but Entity. Items exist without inventories, without
## equipment and without commerce -- a pickup lying in a level is a complete
## use of this module on its own.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.items"

## The pickup scene, so a project can drop an item without knowing where the
## addon lives on disk.
const PICKUP_SCENE: String = "res://addons/universal_gameplay/items/item_pickup.tscn"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Items"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Shared item definitions, per-instance state with durability and "
			+ "stacking, and the world pickup that carries one."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		# An ItemDefinition carries a profile from each of these as a typed
		# @export, and an ItemInstance holds StatModifiers. None of it is
		# needed for an item to exist -- a rock has no weapon profile -- but
		# every one is a compile-time reference to a sibling, and rule 36 wants
		# it written down where the registry and the docs can see it.
		_manifest.optional = [
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_SURVIVAL,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_INVENTORY,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_SURVIVAL,
		]
	return _manifest
