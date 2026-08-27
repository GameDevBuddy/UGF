extends FrameworkModule
## The Dialogue module.
##
## A conversation runtime that presents nothing: it says which line is current
## and which options are open, and a project draws them. Conditions query,
## actions mutate, and the split between them is load-bearing -- a condition
## decides whether to [i]offer[/i] a choice, so one with a side effect fires
## for options the player never picked.
##
## Requires Entity for components to hang on. Narrative State is optional: a
## conversation with no conditions and no consequences needs no store, and
## everything degrades to "unknown" rather than erroring (rule 31). Items is
## optional too, and only an [ItemCondition] notices its absence.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.dialogue"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Dialogue"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Branching conversations as content, with conditions that query "
			+ "and actions that mutate, and choices promoted to cross-feature "
			+ "events by a deletable adapter."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
		]
		_manifest.optional = [
			GameplayNames.MODULE_NARRATIVE,
			GameplayNames.MODULE_ITEMS,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_INPUT,
			GameplayNames.MODULE_INTERACTION,
		]
	return _manifest
