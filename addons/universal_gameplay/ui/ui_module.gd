extends FrameworkModule
## The UI module.
##
## [b]Presenters and view models. No widgets, and that is the deliverable.[/b]
## What a health bar looks like is a project's decision about its own game
## (rule 21, rule 29), and a framework that shipped one would ship the first
## thing every project deletes. What every project does need — and would
## otherwise write five slightly different times — is the discipline: a
## presenter observes, builds a plain-data snapshot, and emits it; a widget
## draws the snapshot and holds nothing live.
##
## That discipline is what makes the exit gate true. A [ViewModel] carries
## numbers and strings, never components, so a widget physically cannot mutate
## the world it draws — and a test reads every file here and fails on a call
## that would.
##
## Requires nothing. Every presenter's subject is optional: a HUD on an entity
## with no inventory publishes a panel that says so and draws nothing (rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.ui"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "UI Presentation"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Presenters and view models: observe, snapshot, emit. No widgets, "
			+ "and nothing a widget receives can change the world."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_DIALOGUE,
			GameplayNames.MODULE_MISSIONS,
			GameplayNames.MODULE_STATUS_EFFECTS,
			GameplayNames.MODULE_SURVIVAL,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_DIALOGUE,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_MISSIONS,
			GameplayNames.MODULE_STATUS_EFFECTS,
			GameplayNames.MODULE_SURVIVAL,
		]
	return _manifest
