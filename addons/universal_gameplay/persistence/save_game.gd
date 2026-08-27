class_name SaveGame
extends RefCounted
## One whole saved game: who was playing, what the world knew, and everybody
## in it.
##
## The document Implementation Plan 26 describes, and nothing more. It holds
## plain data — no nodes, no scene graph, no resources — because a save that
## referenced live objects would be a save that only loads back into the
## session that wrote it (rule 9 of the plan's save rules).
##
## [b]Two versions, moving independently.[/b] The framework version records
## which build wrote the file, for diagnostics. The schema version is what
## migrations are registered against, and only moves when the shape of
## persisted data changes. Bumping the framework for a bug fix must not
## invalidate anybody's saves.

## Which build wrote this.
var framework_version: String = FrameworkVersion.get_version_string()

## What migrations are registered against.
var schema_version: int = FrameworkVersion.SAVE_SCHEMA

## Who was playing: name, difficulty, chosen options. Deliberately free-form —
## a profile is a project's business and the framework only carries it.
var profile: Dictionary = {}

## Per-service state, keyed by service id. Narrative, factions, missions,
## world state and heat all land here through their own
## [code]capture_state()[/code], and none of them knows the others exist.
var services: Dictionary = {}

## Everybody worth saving.
var entities: Array[EntityRecord] = []

## When it was written, as a Unix timestamp. Set by the service rather than
## here, so a test can write a save without the clock in it.
var saved_at: int = 0

## Seconds played. Carried, never computed: how a project measures playtime is
## its own decision.
var playtime: float = 0.0


static func create(profile_data: Dictionary = {}) -> SaveGame:
	var save := SaveGame.new()
	save.profile = profile_data.duplicate(true)
	return save


# --- Services -------------------------------------------------------------

func set_service_state(service_id: StringName, state: Dictionary) -> void:
	services[String(service_id)] = state.duplicate(true)


func get_service_state(service_id: StringName) -> Dictionary:
	return services.get(String(service_id), {})


func has_service_state(service_id: StringName) -> bool:
	return services.has(String(service_id))


func get_service_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in services:
		ids.append(StringName(key))
	return ids


# --- Entities -------------------------------------------------------------

func add_entity(record: EntityRecord) -> void:
	if record != null:
		entities.append(record)


func get_entity(persistent_id: StringName) -> EntityRecord:
	for record in entities:
		if record.persistent_id == persistent_id:
			return record
	return null


func has_entity(persistent_id: StringName) -> bool:
	return get_entity(persistent_id) != null


func get_entity_count() -> int:
	return entities.size()


## Every record built from one definition. What a spawn service uses to put a
## region's authored population back.
func find_entities_of(definition_id: StringName) -> Array[EntityRecord]:
	var found: Array[EntityRecord] = []
	for record in entities:
		if record.definition_id == definition_id:
			found.append(record)
	return found


# --- Serialisation --------------------------------------------------------

## Plain-data form. Every value is engine-serialisable, so
## [method FileAccess.store_var] handles it with no custom encoder.
func to_dictionary() -> Dictionary:
	var records: Array = []
	for record in entities:
		records.append(record.to_dictionary())
	return {
		"framework_version": framework_version,
		"schema_version": schema_version,
		"saved_at": saved_at,
		"playtime": playtime,
		"profile": profile.duplicate(true),
		"services": services.duplicate(true),
		"entities": records,
	}


static func from_dictionary(data: Dictionary) -> SaveGame:
	var save := SaveGame.new()
	save.framework_version = str(data.get("framework_version", ""))
	save.schema_version = int(data.get("schema_version", 0))
	save.saved_at = int(data.get("saved_at", 0))
	save.playtime = float(data.get("playtime", 0.0))
	save.profile = (data.get("profile", {}) as Dictionary).duplicate(true)
	save.services = (data.get("services", {}) as Dictionary).duplicate(true)
	for entry in data.get("entities", []):
		save.add_entity(EntityRecord.from_dictionary(entry))
	return save


## Whether this save is newer than the running build understands.
##
## Worth its own method because the failure is asymmetric: loading an old save
## is a migration, and loading a *future* one is a refusal. A player who
## downgraded should be told, not silently given a broken world.
func is_from_the_future() -> bool:
	return schema_version > FrameworkVersion.SAVE_SCHEMA


func needs_migration() -> bool:
	return schema_version < FrameworkVersion.SAVE_SCHEMA


func _to_string() -> String:
	return "SaveGame(schema %d, %d entities, %d service(s))" % [
		schema_version, entities.size(), services.size()
	]
