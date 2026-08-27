extends FrameworkModule
## The Stats module.
##
## Registers no services. Stats are entity-local with exactly one owner per
## entity (rule 4), and a global stat manager would hold every character's
## numbers while answering to none of them.
##
## Nothing else in the framework is required for stats to work: an entity with
## a [StatsComponent] and no health, no combat and no equipment has working
## attributes. That is the point of rule 10, tested rather than asserted.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.stats"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Stats"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Attributes and depletable resources, with source-tracked modifiers "
			+ "that stack in a fixed, documented order."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
		]
	return _manifest
