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
		# A CharacterDefinition composes a profile from a dozen modules as
		# typed @export properties, and CharacterController holds three sibling
		# components. All of it works with any of them absent, but all of it is
		# a compile-time reference, so all of it belongs here.
		#
		# Worth saying plainly: that a definition in one module names types
		# from twelve others is itself worth questioning, and a seam would be
		# the better answer than a longer list. That is a redesign of Character
		# rather than a manifest fix, and it is not what this change is. What
		# this change buys is that the relationship is written down and any new
		# one has to be.
		_manifest.optional = [
			GameplayNames.MODULE_INPUT,
			GameplayNames.MODULE_CAMERA,
			GameplayNames.MODULE_ANIMATION,
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_DIALOGUE,
			GameplayNames.MODULE_FACTIONS,
			GameplayNames.MODULE_COMMERCE,
			GameplayNames.MODULE_LOOT,
			GameplayNames.MODULE_SURVIVAL,
		]
		_manifest.parse_requires = [
			GameplayNames.MODULE_AI,
			GameplayNames.MODULE_ANIMATION,
			GameplayNames.MODULE_CAMERA,
			GameplayNames.MODULE_COMBAT,
			GameplayNames.MODULE_COMMERCE,
			GameplayNames.MODULE_DIALOGUE,
			GameplayNames.MODULE_ENTITY,
			GameplayNames.MODULE_EQUIPMENT,
			GameplayNames.MODULE_FACTIONS,
			GameplayNames.MODULE_HEALTH,
			GameplayNames.MODULE_INPUT,
			GameplayNames.MODULE_INTERACTION,
			GameplayNames.MODULE_INVENTORY,
			GameplayNames.MODULE_LOCOMOTION,
			GameplayNames.MODULE_LOOT,
			GameplayNames.MODULE_STATS,
			GameplayNames.MODULE_SURVIVAL,
		]
	return _manifest
