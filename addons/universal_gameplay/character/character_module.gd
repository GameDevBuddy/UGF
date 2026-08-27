extends FrameworkModule
## The Character module.
##
## Provides the character definition type, the player-input driver and the
## assembled character scene. It registers no services: a character is an
## entity, and everything about it is entity-local (rule 4).
##
## Requires Entity and Locomotion, because a character definition configures a
## mover and the controller drives one. Input, Camera and Animation are
## optional -- a headless server running NPCs needs none of the three, and a
## character built without them still walks, still saves and still restores
## (rule 10, rule 31).
##
## No class_name: modules are instantiated by the project that installs them,
## not referenced globally.

const MODULE_ID: StringName = &"module.character"

## The assembled character scene, so a project can instantiate one without
## knowing where the addon lives on disk.
const CHARACTER_SCENE: String = (
	"res://addons/universal_gameplay/character/character.tscn"
)

var _manifest: ModuleManifest = null


func get_manifest() -> ModuleManifest:
	if _manifest == null:
		_manifest = ModuleManifest.new()
		_manifest.id = MODULE_ID
		_manifest.display_name = "Character"
		_manifest.version = FrameworkVersion.get_version_string()
		_manifest.description = (
			"Character definitions, the player-input driver and the shared "
			+ "character scene every human-shaped entity is built from."
		)
		_manifest.requires = [
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_LOCOMOTION,
		]
		_manifest.optional = [
			GameplayNames.MODULE_INPUT,
			GameplayNames.MODULE_CAMERA,
			GameplayNames.MODULE_ANIMATION,
		]
	return _manifest
