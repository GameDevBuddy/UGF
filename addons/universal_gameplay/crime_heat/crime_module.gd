extends FrameworkModule
## The Crime / Heat module.
##
## Optional, and meant to be. The plan's own settings example ships it off
## (`crime_heat=false`), because an arena shooter, a dungeon crawler and a
## farming game all want combat, factions and AI with no law at all.
##
## [b]It depends on nothing that depends on it.[/b] That is the M15 exit gate.
## Combat does not import Crime — a killing becomes an offence because
## [CombatCrimeAdapter] subscribes to [code]actor_died[/code], a fact Combat
## has published since M3. AI does not import Crime — a guard attacks a
## fugitive because [CrimeAIAdapter] hands it a [WantedHostilityProvider]
## through the seam AI declared in M7. Factions does not import Crime —
## [CrimeFactionAdapter] pushes standing in through Factions' existing public
## API. All three adapters live here, and all three are deletable.
##
## Combat needed no change at all for this milestone. Not one line.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.crime"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Crime and Heat"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Crimes, witnesses, wanted tiers and law response, layered on top "
			+ "of Combat, AI and Factions without any of them knowing."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_FACTIONS,
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_WORLD_STATE,
			GameplayNames.MODULE_NARRATIVE,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_FACTIONS,
		]
	return _manifest
