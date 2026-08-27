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
##
## [b]Objects are not decoded, and that is a security boundary rather than a
## preference.[/b] This file used to pass [code]true[/code] to
## [method FileAccess.store_var] and [method FileAccess.get_var], which is
## Godot's [code]allow_objects[/code] flag. The engine's own documentation is
## blunt about it: a deserialised object can carry a script, and that script
## runs. A save file lives in a directory the player can write, gets synced
## between machines by Steam or a console's cloud, and gets passed around in
## forum threads when someone wants help with a broken run. Any of those is a
## path from a modified file to code execution inside the game.
##
## Nothing was gained by it. [Transform3D] and [Vector3] are Variant types, not
## objects, and they round-trip perfectly well with the flag off — the very
## thing the paragraph above claims as the reason for binary. Plan 26 already
## forbids saving nodes, so a save that genuinely needed object decoding would
## be a save that had broken that rule.
##
## Three further protections against a save that is damaged rather than
## hostile, because losing a hundred-hour run to a power cut is its own kind of
## failure: writes land on a temporary file and are renamed into place, the
## previous save is kept beside the new one, and a checksum records what was
## written so a truncated or edited file is refused rather than half-loaded.
##
## [b]The checksum is not a security control.[/b] Anyone who can edit a save
## can recompute it, and there is no key here to stop them. It catches
## corruption and casual tampering, and it is the object flag above that stops
## a hostile save from running code. A project that needs saves to be
## genuinely tamper-proof wants a signature and a secret this framework has
## nowhere to keep.

## Where saves live. [code]user://[/code] by default, which Godot maps to the
## platform's own per-user directory.
var directory: String = "user://saves"

## Extension for the save itself.
var extension: String = ".save"

## Extension for the slot metadata written beside it.
var slot_extension: String = ".slot"

## Suffix for the previous save, kept when a new one replaces it.
const BACKUP_SUFFIX: String = ".bak"

## Suffix for a write in progress, renamed into place once it is complete.
const TEMPORARY_SUFFIX: String = ".tmp"

## Version of the container format, not of the save's contents.
##
## Separate from [member FrameworkVersion.SAVE_SCHEMA] on purpose: that number
## describes what a save means and moves when a module changes what it stores.
## This one describes the envelope around it and moves only when the file
## layout itself changes.
const FORMAT_VERSION: int = 1

const FORMAT_KEY: StringName = &"format"
const CHECKSUM_KEY: StringName = &"checksum"
const PAYLOAD_KEY: StringName = &"payload"


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
	# The backup counts. read() will load it when the primary is gone, and a
	# save menu that hides a slot the game can still load is a save the player
	# has lost for no reason.
	var path := _save_path(slot_id)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BACKUP_SUFFIX)


func erase(slot_id: StringName) -> bool:
	if not exists(slot_id):
		return false
	var handle := DirAccess.open(directory)
	if handle == null:
		return false
	# The backup and any abandoned temporary go with it. A backup that outlives
	# the save it belonged to is a deleted game that comes back, which is worse
	# than a deleted game.
	for suffix in [extension, slot_extension]:
		var base := _file_name(slot_id, suffix)
		handle.remove(base)
		handle.remove(base + BACKUP_SUFFIX)
		handle.remove(base + TEMPORARY_SUFFIX)
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


## Writes [param data] so that a failure part-way through cannot destroy what
## was already there.
##
## The write lands on a temporary file first and is renamed into place only
## once it is closed. A rename is the cheapest thing a filesystem offers that
## is either done or not done, which is what a save needs: the alternative --
## opening the real file and writing into it -- means a crash, a power cut or a
## full disk leaves the player with a file that is neither the old save nor the
## new one.
##
## The previous save moves aside rather than being overwritten, so there is
## always one generation to fall back on.
func _store(path: String, data: Dictionary) -> FrameworkResult:
	var temporary := path + TEMPORARY_SUFFIX
	var handle := FileAccess.open(temporary, FileAccess.WRITE)
	if handle == null:
		return FrameworkResult.fail(
			&"save.write_failed",
			"Could not write '%s' (error %d)." % [temporary, FileAccess.get_open_error()]
		)

	var payload := var_to_bytes(data)
	handle.store_var(
		{
			FORMAT_KEY: FORMAT_VERSION,
			CHECKSUM_KEY: _checksum(payload),
			PAYLOAD_KEY: payload,
		},
		false
	)
	handle.close()

	# Godot reports a short write through the file's error state rather than
	# through store_var, so a disk that filled up mid-save is only visible by
	# asking afterwards. Checking here keeps a truncated file from being
	# renamed over a good one.
	if FileAccess.get_open_error() != OK and not FileAccess.file_exists(temporary):
		return FrameworkResult.fail(
			&"save.write_failed", "Nothing was written to '%s'." % temporary
		)

	var directory_handle := DirAccess.open(directory)
	if directory_handle == null:
		return FrameworkResult.fail(
			&"save.write_failed", "Could not open the save directory '%s'." % directory
		)

	if FileAccess.file_exists(path):
		var backup := path + BACKUP_SUFFIX
		if FileAccess.file_exists(backup):
			directory_handle.remove(backup.get_file())
		var moved := directory_handle.rename(path.get_file(), backup.get_file())
		if moved != OK:
			return FrameworkResult.fail(
				&"save.write_failed",
				"Could not move the previous save aside (error %d)." % moved
			)

	var renamed := directory_handle.rename(temporary.get_file(), path.get_file())
	if renamed != OK:
		return FrameworkResult.fail(
			&"save.write_failed",
			"Could not put '%s' into place (error %d)." % [path, renamed]
		)
	return FrameworkResult.ok(path)


static func _checksum(payload: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	return context.finish().hex_encode()


## Reads a save, falling back to the backup when the primary will not load.
##
## A save that fails its checksum is refused rather than repaired. Half a save
## is not a save: restoring from one leaves a world where some entities know
## about a quest and others do not, which is far harder to notice, and far
## worse to meet, than being told the file is damaged.
func _load(path: String, slot_id: StringName) -> FrameworkResult:
	var backup := path + BACKUP_SUFFIX
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup):
		return FrameworkResult.fail(
			&"save.no_such_slot", "There is no save in slot '%s'." % slot_id
		)

	var primary := _read_file(path, slot_id)
	if primary.is_ok():
		return primary
	if not FileAccess.file_exists(backup):
		return primary

	var fallback := _read_file(backup, slot_id)
	if fallback.is_ok():
		return fallback
	# Report the primary's problem, not the backup's. The player asked for
	# their save; that the spare is also broken is not the headline.
	return primary


func _read_file(path: String, slot_id: StringName) -> FrameworkResult:
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
	# false is the whole point: with objects allowed, a file anyone can edit
	# decides what classes this process instantiates.
	var stored: Variant = handle.get_var(false)
	handle.close()

	if not (stored is Dictionary):
		return FrameworkResult.fail(
			&"save.corrupt", "The save in slot '%s' is not readable." % slot_id
		)

	var envelope: Dictionary = stored
	if not envelope.has(PAYLOAD_KEY):
		return FrameworkResult.fail(
			&"save.corrupt",
			(
				"The save in slot '%s' is not in a format this version can read. "
				+ "A save written before checksums were added reads as damaged; "
				+ "there is no way to tell it apart from one that is."
			) % slot_id
		)

	var payload: Variant = envelope[PAYLOAD_KEY]
	if not (payload is PackedByteArray):
		return FrameworkResult.fail(
			&"save.corrupt", "The save in slot '%s' is not readable." % slot_id
		)

	if str(envelope.get(CHECKSUM_KEY, "")) != _checksum(payload):
		return FrameworkResult.fail(
			&"save.tampered",
			(
				"The save in slot '%s' does not match its checksum, so it has been "
				+ "edited or damaged since it was written."
			) % slot_id
		)

	# bytes_to_var cannot decode objects at all -- that is a separate function,
	# bytes_to_var_with_objects, which this file must never call. Worth saying
	# rather than leaving to be rediscovered: the payload is attacker-controlled
	# bytes, so swapping in the other spelling would reopen everything the
	# get_var above closes.
	var data: Variant = bytes_to_var(payload)
	if not (data is Dictionary):
		return FrameworkResult.fail(
			&"save.corrupt", "The save in slot '%s' is not readable." % slot_id
		)
	return FrameworkResult.ok(data)
