class_name SaveService
extends FrameworkService
## Captures the world, writes it, and puts it back.
##
## [b]It serialises nothing itself.[/b] Every persistent component already owns
## [code]capture_state()[/code] and [code]restore_state()[/code], and every
## persistent service owns the same pair; this walks what it was given and
## aggregates the results (Implementation Plan 26). That is why a milestone
## can add a component with saved state and this file needs no change —
## fourteen of them have, and it has not.
##
## [b]Nothing is discovered.[/b] Entities and services are registered, not
## searched for. A save that swept the scene tree would be the global scan M14
## spent a milestone removing, arriving once per autosave instead of once per
## frame — which is worse, because it lands as a hitch rather than a
## slow average.

## Emitted after a successful write.
signal saved(slot_id: StringName, slot: SaveSlot)
## Emitted after a successful load, before anything has been restored, so a
## project can fade the screen out.
signal loading(slot_id: StringName, save: SaveGame)
## Emitted after everything has been put back.
signal loaded(slot_id: StringName, save: SaveGame)
## Emitted when a save or load failed, with why.
signal failed(slot_id: StringName, operation: StringName, reason: StringName)
## Emitted per migration step applied on load.
signal migrated(slot_id: StringName, from_version: int, to_version: int)

## Where saves are kept. In-memory by default, which is what makes this
## testable with no disk and what stops a project with no backend crashing.
var backend: SaveBackend = null

## The schema ladder. Empty is correct for a project that has never bumped
## its schema.
var migrations: MigrationRegistry = null

## Where entities are rebuilt from. Any object with
## [code]get_definition(id)[/code]; in practice the core.
var registry: Object = null

## Autosave settings. Null never autosaves.
var autosave: AutosavePolicy = null

## Carried into every save. What a project sets its player name and difficulty
## on.
var profile: Dictionary = {}

## Seconds played, carried into the save. Advanced by [method tick] when a
## project wants that, or set directly when it measures its own.
var playtime: float = 0.0

## Services whose state is saved, by service id. Registered rather than
## resolved from the core, so a project can save a subset — and so this file
## has no list of which services exist (rule 9).
var _services: Dictionary[StringName, Object] = {}

## Entities whose state is saved, by persistent id.
var _entities: Dictionary[StringName, Node] = {}

var _since_autosave: float = 0.0
var _since_any_save: float = 0.0
var _autosave_index: int = 0


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_SAVE


func configure(
	p_backend: SaveBackend = null,
	p_registry: Object = null,
	p_migrations: MigrationRegistry = null
) -> void:
	backend = p_backend if p_backend != null else SaveBackend.new()
	registry = p_registry
	migrations = p_migrations if p_migrations != null else MigrationRegistry.new()


func service_stopped() -> void:
	_services.clear()
	_entities.clear()


func _get_backend() -> SaveBackend:
	if backend == null:
		backend = SaveBackend.new()
	return backend


func _get_migrations() -> MigrationRegistry:
	if migrations == null:
		migrations = MigrationRegistry.new()
	return migrations


# --- Registration ---------------------------------------------------------

## Registers a service whose state should be saved.
##
## Anything with [code]capture_state()[/code] and [code]restore_state()[/code]
## qualifies — duck-typed rather than cast, so this file names no module and a
## project's own service saves the same way the framework's do.
func register_service(service_id: StringName, service: Object) -> FrameworkResult:
	if service_id == &"" or service == null:
		return FrameworkResult.fail(&"save.no_service", "There is no service to register.")
	if not service.has_method("capture_state") or not service.has_method("restore_state"):
		return FrameworkResult.fail(
			&"save.not_persistent",
			"'%s' has no capture_state/restore_state pair." % service_id
		)
	_services[service_id] = service
	return FrameworkResult.ok(service)


func unregister_service(service_id: StringName) -> bool:
	return _services.erase(service_id)


func get_registered_service_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_services.keys())
	return ids


## Registers an entity whose state should be saved.
##
## Refuses anything without a persistent id, because a record keyed on nothing
## cannot be put back — and failing here is far better than at load, when the
## player has lost something.
func register_entity(entity: Node) -> FrameworkResult:
	if entity == null:
		return FrameworkResult.fail(&"save.no_entity", "There is no entity to register.")
	var identity := EntitySerializer.find_identity(entity)
	if identity == null or identity.get_persistent_id() == &"":
		return FrameworkResult.fail(
			&"save.no_identity",
			"'%s' has no persistent id, so it could never be put back." % entity.name
		)
	if not identity.is_saveable():
		return FrameworkResult.fail(
			&"save.not_saveable", "'%s' is marked not saveable." % entity.name
		)
	_entities[identity.get_persistent_id()] = entity
	return FrameworkResult.ok(entity)


func unregister_entity(entity: Node) -> bool:
	if entity == null:
		return false
	var identity := EntitySerializer.find_identity(entity)
	if identity == null:
		return false
	return _entities.erase(identity.get_persistent_id())


func get_registered_entity_count() -> int:
	return _entities.size()


func get_registered_entity(persistent_id: StringName) -> Node:
	var candidate: Variant = _entities.get(persistent_id)
	if candidate == null or not is_instance_valid(candidate):
		return null
	return candidate as Node


func clear_registrations() -> void:
	_services.clear()
	_entities.clear()


# --- Capturing ------------------------------------------------------------

## Builds a save from everything registered, without writing it.
##
## Public and separate from [method save] so a project can inspect, augment or
## discard a capture — and so a test can round-trip without a backend at all.
func capture(issues: ValidationResult = null) -> SaveGame:
	var save := SaveGame.create(profile)
	save.playtime = playtime
	save.saved_at = int(Time.get_unix_time_from_system())

	for service_id in _services:
		var service: Object = _services[service_id]
		if service == null or not is_instance_valid(service):
			continue
		var state: Variant = service.call("capture_state")
		if state is Dictionary:
			save.set_service_state(service_id, state)

	for persistent_id in _entities.keys():
		var entity := get_registered_entity(persistent_id)
		if entity == null:
			# Registered and since freed. Dropping it silently is right: the
			# thing no longer exists, and a save that refused because of it
			# would be a save nobody could make.
			_entities.erase(persistent_id)
			continue
		var record := EntitySerializer.capture(entity, issues)
		if record != null:
			save.add_entity(record)
	return save


## Puts a captured save back into the live world.
##
## Services first, then entities. The order matters: an entity's
## [code]restore_state[/code] may ask a service a question — a seat asking who
## was aboard, a component asking what the narrative says — and a service
## restored afterwards would answer from the wrong world.
func apply(save: SaveGame) -> ValidationResult:
	var issues := ValidationResult.new()
	if save == null:
		issues.add_error(&"save.nothing_to_apply", "There is no save to apply.")
		return issues

	profile = save.profile.duplicate(true)
	playtime = save.playtime

	for service_id in save.get_service_ids():
		var service: Object = _services.get(service_id)
		if service == null or not is_instance_valid(service):
			# A save holding state for a module this build does not have.
			# Information rather than an error: removing an optional module
			# must not make existing saves unloadable (rule 31).
			issues.add_info(
				&"save.unknown_service",
				(
					"The save holds state for '%s', which is not registered "
					+ "here. It has been left alone."
				) % service_id,
				String(service_id)
			)
			continue
		service.call("restore_state", save.get_service_state(service_id))

	for record in save.entities:
		var entity := get_registered_entity(record.persistent_id)
		if entity == null:
			issues.add_info(
				&"save.unmatched_entity",
				(
					"The save holds '%s', which is not in the world. A spawner "
					+ "rebuilds it from its definition id."
				) % record.persistent_id,
				String(record.persistent_id)
			)
			continue
		issues.merge(EntitySerializer.restore(entity, record))
	return issues


## Rebuilds an entity the live world does not have, from its record.
##
## Separate from [method apply] on purpose: what to respawn and where to parent
## it is a project's decision, and a save service that guessed would be one
## deciding scene structure. This does the part that is the framework's — the
## definition lookup, the instantiation, the binding, the state — through the
## same [EntityFactory] every other load path uses.
func rebuild(record: EntityRecord, parent: Node) -> FrameworkResult:
	if record == null:
		return FrameworkResult.fail(&"save.no_record", "There is no record to rebuild.")
	if record.definition_id == &"":
		return FrameworkResult.fail(
			&"save.no_definition",
			"'%s' names no definition, so nothing can rebuild it." % record.persistent_id
		)
	var built := EntityFactory.spawn(registry, record.definition_id, parent)
	if built.is_err():
		return built

	var entity: Node = built.payload
	var identity := EntitySerializer.find_identity(entity)
	if identity != null:
		identity.set_persistent_id(record.persistent_id)
	EntitySerializer.restore(entity, record)
	register_entity(entity)
	return FrameworkResult.ok(entity)


# --- Slots ----------------------------------------------------------------

## Captures and writes in one call. What a save menu and an autosave both use.
func save(slot_id: StringName, label: String = "") -> FrameworkResult:
	if slot_id == &"":
		return _fail(slot_id, &"save", &"save.no_slot", "A save needs a slot id.")
	var game := capture()
	var slot := SaveSlot.describe(slot_id, game, label)
	var wrote := _get_backend().write(slot_id, game.to_dictionary(), slot.to_dictionary())
	if wrote.is_err():
		failed.emit(slot_id, &"save", wrote.code)
		return wrote
	_since_any_save = 0.0
	saved.emit(slot_id, slot)
	return FrameworkResult.ok(slot)


## Reads a slot, migrates it if it is old, and puts it back.
func load_slot(slot_id: StringName) -> FrameworkResult:
	var read := read_save(slot_id)
	if read.is_err():
		failed.emit(slot_id, &"load", read.code)
		return read

	var game: SaveGame = read.payload
	loading.emit(slot_id, game)
	var issues := apply(game)
	loaded.emit(slot_id, game)
	return FrameworkResult.ok(issues)


## Reads and migrates a slot without applying it.
##
## Separate because "can this save be loaded?" is a question a load menu asks
## about six slots before the player picks one, and because a migration that
## fails should say so before anything in the live world has moved.
func read_save(slot_id: StringName) -> FrameworkResult:
	var read := _get_backend().read(slot_id)
	if read.is_err():
		return read

	var data: Dictionary = read.payload
	var version := int(data.get("schema_version", 0))
	if version > FrameworkVersion.SAVE_SCHEMA:
		return FrameworkResult.fail(
			&"save.from_the_future",
			(
				"That save is schema %d and this build understands %d. It was "
				+ "written by a newer version of the game."
			) % [version, FrameworkVersion.SAVE_SCHEMA]
		)
	if version < FrameworkVersion.SAVE_SCHEMA:
		var ladder := _get_migrations()
		var climbed := ladder.migrate(data, version)
		if climbed.is_err():
			return climbed
		data = climbed.payload
		migrated.emit(slot_id, version, FrameworkVersion.SAVE_SCHEMA)
	return FrameworkResult.ok(SaveGame.from_dictionary(data))


## Slot metadata for the load menu, without reading any save.
func read_slot(slot_id: StringName) -> FrameworkResult:
	var read := _get_backend().read_slot(slot_id)
	if read.is_err():
		return read
	return FrameworkResult.ok(SaveSlot.from_dictionary(read.payload))


## Every slot on disk, newest first. What a load menu draws.
func list_slots() -> Array[SaveSlot]:
	var slots: Array[SaveSlot] = []
	for slot_id in _get_backend().list_slots():
		var read := read_slot(slot_id)
		if read.is_ok():
			slots.append(read.payload)
	slots.sort_custom(
		func(a: SaveSlot, b: SaveSlot) -> bool: return a.saved_at > b.saved_at
	)
	return slots


func has_slot(slot_id: StringName) -> bool:
	return _get_backend().exists(slot_id)


func delete_slot(slot_id: StringName) -> bool:
	return _get_backend().erase(slot_id)


# --- Autosave -------------------------------------------------------------

## Writes to the next autosave slot in the rotation.
##
## Rotating rather than overwriting is the point: a corrupted or badly-timed
## autosave costs one slot rather than the whole run.
func autosave_now(label: String = "") -> FrameworkResult:
	if autosave == null or not autosave.enabled:
		return FrameworkResult.fail(&"save.autosave_off", "Autosaving is switched off.")
	if _since_any_save < autosave.minimum_gap and _since_any_save > 0.0:
		return FrameworkResult.fail(
			&"save.too_soon", "Something was saved too recently."
		)
	var slot_id := autosave.get_slot_id(_autosave_index)
	var wrote := save(slot_id, label)
	if wrote.is_ok():
		_autosave_index += 1
		_since_autosave = 0.0
	return wrote


## Whether an event should trigger an autosave. Called by whatever bridges the
## bus, so this file subscribes to nothing and Persistence depends on no module
## that publishes.
func should_autosave_on(event_name: StringName) -> bool:
	return autosave != null and autosave.triggers_on(event_name)


func get_time_until_autosave() -> float:
	if autosave == null or not autosave.saves_on_a_timer():
		return 0.0
	return maxf(0.0, autosave.interval - _since_autosave)


## Advances the autosave clock and the playtime counter, and saves when due.
##
## Ticked rather than processed: writing a file is the last thing that belongs
## in a frame callback, and the plan's performance rules put low-rate
## simulation on a timer (rule 26).
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	playtime += delta
	_since_any_save += delta
	if autosave == null or not autosave.saves_on_a_timer():
		return
	_since_autosave += delta
	if _since_autosave >= autosave.interval:
		autosave_now()


# --- Internals ------------------------------------------------------------

func _fail(
	slot_id: StringName, operation: StringName, code: StringName, message: String
) -> FrameworkResult:
	failed.emit(slot_id, operation, code)
	return FrameworkResult.fail(code, message)
