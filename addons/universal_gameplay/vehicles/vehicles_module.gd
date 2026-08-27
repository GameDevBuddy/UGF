extends FrameworkModule
## The Vehicles module.
##
## Identity, seats, fuel, damage, storage, upgrades, cameras and possession.
## How a vehicle actually moves is behind [VehicleControllerAdapter], which is
## the boundary Implementation Plan 22 insists on: a project using
## [VehicleBody3D], one using a kinematic body and a headless server are all
## drivable through the same six calls, and traffic AI reaches them without
## knowing which is installed.
##
## Requires Entity. Everything else is optional and degrades to something
## sensible: no Input is a vehicle only an AI can drive, no Health is one that
## cannot be wrecked, no Inventory is one with no boot, no Equipment is one
## that cannot be upgraded, no Interaction is one entered by script rather than
## by pressing E (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.vehicles"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Vehicles"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Vehicle identity, seats, fuel, damage, storage and possession, "
			+ "driven through one adapter that player and AI share."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = [
			GameplayNames.MODULE_INPUT,
			GameplayNames.MODULE_CAMERA,
			GameplayNames.MODULE_CHARACTER,
			GameplayNames.MODULE_LOCOMOTION,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_AI,
		]
	return _manifest
