extends FrameworkModule
## The Health and Damage module.
##
## Owns the damage pipeline, the health capability and the seam that promotes a
## death to a cross-feature fact. Registers no services: health is entity-local
## with one owner (rule 4).
##
## Stats is optional, not required. A crate with 40 hit points and no attributes
## is a legitimate damageable entity, and [HealthComponent] falls back to its
## exported maximum when no [StatsComponent] is wired up (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.health"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Health and Damage"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"A deterministic mitigation pipeline, one number that says whether an "
			+ "entity is standing, and an explicit seam that publishes its death."
		)
		_manifest.requires = [GameplayNames.MODULE_ENTITY]
		_manifest.optional = [GameplayNames.MODULE_STATS]
	return _manifest
