class_name FileSaveBackend
extends SaveBackend
## Saves on disk. The only file in Persistence that touches the filesystem.
##
## Binary through [method FileAccess.store_var] rather than JSON, because the
## records carry [Transform3D] and [Vector3] values that JSON cannot represent
## without an encoder on both sides — and an encoder that has to know every
## type a component might save is exactly the "serialise arbitrary nodes"
## approach Implementation Plan 26 rules out.
##
## Slot metadata is a separate small file next to the save, so listing a save
## menu reads a few hundred bytes per row instead of a whole world.

## Where saves live. [code]user://[/code] by default, which Godot maps to the
## platform's own per-user directory.
var directory: String = "user://saves"

## Extension for the save itself.
var extension: String = ".save"

## Extension for the slot metadata written beside it.
var slot_extension: String = ".slot"


static func create(p_directory: String = "user://saves") -> FileSaveBackend:
	var backend := FileSaveBackend.new()
	backend.directory = p_directory
	return backend


func write(slot_id: StringName, save_data: Dictionary, slot_data: Dictionary) -> FrameworkResult:
	if slot_id == &"":
		return FrameworkResult.fail(&"save.no_slot", "A save needs a slot id.")
	var made := _ensure_directory()
	if made.is_err():
		return made

	# The save first, the slot second. A slot row describing a save that failed
	# to write is how a load menu comes to offer something that cannot be
	# loaded, and this order makes that impossible rather than unlikely.
	var wrote := _store(_save_path(slot_id), save_data)
	if wrote.is_err():
		return wrote
	return _store(_slot_path(slot_id), slot_data)


func read(slot_id: StringName) -> FrameworkResult:
	return _load(_save_path(slot_id), slot_id)


func read_slot(slot_id: StringName) -> FrameworkResult:
	return _load(_slot_path(slot_id), slot_id)


func exists(slot_id: StringName) -> bool:
	return FileAccess.file_exists(_save_path(slot_id))


func erase(slot_id: StringName) -> bool:
	if not exists(slot_id):
		return false
	var handle := DirAccess.open(directory)
	if handle == null:
		return false
	handle.remove(_file_name(slot_id, extension))
	handle.remove(_file_name(slot_id, slot_extension))
	return true


func list_slots() -> Array[StringName]:
	var ids: Array[StringName] = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return ids
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		if not handle.current_is_dir() and entry.ends_with(slot_extension):
			ids.append(StringName(entry.trim_suffix(slot_extension)))
		entry = handle.get_next()
	handle.list_dir_end()
	ids.sort()
	return ids


func clear() -> void:
	for slot_id in list_slots():
		erase(slot_id)


# --- Internals ------------------------------------------------------------

func _file_name(slot_id: StringName, suffix: String) -> String:
	# Slot ids reach here from a project and sometimes from a player naming a
	# save. Anything that could climb out of the save directory is stripped
	# rather than escaped: a save called "../../autoexec" must land in the
	# saves folder under a mangled name, not somewhere else entirely.
	var safe := String(slot_id).validate_filename()
	return "%s%s" % [safe if not safe.is_empty() else "unnamed", suffix]


func _save_path(slot_id: StringName) -> String:
	return directory.path_join(_file_name(slot_id, extension))


func _slot_path(slot_id: StringName) -> String:
	return directory.path_join(_file_name(slot_id, slot_extension))


func _ensure_directory() -> FrameworkResult:
	if DirAccess.dir_exists_absolute(directory):
		return FrameworkResult.ok(directory)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return FrameworkResult.fail(
			&"save.no_directory",
			"Could not create the save directory '%s' (error %d)." % [directory, error]
		)
	return FrameworkResult.ok(directory)


func _store(path: String, data: Dictionary) -> FrameworkResult:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return FrameworkResult.fail(
			&"save.write_failed",
			"Could not write '%s' (error %d)." % [path, FileAccess.get_open_error()]
		)
	handle.store_var(data, true)
	handle.close()
	return FrameworkResult.ok(path)


func _load(path: String, slot_id: StringName) -> FrameworkResult:
	if not FileAccess.file_exists(path):
		return FrameworkResult.fail(
			&"save.no_such_slot", "There is no save in slot '%s'." % slot_id
		)
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return FrameworkResult.fail(
			&"save.read_failed",
			"Could not read '%s' (error %d)." % [path, FileAccess.get_open_error()]
		)
	var data: Variant = handle.get_var(true)
	handle.close()
	if not (data is Dictionary):
		return FrameworkResult.fail(
			&"save.corrupt", "The save in slot '%s' is not readable." % slot_id
		)
	return FrameworkResult.ok(data)
