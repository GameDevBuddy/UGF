class_name CharacterDefinition
extends EntityDefinition
## What a character is: a scene plus the profiles that configure it.
##
## Every human-shaped entity in the framework is one of these. A civilian, a
## guard, a vendor, a companion and the player are the same definition type
## with different profiles and different tags -- not five classes (rule 5,
## rule 13). Adding an ordinary NPC to a game creates a [code].tres[/code] and
## no GDScript at all (rule 15).
##
## [b]This definition is incomplete on purpose.[/b] Implementation Plan 6 lists
## stats, loadout, AI and faction here too, and they are absent because the
## modules that own those types do not exist yet. Declaring
## [code]@export var faction: FactionDefinition[/code] before M10 would put a
## Faction type inside a definition every project must load, and make Character
## fail to parse in a build without Factions -- rules 1 and 10, broken to save
## a later edit. Each milestone adds its own field, which is a MINOR version
## bump and leaves the save schema alone (Implementation Plan 43).

## How this character moves. Shared across every character that moves alike.
@export var movement: MovementProfile

## Attributes and depletable resources. Optional: an entity can be damageable
## with a flat maximum and no attributes at all.
@export var stats: StatsProfile

## Armour and resistances. Optional; absent means every hit lands in full.
@export var resistances: ResistanceProfile

## What this character can carry. Optional: an NPC that never holds anything
## needs no container.
@export var inventory: InventoryProfile

## Equipment slots and starting gear. Optional; absent means it wears nothing.
@export var loadout: LoadoutProfile

## How this character's rig is driven. Optional: an NPC with no visible mesh
## needs none.
@export var animation: AnimationProfile

## The view used when this character is the one being followed. Optional: most
## NPCs are never a camera target.
@export var camera: CameraProfile

## Input context pushed when a player takes control of this character. Blank
## uses the standard on-foot context.
@export var input_context: InputContext

## How this character fights unarmed, and where its attacks come from.
## Optional: a civilian that never throws a punch needs none.
@export var combat: CombatProfile

## How far this character can reach and how it finds what to reach for.
## Optional: a character that never uses anything needs none.
@export var interaction: InteractorProfile

## What can be done [i]to[/i] this character: talk, search, revive, rob. The
## other side of the same module, and the reason an NPC needs no Door script to
## be interactable.
@export var interactions: Array[InteractionDefinition] = []


func validate() -> ValidationResult:
	var result := super()
	if movement == null:
		result.add_warning(
			&"character_definition.no_movement_profile",
			(
				"%s has no movement profile, so it cannot move. Correct for a "
				+ "statue; probably not for a character."
			) % get_debug_name(),
			resource_path,
			"movement"
		)
	else:
		result.merge(movement.validate())
	if stats != null:
		result.merge(stats.validate())
	if resistances != null:
		result.merge(resistances.validate())
	if inventory != null:
		result.merge(inventory.validate())
	if loadout != null:
		result.merge(loadout.validate())
	if animation != null:
		result.merge(animation.validate())
	if camera != null:
		result.merge(camera.validate())
	if input_context != null:
		result.merge(input_context.validate())
	if combat != null:
		result.merge(combat.validate())
	if interaction != null:
		result.merge(interaction.validate())
	for offered in interactions:
		if offered != null:
			result.merge(offered.validate())
	return result


## Whether this character can be handed to a player.
##
## A character with no camera profile is not thereby unplayable -- a top-down
## game frames the world, not the character -- so this asks only about the
## input context, which is what possession actually needs.
func is_playable() -> bool:
	return input_context != null or movement != null
