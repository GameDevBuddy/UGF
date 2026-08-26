class_name PersistentIdentity
extends FrameworkComponent
## Gives an entity a save identity that outlives its scene.
##
## Persistence keys off this id, not off a node path (rule 32). A path is an
## implementation detail: move the entity into a different parent, rename a
## node, restructure a level, and every path-keyed save breaks. The id does not
## care where the entity lives.
##
## Entities authored into a scene should have their id set in the inspector, so
## it is stable across every save the level ever produces. Entities spawned at
## runtime get a generated one.
##
## Network ids are a separate concern and deliberately not this
## (Implementation Plan 27).

## Authored id. Leave blank on runtime-spawned entities and one is generated.
@export var persistent_id: StringName = &""

## Generate an id on first use when none was authored. Turn this off for an
## entity that must never be saved.
@export var generate_if_missing: bool = true

## Prefix for a generated id. Blank falls back to the entity definition's
## prefix, then to "entity".
@export var id_prefix: String = ""

## Whether the save system should persist this entity at all. Ambient
## population -- traffic, crowd NPCs -- is regenerated from definitions rather
## than saved individually (Implementation Plan 23).
@export var saveable: bool = true

## Counter feeding generated ids. Static so two entities created in the same
## microsecond cannot collide.
static var _sequence: int = 0


## The entity's id, generating one on first call if needed.
##
## Generation is lazy rather than done in [method Node._ready] for the same
## reason Core wires itself lazily: _ready() does not run until the first
## process frame, and an entity spawned and serialised inside one frame would
## otherwise have no id.
func get_persistent_id() -> StringName:
	if persistent_id == &"" and generate_if_missing:
		persistent_id = generate_id(_resolve_prefix())
	return persistent_id


func set_persistent_id(value: StringName) -> void:
	persistent_id = value


func has_persistent_id() -> bool:
	return persistent_id != &""


func is_saveable() -> bool:
	return saveable


func _resolve_prefix() -> String:
	if not id_prefix.is_empty():
		return id_prefix
	var definition := get_definition()
	if definition is EntityDefinition:
		return (definition as EntityDefinition).get_id_prefix()
	if definition != null and definition.id != &"":
		return str(definition.id)
	return "entity"


## Builds an id unique within a run: prefix, microsecond clock, and a counter
## that breaks ties inside the same microsecond.
static func generate_id(prefix: String = "entity") -> StringName:
	_sequence += 1
	return StringName("%s.%d.%d" % [prefix, Time.get_ticks_usec(), _sequence])
