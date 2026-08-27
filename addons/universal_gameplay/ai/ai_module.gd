extends FrameworkModule
## The AI module.
##
## Perception, memory and brains, plus the controller that turns a decision
## into the same commands a player's controller issues. NPC roles live here
## too rather than in a module of their own: a role is a definition resource,
## and a module whose whole content is one [Resource] type is a folder, not a
## dependency (rule 23).
##
## Requires Entity for components to hang on. Everything else is optional:
## without Locomotion an NPC thinks and stands still, without Combat it never
## fights, without Interaction it opens no doors, and each of those is a whole
## valid kind of NPC rather than a broken one (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.ai"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "AI"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Perception with a memory that fades, brains as shared resources "
			+ "with no state of their own, and a controller that drives a "
			+ "character through the same API the player's does."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
		]
		_manifest.optional = [
			GameplayNames.MODULE_LOCOMOTION,
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_HEALTH,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_LOCOMOTION,
		]
	return _manifest
