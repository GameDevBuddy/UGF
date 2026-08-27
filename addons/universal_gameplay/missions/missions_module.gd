extends FrameworkModule
## The Missions module.
##
## [b]It imports nothing it reacts to.[/b] An objective names a bus event and a
## few field matchers; the events themselves are published by Health, Dialogue,
## Inventory and area triggers, each through its own deletable adapter. That is
## the M9 exit gate, and it is why this manifest lists no feature module as
## required (rule 9, rule 10).
##
## The cost, stated plainly: field names are strings, so a typo is content that
## silently never matches. [EventMatcher] documents it and validation catches
## what it can.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.missions"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Missions"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Event-driven objectives, sequencing, rewards and failure hooks. "
			+ "One objective definition covers the fourteen baseline kinds, "
			+ "because they differ in which event they count, not in code."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
		]
	return _manifest
