extends FrameworkModule
## The Factions module.
##
## Standing between named parties, the bands that turn it into behaviour, and
## two adapters that hand the result to systems which know nothing about
## factions: [FactionAIAdapter] for hostility and [FactionPriceAdapter] for
## pricing.
##
## Requires nothing. Depending on Entity would be wrong: standing is between
## names, and a faction service is useful to a strategy layer with no entities
## in it at all. [FactionComponent] needs Entity, and a project that uses only
## the service does not need the component.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.factions"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Factions"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Directional standing between factions and actors, resolved into "
			+ "attitude bands, and consumed by AI and pricing through adapters "
			+ "that neither side has to know about."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_COMMERCE,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_ENTITY,
		]
	return _manifest
