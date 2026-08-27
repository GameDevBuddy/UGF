extends FrameworkTestCase
## Covers SaveGame, SaveSlot, the backends, AutosavePolicy and
## MigrationRegistry: the platform around the round-trip.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var saves: SaveService = null
var narrative: NarrativeStateService = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	narrative = NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)
	saves.register_service(GameplayNames.SERVICE_NARRATIVE, narrative)


# --- SaveGame --------------------------------------------------------------

func test_a_save_carries_two_versions_that_move_independently() -> void:
	# Bumping the framework for a bug fix must not invalidate anybody's saves.
	var game := SaveGame.create()
	assert_eq(game.schema_version, FrameworkVersion.SAVE_SCHEMA)
	assert_eq(game.framework_version, FrameworkVersion.get_version_string())


func test_a_save_reports_whether_it_needs_migrating() -> void:
	var game := SaveGame.new()
	game.schema_version = FrameworkVersion.SAVE_SCHEMA - 1
	assert_true(game.needs_migration())
	assert_false(game.is_from_the_future())

	game.schema_version = FrameworkVersion.SAVE_SCHEMA + 1
	assert_false(game.needs_migration())
	assert_true(game.is_from_the_future())


func test_service_state_is_copied_rather_than_shared() -> void:
	# A save holding a live reference to a service's dictionary would change
	# under it between capture and write.
	var game := SaveGame.new()
	var state := {"flags": {"a": true}}
	game.set_service_state(&"service.x", state)
	state["flags"]["a"] = false
	assert_true(game.get_service_state(&"service.x")["flags"]["a"])


func test_entities_can_be_found_by_id_and_by_definition() -> void:
	var game := SaveGame.new()
	for index in 3:
		var record := EntityRecord.new()
		record.persistent_id = StringName("npc_%d" % index)
		record.definition_id = &"npc.guard" if index < 2 else &"npc.vendor"
		game.add_entity(record)

	assert_eq(game.get_entity_count(), 3)
	assert_true(game.has_entity(&"npc_1"))
	assert_size(game.find_entities_of(&"npc.guard"), 2)
	assert_size(game.find_entities_of(&"npc.vendor"), 1)


# --- SaveSlot --------------------------------------------------------------

func test_a_slot_describes_a_save_without_holding_it() -> void:
	# The whole reason slots are stored separately: six rows render without
	# deserialising six worlds.
	var game := SaveGame.create({"name": "Player"})
	game.playtime = 3600.0
	game.saved_at = 1234
	var slot := SaveSlot.describe(&"slot_1", game, "Chapter Two")

	assert_eq(slot.label, "Chapter Two")
	assert_almost_eq(slot.playtime, 3600.0)
	assert_eq(slot.saved_at, 1234)
	assert_eq(slot.schema_version, game.schema_version)


func test_a_slot_labels_itself_when_nobody_does() -> void:
	assert_eq(SaveSlot.create(&"slot_1").label, "slot_1")


func test_a_slot_knows_it_is_an_autosave() -> void:
	assert_true(SaveSlot.create(&"autosave_0").is_autosave())
	assert_false(SaveSlot.create(&"slot_1").is_autosave())


func test_a_future_slot_is_not_loadable() -> void:
	# A load menu greys out the row rather than letting the player click and
	# crash.
	var slot := SaveSlot.create(&"slot_1")
	slot.schema_version = FrameworkVersion.SAVE_SCHEMA + 1
	assert_false(slot.is_loadable())
	assert_true(SaveSlot.create(&"slot_2").is_loadable())


func test_a_slot_round_trips_through_plain_data() -> void:
	var slot := SaveSlot.create(&"slot_1", "Docks", {"chapter": 2})
	slot.playtime = 90.0
	var restored := SaveSlot.from_dictionary(slot.to_dictionary())
	assert_eq(restored.id, &"slot_1")
	assert_eq(restored.label, "Docks")
	assert_almost_eq(restored.playtime, 90.0)
	assert_eq(restored.summary["chapter"], 2)


# --- Slots through the service --------------------------------------------

func test_saving_and_listing_slots() -> void:
	narrative.set_flag(&"flag.a", true)
	assert_ok(saves.save(&"slot_1", "First"))
	assert_ok(saves.save(&"slot_2", "Second"))

	assert_true(saves.has_slot(&"slot_1"))
	var slots := saves.list_slots()
	assert_size(slots, 2)
	for slot in slots:
		assert_true(slot.label in ["First", "Second"])


func test_a_slot_can_be_read_without_reading_the_save() -> void:
	assert_ok(saves.save(&"slot_1", "First"))
	var read := saves.read_slot(&"slot_1")
	assert_ok(read)
	assert_eq((read.payload as SaveSlot).label, "First")


func test_a_missing_slot_is_refused() -> void:
	assert_err(saves.load_slot(&"slot_nothing"), &"save.no_such_slot")
	assert_err(saves.read_slot(&"slot_nothing"), &"save.no_such_slot")


func test_saving_with_no_slot_id_is_refused() -> void:
	assert_err(saves.save(&""), &"save.no_slot")


func test_a_slot_can_be_deleted() -> void:
	assert_ok(saves.save(&"slot_1"))
	assert_true(saves.delete_slot(&"slot_1"))
	assert_false(saves.has_slot(&"slot_1"))
	assert_false(saves.delete_slot(&"slot_1"), "and again is a no-op")


func test_saving_is_announced() -> void:
	var written: Array = []
	saves.saved.connect(
		func(slot_id: StringName, slot: SaveSlot) -> void:
			written.append([slot_id, slot.label])
	)
	assert_ok(saves.save(&"slot_1", "First"))
	assert_eq(written, [[&"slot_1", "First"]])


func test_loading_announces_before_and_after() -> void:
	# Before, so a project can fade out; after, so it can fade back in.
	var order: Array = []
	saves.loading.connect(func(_id: StringName, _s: SaveGame) -> void: order.append("loading"))
	saves.loaded.connect(func(_id: StringName, _s: SaveGame) -> void: order.append("loaded"))
	assert_ok(saves.save(&"slot_1"))
	assert_ok(saves.load_slot(&"slot_1"))
	assert_eq(order, ["loading", "loaded"])


func test_a_failure_is_announced_with_its_reason() -> void:
	var failures: Array = []
	saves.failed.connect(
		func(_id: StringName, operation: StringName, reason: StringName) -> void:
			failures.append([operation, reason])
	)
	assert_err(saves.load_slot(&"slot_nothing"), &"save.no_such_slot")
	assert_eq(failures, [[&"load", &"save.no_such_slot"]])


# --- Registration ----------------------------------------------------------

func test_a_service_with_no_capture_pair_is_refused() -> void:
	# Parented rather than orphaned: a bare Node.new() that is refused and
	# never freed leaks one ObjectDB instance, and the CI gate fails on that.
	var plain := Node.new()
	plain.name = "NotAService"
	add_test_node(plain)
	assert_err(saves.register_service(&"service.x", plain), &"save.not_persistent")


func test_an_entity_with_no_identity_is_refused() -> void:
	# Failing here is far better than at load, when the player has lost
	# something.
	var anonymous := Node3D.new()
	anonymous.name = "Anonymous"
	add_test_node(anonymous)
	assert_err(saves.register_entity(anonymous), &"save.no_identity")


func test_an_entity_marked_not_saveable_is_refused() -> void:
	var entity := Node3D.new()
	entity.name = "Ambient"
	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"ambient_1"
	identity.saveable = false
	entity.add_child(identity)
	add_test_node(entity)
	assert_err(saves.register_entity(entity), &"save.not_saveable")


func test_a_freed_entity_is_dropped_rather_than_failing_the_save() -> void:
	# The thing no longer exists, and a save that refused because of it would
	# be a save nobody could make.
	var entity := Node3D.new()
	entity.name = "Doomed"
	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"doomed"
	entity.add_child(identity)
	add_test_node(entity)
	assert_ok(saves.register_entity(entity))

	entity.get_parent().remove_child(entity)
	entity.free()

	var game := saves.capture()
	assert_eq(game.get_entity_count(), 0)
	assert_eq(saves.get_registered_entity_count(), 0)


func test_registrations_can_be_cleared() -> void:
	saves.clear_registrations()
	assert_empty(saves.get_registered_service_ids())
	assert_eq(saves.get_registered_entity_count(), 0)


# --- Backends --------------------------------------------------------------

func test_the_default_backend_keeps_saves_in_memory() -> void:
	# What makes the service testable with no disk, and what stops a project
	# with no backend crashing.
	var backend := SaveBackend.new()
	assert_ok(backend.write(&"slot_1", {"a": 1}, {"id": "slot_1"}))
	assert_true(backend.exists(&"slot_1"))
	assert_eq((backend.read(&"slot_1").payload as Dictionary)["a"], 1)
	assert_eq(backend.list_slots(), [&"slot_1"] as Array[StringName])


func test_a_backend_copies_what_it_is_given() -> void:
	var backend := SaveBackend.new()
	var data := {"a": 1}
	backend.write(&"slot_1", data, {})
	data["a"] = 2
	assert_eq((backend.read(&"slot_1").payload as Dictionary)["a"], 1)


func test_a_backend_write_with_no_slot_is_refused() -> void:
	assert_err(SaveBackend.new().write(&"", {}, {}), &"save.no_slot")


func test_the_file_backend_round_trips_through_disk() -> void:
	var backend := FileSaveBackend.create("user://ugf_test_saves")
	backend.clear()

	var game := SaveGame.create({"name": "Player"})
	game.playtime = 42.0
	var record := EntityRecord.new()
	record.persistent_id = &"survivor"
	record.definition_id = &"character.survivor"
	record.transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	record.has_transform = true
	game.add_entity(record)

	assert_ok(
		backend.write(
			&"slot_1", game.to_dictionary(), SaveSlot.describe(&"slot_1", game).to_dictionary()
		)
	)
	var read := backend.read(&"slot_1")
	assert_ok(read)

	var restored := SaveGame.from_dictionary(read.payload)
	assert_almost_eq(restored.playtime, 42.0)
	assert_eq(restored.get_entity_count(), 1)
	# The reason it is binary rather than JSON: a Transform3D survives with no
	# encoder on either side.
	assert_almost_eq(restored.get_entity(&"survivor").transform.origin.y, 2.0)
	backend.clear()


func test_the_file_backend_lists_and_erases() -> void:
	var backend := FileSaveBackend.create("user://ugf_test_saves")
	backend.clear()
	backend.write(&"slot_1", {"a": 1}, {"id": "slot_1"})
	backend.write(&"slot_2", {"a": 2}, {"id": "slot_2"})

	assert_size(backend.list_slots(), 2)
	assert_true(backend.erase(&"slot_1"))
	assert_size(backend.list_slots(), 1)
	assert_false(backend.exists(&"slot_1"))
	backend.clear()


func test_the_file_backend_refuses_to_be_walked_out_of_its_directory() -> void:
	# A save called "../../autoexec" must land in the saves folder under a
	# mangled name, not somewhere else entirely.
	var backend := FileSaveBackend.create("user://ugf_test_saves")
	backend.clear()
	assert_ok(backend.write(&"../../escape", {"a": 1}, {"id": "escape"}))
	assert_false(
		FileAccess.file_exists("user://escape.save"), "it did not climb out"
	)
	assert_true(backend.exists(&"../../escape"), "and is still readable by its id")
	backend.clear()


func test_reading_a_missing_file_is_refused_rather_than_crashing() -> void:
	var backend := FileSaveBackend.create("user://ugf_test_saves")
	backend.clear()
	assert_err(backend.read(&"slot_nothing"), &"save.no_such_slot")


# --- Autosave --------------------------------------------------------------

func _policy(interval: float = 10.0, slot_count: int = 3) -> AutosavePolicy:
	var policy := AutosavePolicy.new()
	policy.interval = interval
	policy.slot_count = slot_count
	policy.minimum_gap = 0.0
	return policy


func test_autosaving_rotates_through_its_slots() -> void:
	# A corrupted or badly-timed autosave costs one slot rather than the run.
	saves.autosave = _policy()
	for index in 4:
		assert_ok(saves.autosave_now())
	var ids := saves.backend.list_slots()
	assert_size(ids, 3, "three slots, four saves")
	assert_has(ids, &"autosave_0")
	assert_has(ids, &"autosave_2")


func test_autosaving_fires_on_the_interval() -> void:
	saves.autosave = _policy(10.0)
	saves.tick(5.0)
	assert_false(saves.has_slot(&"autosave_0"), "not yet")
	assert_almost_eq(saves.get_time_until_autosave(), 5.0)
	saves.tick(5.0)
	assert_true(saves.has_slot(&"autosave_0"))


func test_a_minimum_gap_stops_three_saves_in_one_room() -> void:
	saves.autosave = _policy()
	saves.autosave.minimum_gap = 30.0
	assert_ok(saves.autosave_now())
	saves.tick(5.0)
	assert_err(saves.autosave_now(), &"save.too_soon")
	saves.tick(30.0)
	assert_ok(saves.autosave_now())


func test_autosaving_can_be_switched_off() -> void:
	saves.autosave = _policy()
	saves.autosave.enabled = false
	assert_err(saves.autosave_now(), &"save.autosave_off")


func test_no_policy_means_no_autosave() -> void:
	assert_err(saves.autosave_now(), &"save.autosave_off")
	saves.tick(1000.0)
	assert_empty(saves.backend.list_slots())


func test_a_policy_names_the_events_it_saves_on() -> void:
	# The service subscribes to nothing: whatever bridges the bus asks.
	var policy := _policy()
	var triggers: Array[StringName] = [GameplayNames.EVENT_MISSION_COMPLETED]
	policy.trigger_events = triggers
	saves.autosave = policy

	assert_true(saves.should_autosave_on(GameplayNames.EVENT_MISSION_COMPLETED))
	assert_false(saves.should_autosave_on(GameplayNames.EVENT_ACTOR_DIED))


func test_a_policy_that_never_fires_is_a_warning() -> void:
	var policy := AutosavePolicy.new()
	policy.interval = 0.0
	assert_true(policy.validate().has_warnings())


func test_a_single_autosave_slot_is_worth_saying_something_about() -> void:
	var policy := _policy(10.0, 1)
	assert_true(policy.validate().count_of(ValidationIssue.Severity.INFO) > 0)


func test_playtime_accumulates_and_is_carried_into_the_save() -> void:
	saves.tick(60.0)
	saves.tick(30.0)
	assert_ok(saves.save(&"slot_1"))
	assert_almost_eq((saves.read_slot(&"slot_1").payload as SaveSlot).playtime, 90.0)


func test_the_service_does_not_process_every_frame() -> void:
	# Writing a file is the last thing that belongs in a frame callback.
	assert_false(saves.is_processing())
	assert_false(saves.is_physics_processing())


# --- The migration ladder --------------------------------------------------

class Step:
	extends SaveMigration

	func _init(from: int = 1) -> void:
		from_version = from
		to_version = from + 1
		description = "test step"

	func migrate(data: Dictionary) -> Dictionary:
		var applied: Array = data.get("applied", [])
		applied.append(from_version)
		data["applied"] = applied
		return data


func test_a_migration_that_skips_a_version_is_refused() -> void:
	# A step that skips a version leaves a hole nothing can cross.
	var jump := SaveMigration.new()
	jump.from_version = 1
	jump.to_version = 4
	assert_true(jump.validate().has_errors())
	assert_err(MigrationRegistry.new().register(jump), &"migration.not_a_step")


func test_two_migrations_from_the_same_version_are_refused() -> void:
	var ladder := MigrationRegistry.new()
	assert_ok(ladder.register(Step.new(1)))
	assert_err(ladder.register(Step.new(1)), &"migration.duplicate")


func test_steps_are_applied_in_order() -> void:
	var ladder := MigrationRegistry.new()
	for version in [3, 1, 2]:
		assert_ok(ladder.register(Step.new(version)))

	var climbed := ladder.migrate({"schema_version": 1}, 1, 4)
	assert_ok(climbed)
	assert_eq((climbed.payload as Dictionary)["applied"], [1, 2, 3])
	assert_eq(int((climbed.payload as Dictionary)["schema_version"]), 4)


func test_each_step_is_announced() -> void:
	var ladder := MigrationRegistry.new()
	var applied: Array = []
	ladder.step_applied.connect(
		func(from: int, to: int) -> void: applied.append([from, to])
	)
	ladder.register(Step.new(1))
	ladder.register(Step.new(2))
	assert_ok(ladder.migrate({}, 1, 3))
	assert_eq(applied, [[1, 2], [2, 3]])


func test_a_ladder_reports_whether_it_can_reach_the_target() -> void:
	var ladder := MigrationRegistry.new()
	ladder.register(Step.new(1))
	assert_ok(ladder.can_migrate(1, 2))
	assert_err(ladder.can_migrate(1, 3), &"migration.missing_step")
	assert_err(ladder.can_migrate(5, 2), &"migration.from_the_future")


func test_a_save_already_current_needs_no_steps() -> void:
	assert_ok(MigrationRegistry.new().can_migrate(2, 2))


func test_a_gap_in_the_ladder_is_a_validation_error() -> void:
	# So a missing step is a build failure rather than a support ticket.
	var ladder := MigrationRegistry.new()
	ladder.register(Step.new(1))
	assert_true(ladder.validate(4).has_errors())


func test_a_complete_ladder_validates_clean() -> void:
	var ladder := MigrationRegistry.new()
	ladder.register(Step.new(1))
	ladder.register(Step.new(2))
	assert_false(ladder.validate(3).has_errors())


func test_a_base_migration_does_nothing_and_that_is_valid() -> void:
	# A schema bump that only adds an optional field needs no work, and saying
	# so explicitly is better than a gap in the ladder.
	var noop := SaveMigration.new()
	noop.from_version = 1
	noop.to_version = 2
	noop.description = "adds an optional field"
	assert_false(noop.validate().has_errors())
	assert_eq(noop.migrate({"a": 1}), {"a": 1})
