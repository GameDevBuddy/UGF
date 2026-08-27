class_name SaveBackend
extends RefCounted
## Where saves are kept. The seam between the framework and a filesystem.
##
## [b]A seam, not a policy.[/b] Saves go to [code]user://[/code] in most
## projects, to a cloud service in some, to a platform's own save API on
## console, and to memory in a test. Declaring the question here and letting
## something else answer it is the same shape [HitProvider] and
## [VehicleControllerAdapter] have (rule 20).
##
## The default implementation is in-memory. That is deliberate: it makes
## [SaveService] testable with no disk at all, and a project that forgets to
## install a real backend gets saves that vanish on quit rather than a crash —
## loud enough to notice, quiet enough not to lose anything that mattered.

var _saves: Dictionary[StringName, Dictionary] = {}
var _slots: Dictionary[StringName, Dictionary] = {}


## Writes one save and its slot metadata together.
##
## Together on purpose: a slot row describing a save that failed to write is
## how a load menu comes to offer something that cannot be loaded.
func write(slot_id: StringName, save_data: Dictionary, slot_data: Dictionary) -> FrameworkResult:
	if slot_id == &"":
		return FrameworkResult.fail(&"save.no_slot", "A save needs a slot id.")
	_saves[slot_id] = save_data.duplicate(true)
	_slots[slot_id] = slot_data.duplicate(true)
	return FrameworkResult.ok(slot_id)


func read(slot_id: StringName) -> FrameworkResult:
	if not _saves.has(slot_id):
		return FrameworkResult.fail(
			&"save.no_such_slot", "There is no save in slot '%s'." % slot_id
		)
	return FrameworkResult.ok((_saves[slot_id] as Dictionary).duplicate(true))


## Slot metadata only, without reading the save.
##
## The whole reason slots are stored separately: a load menu renders six rows
## without deserialising six worlds.
func read_slot(slot_id: StringName) -> FrameworkResult:
	if not _slots.has(slot_id):
		return FrameworkResult.fail(
			&"save.no_such_slot", "There is no save in slot '%s'." % slot_id
		)
	return FrameworkResult.ok((_slots[slot_id] as Dictionary).duplicate(true))


func exists(slot_id: StringName) -> bool:
	return _saves.has(slot_id)


func erase(slot_id: StringName) -> bool:
	if not _saves.has(slot_id):
		return false
	_saves.erase(slot_id)
	_slots.erase(slot_id)
	return true


func list_slots() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_slots.keys())
	ids.sort()
	return ids


func clear() -> void:
	_saves.clear()
	_slots.clear()
