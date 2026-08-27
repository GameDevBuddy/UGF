extends FrameworkModule
## The Survival module.
##
## Generic meters that drain, what refills them, and places that change how
## fast they drain. Hunger, thirst, fatigue, oxygen and body temperature are
## one [NeedDefinition] with different numbers -- temperature drains towards a
## comfortable middle rather than towards empty, which is a field rather than a
## second mechanism.
##
## Requires nothing. Health is optional and only how an empty need hurts;
## Status Effects is optional and only how a critical one debuffs; Items and
## Inventory are optional and only how something is eaten. A creature that
## starves and cannot use items is a whole valid entity (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.survival"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Survival"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Needs that drain and save, consumables that refill them, and "
			+ "environment zones that scale the rate rather than draining "
			+ "directly, so overlapping zones compose."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_STATUS_EFFECTS,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_STATUS_EFFECTS,
		]
	return _manifest
