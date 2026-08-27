extends FrameworkModule
## The Narrative State module.
##
## One service holding the four kinds of thing a story remembers: flags,
## variables, counters and standing between named parties. Deliberately
## separate from Dialogue: missions, world state, crime and commerce all read
## and write narrative state, and none of them should have to install a
## conversation runtime to do it (rule 9, rule 10).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.narrative"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Narrative State"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Flags, variables, counters and relationships that outlive the "
			+ "entities they describe."
		)
		_manifest.requires = []
		_manifest.optional = []
	return _manifest
