extends FrameworkModule
## The Combat module.
##
## Attacks, weapons, ammunition and the geometry of a hit. Melee and ranged are
## the same pipeline with different delivery resources, and a player and an AI
## reach it through the same [method CombatComponent.attack].
##
## Requires Entity for components to hang on and Health for damage to land on.
## Items, Equipment, Stats and Inventory are optional: without Equipment a
## weapon is set directly, without Stats attacks are free, and without
## Inventory ammunition comes from an abstract reserve (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.combat"

const PROJECTILE_SCENE: String = (
	"res://addons/universal_gameplay/combat/projectile.tscn"
)

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Combat"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Attacks as data, weapons as profiles, and one command API for a "
			+ "player and an AI. Hit queries go through a provider seam so "
			+ "combat is decidable without a physics frame."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
		]
		_manifest.optional = [
			# CombatComponent can open its damage window on an animation
			# event instead of on authored timing. Optional in both
			# directions: no relay means the authored startup runs.
			GameplayNames.MODULE_ANIMATION,
			# TargetingComponent draws its lock-on candidates from an NPC's
			# perception memory when there is one, and from a list handed to
			# it when there is not.
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_STATS,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_ANIMATION,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_STATS,
		]
	return _manifest
