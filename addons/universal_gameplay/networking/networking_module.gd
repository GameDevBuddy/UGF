extends FrameworkModule
## The Networking module.
##
## [b]Optional, and the plan is emphatic about it:[/b] "do not make networking
## a mandatory dependency. Instead, define mutation APIs so an authority
## adapter can sit in front of them" (Implementation Plan 27).
##
## Seventeen milestones of insisting every mutation be a method returning a
## [FrameworkResult] is what makes that possible. The adapters here register
## handlers that call those methods and add nothing; not one line changed in
## Inventory or Combat for this milestone.
##
## [b]Offline is not a special case.[/b] The default transport is
## authoritative and the default policy owns nothing, so a command runs
## in-process on the same line — the single-player path and the hosting path
## are one path, which is why "offline mode unchanged" is a property of the
## design rather than something to re-verify each release.
##
## Requires nothing. No module outside this folder names a peer, an intent or
## the authority service, and a test asserts it.
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.networking"

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Networking"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"An authority facade in front of mutation APIs the modules already "
			+ "had, with a transport seam and server-side validation."
		)
		_manifest.requires = []
		_manifest.optional = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_ITEMS,
		]
	return _manifest
