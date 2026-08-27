extends FrameworkModule
## The Progression module.
##
## Experience, levels, skill points and perk unlocks -- Implementation Plan 12's
## Progression section, which the M0-M19 milestone roadmap never listed and so
## never built. It surfaced when the vertical slice gate for the shooter RPG
## asked for the "XP" leg of weapon -> damage -> loot -> equip -> XP/reputation
## -> mission and there was nothing to call.
##
## Requires nothing. Stats is optional and only where a skill's modifiers land;
## a character with no [StatsComponent] still levels correctly, it just has no
## numbers for the levels to change (rule 31). Narrative is optional and only
## consulted by skills that gate on a flag.
##
## Reputation progression, which the plan lists in the same section, is
## [FactionService]'s and is not duplicated here.
##
## No class_name: modules are instantiated by the catalog, not referenced
## globally.

const MODULE_ID: StringName = &"module.progression"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Progression"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Experience tracks, levels, skill points and perk unlocks. Grants "
			+ "stat modifiers and semantic states; never runs behaviour itself."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_NARRATIVE,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_STATS,
		]
	return _manifest
