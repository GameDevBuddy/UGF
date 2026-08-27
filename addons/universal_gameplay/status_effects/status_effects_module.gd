extends FrameworkModule
## The Status Effects module.
##
## Buffs, debuffs, poisons and burns, all as data. Registers no services:
## effects live on the entity they affect (rule 4).
##
## Stats and Health are optional. An effect with only semantic state tags works
## on an entity with neither, an effect with modifiers needs Stats, and one with
## periodic damage needs a damage receiver -- and each degrades to doing less
## rather than to an error (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.status_effects"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Status Effects"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Timed and permanent effects with stacking policies, periodic damage "
			+ "and modifiers that unwind cleanly however they overlap."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = [
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_HEALTH,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_STATS,
		]
	return _manifest
