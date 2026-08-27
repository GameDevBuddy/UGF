extends FrameworkModule
## The Locomotion module.
##
## Registers no services. Movement is entity-local state with exactly one
## owner per entity ([MovementComponent]), which is what rule 4 asks for and
## what rule 8 means by an autoload having to justify itself -- a global
## movement manager would own every character's velocity and answer to none of
## them.
##
## Requires Entity because a [MovementComponent] is a [FrameworkComponent], and
## components only receive their configuration through the binder's context.
## That dependency is declared here rather than discovered at runtime (rule 36).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.locomotion"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Locomotion"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Ground and air movement: profiles, a solver with no node "
			+ "dependency, and one movement capability per entity."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
		]
	return _manifest
