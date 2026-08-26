class_name EntityDefinition
extends FrameworkDefinition
## A definition that can be instantiated into the world.
##
## Not every definition is an entity. A mission, a recipe or a faction is
## content with no scene, so [member scene] lives here rather than on
## [FrameworkDefinition] -- otherwise every definition in the project would
## carry a field most of them can never use, and validation could not tell a
## missing scene from a scene that was never meant to exist.
##
## Character, vehicle and world-object definitions extend this.

## The scene instantiated for this entity. The load path is definition id ->
## registry -> scene -> instantiate -> bind -> apply saved state, which is what
## lets a save hold ids and state instead of a serialised scene graph (rule 22).
@export var scene: PackedScene

## Prefix for generated persistent ids, so a runtime id reads as
## [code]npc.guard.1837462.4471[/code] rather than an opaque number.
@export var id_prefix: String = ""


func validate() -> ValidationResult:
	var result := super()
	if scene == null:
		result.add_error(
			&"entity_definition.missing_scene",
			"%s has no scene, so it cannot be spawned." % get_debug_name(),
			resource_path,
			"scene"
		)
	return result


## Prefix to use when generating a persistent id for an instance of this
## definition. Falls back to the definition id, which is almost always what
## you want.
func get_id_prefix() -> String:
	if not id_prefix.is_empty():
		return id_prefix
	return str(id) if id != &"" else "entity"
