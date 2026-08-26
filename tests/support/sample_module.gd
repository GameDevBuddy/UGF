extends FrameworkModule
## Configurable module fixture. Records its own lifecycle so tests can assert
## that initialize and shutdown ran exactly when they should have.
##
## Configuration is an instance method rather than a static factory: a static
## factory here would have to load this script by path and return an untyped
## instance, which costs the caller every bit of static typing on the fixture.

var manifest: ModuleManifest = null
var initialize_count: int = 0
var shutdown_count: int = 0
var last_core: Node = null


func configure(
	id: StringName, requires: Array[StringName] = [], optional: Array[StringName] = []
) -> void:
	manifest = ModuleManifest.new()
	manifest.id = id
	manifest.display_name = str(id)
	manifest.requires = requires.duplicate()
	manifest.optional = optional.duplicate()


func get_manifest() -> ModuleManifest:
	return manifest


func initialize(core: Node) -> void:
	initialize_count += 1
	last_core = core


func shutdown(core: Node) -> void:
	shutdown_count += 1
	last_core = core
