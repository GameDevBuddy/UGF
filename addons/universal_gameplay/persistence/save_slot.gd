class_name SaveSlot
extends RefCounted
## What a load menu shows without reading the whole save.
##
## [b]Separate from [SaveGame] on purpose.[/b] A slot list has to render before
## anything is loaded, and deserialising six full worlds to draw six rows is
## how a save menu comes to take four seconds. Everything here is written
## alongside the save and read on its own.

## Which slot: [code]"slot_1"[/code], [code]"autosave"[/code],
## [code]"quicksave"[/code]. A string rather than an int, because "autosave" is
## not slot minus one.
var id: StringName = &""

## What the player called it, or what the project generated.
var label: String = ""

var saved_at: int = 0
var playtime: float = 0.0
var schema_version: int = FrameworkVersion.SAVE_SCHEMA
var framework_version: String = FrameworkVersion.get_version_string()

## Whatever the project wants on the row: location name, chapter, level,
## screenshot path. Free-form because none of it is the framework's business.
var summary: Dictionary = {}


static func create(
	p_id: StringName, p_label: String = "", p_summary: Dictionary = {}
) -> SaveSlot:
	var slot := SaveSlot.new()
	slot.id = p_id
	slot.label = p_label if not p_label.is_empty() else String(p_id)
	slot.summary = p_summary.duplicate(true)
	return slot


## Builds a slot from a save, so writing one never means describing it twice.
static func describe(p_id: StringName, save: SaveGame, p_label: String = "") -> SaveSlot:
	var slot := create(p_id, p_label)
	slot.saved_at = save.saved_at
	slot.playtime = save.playtime
	slot.schema_version = save.schema_version
	slot.framework_version = save.framework_version
	return slot


func is_autosave() -> bool:
	return String(id).begins_with("autosave")


func needs_migration() -> bool:
	return schema_version < FrameworkVersion.SAVE_SCHEMA


func is_from_the_future() -> bool:
	return schema_version > FrameworkVersion.SAVE_SCHEMA


## Whether this slot can be loaded by the running build at all. A load menu
## greys out the rest rather than letting the player click and crash.
func is_loadable() -> bool:
	return not is_from_the_future()


func to_dictionary() -> Dictionary:
	return {
		"id": String(id),
		"label": label,
		"saved_at": saved_at,
		"playtime": playtime,
		"schema_version": schema_version,
		"framework_version": framework_version,
		"summary": summary.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> SaveSlot:
	var slot := SaveSlot.new()
	slot.id = StringName(data.get("id", ""))
	slot.label = str(data.get("label", ""))
	slot.saved_at = int(data.get("saved_at", 0))
	slot.playtime = float(data.get("playtime", 0.0))
	slot.schema_version = int(data.get("schema_version", 0))
	slot.framework_version = str(data.get("framework_version", ""))
	slot.summary = (data.get("summary", {}) as Dictionary).duplicate(true)
	return slot


func _to_string() -> String:
	return "SaveSlot(%s: %s, schema %d)" % [id, label, schema_version]
