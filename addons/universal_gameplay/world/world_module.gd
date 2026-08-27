extends FrameworkModule
## The World State module.
##
## Regions, which of them are awake, and who is in them. It holds no flags:
## [NarrativeStateService] already owns flags, variables and counters, and a
## region flag is a semantic id in that store rather than a second store
## (rule 23, rule 32).
##
## What lives here is what is genuinely not narrative — a population registry
## maintained on entry and exit, so asking how full a district is never costs
## more as the world grows.
##
## Requires nothing. Entity is optional and only how a [RegionTracker] finds
## its entity; Narrative is not required at all.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.world_state"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "World State"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Regions, activation and a population registry maintained on entry "
			+ "and exit, so population questions never scan the world."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_NARRATIVE,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
		]
	return _manifest
