extends FrameworkModule
## The Interaction module.
##
## One pipeline for every "press E on a thing": doors, pickups, conversations,
## vehicle doors, terminals. Targets carry an [InteractionComponent] listing
## what can be done to them; actors carry an [InteractorComponent] that finds
## them, times the hold, and asks.
##
## Requires Entity for components to hang on. Everything else is optional:
## without Items and Inventory an [ItemRequirement] simply never passes, which
## is the correct answer for a keycard door in a project with no bags; without
## Stats an action that reads an attribute finds none (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.interaction"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Interaction"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Targets offer interactions, actors run them. Requirements, "
			+ "prompts, timed holds and action strategies, with the same "
			+ "entry point for a player and an AI."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
		]
		_manifest.optional = [
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_STATS,
		]
	return _manifest
