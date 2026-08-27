extends FrameworkModule
## The Persistence module.
##
## Slots, profiles, autosave and schema migration, on top of the
## capture/restore pair every persistent component has owned since M1.
##
## [b]It serialises nothing itself.[/b] [SaveService] walks what it was given
## and aggregates the results, which is why fourteen milestones have added
## components with saved state and this module has needed no change for any of
## them. A save platform that knew what an inventory was would need editing
## every time one gained a field.
##
## Requires Entity, which owns the records and the identities. Everything else
## is optional: a save holding state for a module this build does not have is
## reported and left alone, so removing an optional module never makes an
## existing save unloadable (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.save"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Persistence"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Save slots, profiles, autosave rotation and step-by-step schema "
			+ "migration, aggregating state the components already own."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = []
	return _manifest
