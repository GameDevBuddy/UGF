class_name FrameworkService
extends Node
## Base class for a broad-scoped service held in the service registry.
##
## Services are Nodes because the things that justify being a service --
## surviving scene changes, owning transitions, ticking on a timer -- are
## SceneTree concerns. Being registered does not make a service an autoload;
## autoloads stay scarce (rule 8) and most services are children of the core.
##
## The registry accepts any Object, so a stateless service may be a RefCounted
## instead of extending this class.

## Identity under which this service registers. Concrete services override it.
func get_service_id() -> StringName:
	return &""


## Called by the core once the service is registered and in the tree.
func service_started() -> void:
	pass


## Called before the service is unregistered.
func service_stopped() -> void:
	pass
