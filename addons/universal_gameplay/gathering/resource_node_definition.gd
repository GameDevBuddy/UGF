class_name ResourceNodeDefinition
extends FrameworkDefinition
## What a tree, an ore vein or a berry bush gives up.
##
## The first leg of the M12 exit gate. Yields come from a [LootTableDefinition]
## rather than a list of its own, because "a weighted table of items with
## guaranteed entries" is exactly what M11 already ships and a second one would
## be the same code twice (rule 23).

## What it yields, by id. Resolved through the definition registry, so a node
## and its drops do not have to load each other (rule 32).
@export var loot_table_id: StringName = &""

@export_group("Harvesting")
## Seconds of work per harvest. Zero is instant.
@export_range(0.0, 600.0, 0.1, "or_greater") var harvest_time: float = 1.0

## Tag a tool must carry to work here: [code]tool.axe[/code]. Blank needs no
## tool, which is what a berry bush is.
@export var required_tool_tag: StringName = &""

## Durability taken off the tool per harvest.
@export_range(0.0, 1000.0, 0.1) var tool_wear: float = 1.0

## How many times it can be harvested before it is spent. Zero is unlimited.
@export_range(0, 999) var charges: int = 1

@export_group("Respawn")
## Seconds before a spent node comes back. Zero never does.
@export_range(0.0, 86400.0, 1.0, "or_greater") var respawn_time: float = 0.0

@export_group("Vocabulary")
## What kind of node this is, for presentation and for an objective matching
## on it: [code]resource.wood[/code].
@export var resource_tags: Array[StringName] = []


func needs_tool() -> bool:
	return required_tool_tag != &""


func is_unlimited() -> bool:
	return charges <= 0


func respawns() -> bool:
	return respawn_time > 0.0


func validate() -> ValidationResult:
	var result := super()
	if loot_table_id == &"":
		result.add_error(
			&"node.no_yield",
			"%s yields nothing when harvested." % get_debug_name(),
			resource_path,
			"loot_table_id"
		)
	if not needs_tool() and tool_wear > 0.0:
		result.add_info(
			&"node.wear_without_tool",
			(
				"%s needs no tool, so its wear only applies to a tool a player "
				+ "happens to be holding."
			) % get_debug_name(),
			resource_path,
			"tool_wear"
		)
	if is_unlimited() and respawns():
		result.add_warning(
			&"node.unlimited_respawn",
			"%s never runs out, so its respawn time is never waited out." % get_debug_name(),
			resource_path,
			"respawn_time"
		)
	return result
