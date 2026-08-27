extends FrameworkModule
## The Camera module.
##
## Registers no services and owns no global camera. A camera belongs to the
## entity it is framing, and split-screen is two entities with two rigs rather
## than one manager holding a mode flag (rule 8).
##
## Locomotion is optional, not required: [CameraAdapter] reads a mover for its
## sprint FOV cue when one is present and works without it, which is exactly
## the graceful degradation rule 31 asks for. A camera on a turret has no
## locomotion to read and is not broken for it.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.camera"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Camera"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"View profiles, look clamping and boom placement, applied to a rig "
			+ "the entity owns."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = [GameplayNames.MODULE_LOCOMOTION]
	return _manifest
