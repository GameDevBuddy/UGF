extends FrameworkTestCase
## What [FileSaveBackend] does with a save file it did not write.
##
## [b]Every other persistence test writes with the same backend it reads
## with.[/b] That makes them round-trip tests, and a round-trip test cannot
## fail on a hostile file, because it never produces one -- which is why 2,519
## of them passed over a backend that decoded objects out of a
## player-writable directory.
##
## So these tests do the thing the others structurally could not: they write
## the file by hand, the way anyone with a text editor and the save directory
## open can, and then ask the backend to load it.

const DIRECTORY: String = "user://ugf_security_saves"

var backend: FileSaveBackend = null


func before_each() -> void:
	backend = FileSaveBackend.create(DIRECTORY)
	backend.clear()


func after_each() -> void:
	backend.clear()
	super()


# --- The hole ------------------------------------------------------------

func test_a_save_carrying_an_object_is_refused_rather_than_decoded() -> void:
	# The one that matters. Godot's get_var decodes objects when asked to, and
	# a decoded object can carry a script that runs. Saves live where the
	# player can edit them and get synced between machines, so "the file is
	# trusted" was never true.
	var payload := _object_bearing_payload()

	# First prove the payload is actually dangerous, so this test cannot pass
	# because the bytes turned out to be inert.
	var decoded_with_objects: Variant = bytes_to_var_with_objects(payload)
	assert_true(
		decoded_with_objects is Dictionary,
		"The fixture did not survive its own encoding, so it proves nothing"
	)
	assert_true(
		(decoded_with_objects as Dictionary)["smuggled"] is Object,
		"The fixture carries no object, so refusing it would demonstrate nothing"
	)

	# Now the file, written the way an attacker writes it: checksum and all,
	# because anyone who can edit a save can recompute a checksum.
	_write_envelope(&"slot_hostile", payload, FileSaveBackend._checksum(payload))

	var read := backend.read(&"slot_hostile")
	assert_true(read.is_err(), "A save carrying an object was loaded")
	assert_eq(read.code, &"save.corrupt", "and was refused as unreadable")


func test_a_legacy_object_file_is_refused_too() -> void:
	# The other shape of the same attack: skip the envelope entirely and write
	# what the old code used to write. If this loaded, the envelope would be a
	# formality anyone could opt out of.
	var hostile := Resource.new()
	var handle := FileAccess.open(_path(&"slot_legacy"), FileAccess.WRITE)
	handle.store_var({"smuggled": hostile}, true)
	handle.close()

	var read := backend.read(&"slot_legacy")
	assert_true(read.is_err(), "A bare object file was loaded")


# --- Damage --------------------------------------------------------------

func test_an_edited_save_fails_its_checksum() -> void:
	_write_good_save(&"slot_edited", {"gold": 10})

	# The edit a player makes: change the bytes, leave the checksum alone.
	var path := _path(&"slot_edited")
	var stored: Dictionary = _read_envelope(path)
	var payload: PackedByteArray = stored[FileSaveBackend.PAYLOAD_KEY]
	payload[payload.size() - 1] = payload[payload.size() - 1] ^ 0xFF
	_write_envelope(&"slot_edited", payload, str(stored[FileSaveBackend.CHECKSUM_KEY]))

	var read := backend.read(&"slot_edited")
	assert_true(read.is_err(), "An edited save loaded anyway")
	assert_eq(read.code, &"save.tampered", "and was named as edited rather than merely broken")


func test_a_truncated_save_is_refused() -> void:
	_write_good_save(&"slot_cut", {"gold": 10})
	var path := _path(&"slot_cut")
	var raw := FileAccess.get_file_as_bytes(path)
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_buffer(raw.slice(0, raw.size() / 2))
	handle.close()

	assert_true(backend.read(&"slot_cut").is_err(), "Half a save loaded")


func test_a_good_save_still_round_trips() -> void:
	# The check that stops all of the above from being satisfied by a backend
	# that simply refuses everything.
	_write_good_save(&"slot_fine", {"gold": 10, "where": Vector3(1.0, 2.0, 3.0)})
	var read := backend.read(&"slot_fine")
	assert_ok(read)
	assert_eq((read.payload as Dictionary)["gold"], 10)
	assert_almost_eq(((read.payload as Dictionary)["where"] as Vector3).y, 2.0)


# --- Not losing the previous save ----------------------------------------

func test_the_previous_save_is_kept_when_a_new_one_replaces_it() -> void:
	_write_good_save(&"slot_gen", {"gold": 1})
	_write_good_save(&"slot_gen", {"gold": 2})

	assert_true(
		FileAccess.file_exists(_path(&"slot_gen") + FileSaveBackend.BACKUP_SUFFIX),
		"No backup was kept"
	)
	assert_eq(
		(backend.read(&"slot_gen").payload as Dictionary)["gold"], 2, "and the new save is current"
	)


func test_a_destroyed_save_falls_back_to_its_backup() -> void:
	_write_good_save(&"slot_fall", {"gold": 1})
	_write_good_save(&"slot_fall", {"gold": 2})

	# The power cut: the current save is gone or unreadable.
	var handle := FileAccess.open(_path(&"slot_fall"), FileAccess.WRITE)
	handle.store_buffer(PackedByteArray([1, 2, 3]))
	handle.close()

	var read := backend.read(&"slot_fall")
	assert_ok(read, "The backup was not used")
	assert_eq(
		(read.payload as Dictionary)["gold"], 1, "and it is the previous generation"
	)


func test_a_write_leaves_no_temporary_behind() -> void:
	_write_good_save(&"slot_tidy", {"gold": 1})
	assert_false(
		FileAccess.file_exists(_path(&"slot_tidy") + FileSaveBackend.TEMPORARY_SUFFIX),
		"A temporary file was left in the save directory"
	)


func test_erasing_a_slot_takes_its_backup_with_it() -> void:
	_write_good_save(&"slot_gone", {"gold": 1})
	_write_good_save(&"slot_gone", {"gold": 2})
	assert_true(backend.erase(&"slot_gone"))

	assert_false(
		FileAccess.file_exists(_path(&"slot_gone") + FileSaveBackend.BACKUP_SUFFIX),
		"A deleted game came back as its own backup"
	)
	assert_false(backend.exists(&"slot_gone"))


# --- Helpers --------------------------------------------------------------

func _path(slot_id: StringName) -> String:
	return DIRECTORY.path_join("%s.save" % String(slot_id).validate_filename())


func _write_good_save(slot_id: StringName, data: Dictionary) -> void:
	assert_ok(backend.write(slot_id, data, {"id": String(slot_id)}))


## A payload that decodes to a dictionary containing a live object.
func _object_bearing_payload() -> PackedByteArray:
	return var_to_bytes_with_objects({"gold": 10, "smuggled": Resource.new()})


func _write_envelope(slot_id: StringName, payload: PackedByteArray, checksum: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var handle := FileAccess.open(_path(slot_id), FileAccess.WRITE)
	handle.store_var(
		{
			FileSaveBackend.FORMAT_KEY: FileSaveBackend.FORMAT_VERSION,
			FileSaveBackend.CHECKSUM_KEY: checksum,
			FileSaveBackend.PAYLOAD_KEY: payload,
		},
		false
	)
	handle.close()


func _read_envelope(path: String) -> Dictionary:
	var handle := FileAccess.open(path, FileAccess.READ)
	var stored: Variant = handle.get_var(false)
	handle.close()
	return stored as Dictionary
