extends FrameworkModule
## The Animation module.
##
## Presentation only. It registers no services, owns no gameplay state and can
## be removed from a project entirely -- a build with no Animation module has
## characters that move correctly and do not visibly animate, which is the
## right failure mode for a presentation layer (rule 21, rule 10).
##
## Locomotion is optional rather than required for the same reason: an adapter
## with nothing to observe is inert, not broken.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.animation"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Animation"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"AnimationTree adapter driven by movement state through a profile, "
			+ "so a rig's parameter layout stays out of gameplay code."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = [GameplayNames.MODULE_LOCOMOTION]
	return _manifest
