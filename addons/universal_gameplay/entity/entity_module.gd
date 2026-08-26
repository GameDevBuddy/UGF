extends FrameworkModule
## The Entity module.
##
## Entity is the first real module, and it is deliberately a thin one. It
## registers no services and owns no gameplay: binding, identity and
## serialisation are all static or component-local. What it provides is a
## declared presence, so an adapter can ask whether entity support is available
## before assuming a binder exists.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.entity"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Entity"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Definition binding, persistent identity, semantic state and "
			+ "entity state capture/restore."
		)
	return _manifest
