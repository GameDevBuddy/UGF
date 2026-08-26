class_name FrameworkModule
extends RefCounted
## Base class for a removable feature module.
##
## A module is a registration unit, not a gameplay router. It declares what it
## is, wires up whatever services it owns, and tears them down again. Rule 10
## is the whole point: unregistering Commerce must leave Combat working.
##
## Modules receive the core as an argument rather than reaching for the
## autoload, so a module can be registered against a throwaway core in tests
## (rule 20).

## Overridden by every concrete module.
func get_manifest() -> ModuleManifest:
	return ModuleManifest.new()


## Called after dependency checks pass. Register services and adapters here.
func initialize(_core: Node) -> void:
	pass


## Called before the module is removed. Release everything [method initialize]
## claimed; the same module instance may be registered again afterwards.
func shutdown(_core: Node) -> void:
	pass


func get_id() -> StringName:
	return get_manifest().id
