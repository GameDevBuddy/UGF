class_name EntityRecord
extends RefCounted
## One entity's persisted state.
##
## A record holds stable ids and component state -- never a serialised scene
## graph (rule 22). Loading rebuilds the entity from its definition's scene and
## reapplies this, so a level can be restructured, a scene re-authored and a
## component added without invalidating saves already on disk.

## Identity of the saved instance.
var persistent_id: StringName = &""
## Definition to rebuild it from. Blank for an entity authored without one.
var definition_id: StringName = &""
## Scene or region the entity belongs to, so a loader knows where to put it.
var scene_key: String = ""

var transform: Transform3D = Transform3D.IDENTITY
## False for entities with no spatial presence, so loading does not force an
## identity transform onto something that never had one.
var has_transform: bool = false

## Component state, keyed by [method FrameworkComponent.get_state_key].
var component_state: Dictionary = {}

## Save schema the record was written against, so a record moved between saves
## still describes itself.
var schema_version: int = FrameworkVersion.SAVE_SCHEMA


func get_component_state(key: StringName) -> Dictionary:
	return component_state.get(key, {})


func has_component_state(key: StringName) -> bool:
	return component_state.has(key)


## Plain-data form for a save file. Every value is engine-serialisable, so
## [method FileAccess.store_var] handles it without a custom encoder.
func to_dictionary() -> Dictionary:
	var data: Dictionary = {
		"schema_version": schema_version,
		"persistent_id": persistent_id,
		"definition_id": definition_id,
		"component_state": component_state.duplicate(true),
	}
	if not scene_key.is_empty():
		data["scene_key"] = scene_key
	if has_transform:
		data["transform"] = transform
	return data


static func from_dictionary(data: Dictionary) -> EntityRecord:
	var record := EntityRecord.new()
	record.schema_version = int(data.get("schema_version", FrameworkVersion.SAVE_SCHEMA))
	record.persistent_id = StringName(data.get("persistent_id", ""))
	record.definition_id = StringName(data.get("definition_id", ""))
	record.scene_key = str(data.get("scene_key", ""))
	record.component_state = data.get("component_state", {}).duplicate(true)
	if data.has("transform"):
		record.transform = data["transform"]
		record.has_transform = true
	return record


func _to_string() -> String:
	return (
		"EntityRecord(%s from %s, %d component(s))"
		% [persistent_id, definition_id if definition_id != &"" else "<no definition>",
			component_state.size()]
	)
