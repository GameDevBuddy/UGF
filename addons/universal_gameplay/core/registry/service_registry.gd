class_name ServiceRegistry
extends RefCounted
## Maps service ids to service objects.
##
## Deliberately dumb. It resolves an id to an object and nothing else -- no
## construction, no lifecycle, no ordering. Anything cleverer would make Core
## a gameplay switchboard, which is exactly what rule 1 forbids.
##
## Values are typed as Object so a stateless service can be a RefCounted
## instead of a Node.

var _services: Dictionary[StringName, Object] = {}


## Replaces any existing registration under [param id]. Returns a result so
## callers can detect an accidental double-register rather than discovering it
## as a mystery later.
func register(id: StringName, service: Object) -> FrameworkResult:
	if id == &"":
		return FrameworkResult.fail(
			&"service.invalid_id", "Cannot register a service under an empty id."
		)
	if service == null:
		return FrameworkResult.fail(
			&"service.null", "Cannot register a null service under '%s'." % id
		)
	var replaced: bool = _services.has(id)
	_services[id] = service
	if replaced:
		return FrameworkResult.ok(true)
	return FrameworkResult.ok(false)


func unregister(id: StringName) -> bool:
	return _services.erase(id)


func get_service(id: StringName) -> Object:
	return _services.get(id, null)


func has_service(id: StringName) -> bool:
	if not _services.has(id):
		return false
	# A freed Node leaves a dangling entry behind; treat that as absent.
	return is_instance_valid(_services[id])


func get_service_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_services.keys())
	return ids


func size() -> int:
	return _services.size()


func clear() -> void:
	_services.clear()


## Drops entries whose object has been freed. Nodes registered as services can
## outlive their registration when a scene unloads.
func prune_invalid() -> int:
	var dead: Array[StringName] = []
	for id in _services:
		if not is_instance_valid(_services[id]):
			dead.append(id)
	for id in dead:
		_services.erase(id)
	return dead.size()
