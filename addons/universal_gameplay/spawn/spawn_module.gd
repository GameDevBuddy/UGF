extends FrameworkModule
## The Spawn module.
##
## Pools, encounters, anchors, budgets and despawn policies. Nothing here
## discovers anything: anchors are registered into per-region buckets and
## populations are counted by [WorldStateService], so a tick's cost is set by
## how many regions are awake rather than by how large the world is.
##
## Traffic is a category rather than a class. "Spawn lanes, traffic agents,
## despawn, density hooks" is a [SpawnDefinition] whose entries are vehicles,
## whose anchors are lay-bys and whose despawn policy is aggressive — the same
## machinery pedestrians use, which is what stops the framework growing a
## parallel traffic system (rule 6 of the plan: roles are configuration, not a
## class hierarchy).
##
## Requires World State, which is where population lives. Entity, Narrative and
## Vehicles are optional.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.spawn"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Spawn"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Population pools, encounters, anchors and despawn policies, "
			+ "budgeted per region and ticked only where anybody is looking."
		)
		_manifest.requires = [GameplayNames.MODULE_WORLD_STATE]
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_VEHICLES,
			GameplayNames.MODULE_AI,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_WORLD_STATE,
		]
	return _manifest
