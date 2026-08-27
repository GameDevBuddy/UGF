class_name SpawnDefinition
extends FrameworkDefinition
## A pool of things that can appear, and the rules about when.
##
## Adding a kind of ambient population to a game creates a [code].tres[/code]
## and no GDScript (rule 15). What can appear, how likely each is, how many at
## once, where, how often and against which budget are all data.
##
## [b]It names regions by tag, not by id.[/b] One "city pedestrians"
## definition populates every region tagged [code]region.urban[/code], so
## adding a district is authoring a region rather than editing every spawner
## (rule 11, rule 32).

## What can come out.
@export var entries: Array[SpawnEntry] = []

@export_group("Placement")
## Region tags this pool applies to. Empty applies to every region, which is
## right for something universal and usually a mistake.
@export var region_tags: Array[StringName] = []

## Which budget these count against unless an entry overrides it.
@export var category: StringName = &"population.ambient"

## How many to keep alive per region, as a fraction of the region's budget for
## this category. One fills the budget; a half leaves headroom for a project's
## own authored entities.
@export_range(0.0, 1.0, 0.01) var density: float = 1.0

## Hard ceiling per region regardless of density and budget. Zero defers to
## the budget entirely.
@export_range(0, 1000) var maximum_per_region: int = 0

@export_group("Timing")
## Seconds between attempts to top a region up. Zero tops up on every service
## tick, which is only right for something very cheap.
@export_range(0.0, 3600.0, 0.1, "or_greater") var interval: float = 5.0

## How many to place per attempt. Keeping this small is what turns a
## repopulating district into a trickle rather than a pop-in wall.
@export_range(1, 100) var batch_size: int = 2

@export_group("Despawn")
## When what this places may be removed again. Null never despawns, which is
## right for an authored encounter and wrong for traffic.
@export var despawn: DespawnPolicy

@export_group("Availability")
## Narrative flags that must be raised before this pool is used at all.
@export var required_flags: Array[StringName] = []

## Whether the pool is used. What a debug toggle and a difficulty setting move.
@export var enabled: bool = true


func has_entries() -> bool:
	return not entries.is_empty()


func applies_to_every_region() -> bool:
	return region_tags.is_empty()


## Whether this pool populates [param region].
func applies_to(region: RegionDefinition) -> bool:
	if not enabled or region == null:
		return false
	if applies_to_every_region():
		return true
	for tag in region_tags:
		if region.has_region_tag(tag):
			return true
	return false


## Whether the story has unlocked this pool.
func is_unlocked(narrative: NarrativeStateService) -> bool:
	if required_flags.is_empty():
		return true
	return narrative != null and narrative.has_all_flags(required_flags)


## How many this pool wants alive in [param region] right now.
##
## The density is applied to the region's own budget, so one definition
## produces a busy city centre and a quiet suburb from the same numbers — the
## difference is authored on the region, where it belongs.
func get_target_population(region: RegionDefinition) -> int:
	if region == null:
		return 0
	var budget := region.get_budget(category)
	var target := 0
	if budget >= 0:
		target = int(floor(float(budget) * density))
	elif region.total_budget > 0:
		target = int(floor(float(region.total_budget) * density))
	elif maximum_per_region > 0:
		target = maximum_per_region
	if maximum_per_region > 0:
		target = mini(target, maximum_per_region)
	return maxi(0, target)


## The entries usable in [param region] right now.
func get_available_entries(
	region: RegionDefinition, narrative: NarrativeStateService
) -> Array[SpawnEntry]:
	var found: Array[SpawnEntry] = []
	for entry in entries:
		if entry != null and entry.is_available(region, narrative):
			found.append(entry)
	return found


## Picks one entry by weight from those available.
##
## The generator is injected for the same reason loot's is: a test gets the
## same choice twice, and a networked game can share the stream rather than
## every client inventing its own crowd.
func pick(
	region: RegionDefinition, narrative: NarrativeStateService, rng: RandomNumberGenerator
) -> SpawnEntry:
	var available := get_available_entries(region, narrative)
	var total := 0.0
	for entry in available:
		total += maxf(0.0, entry.weight)
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for entry in available:
		roll -= maxf(0.0, entry.weight)
		if roll <= 0.0:
			return entry
	return available.back()


func validate() -> ValidationResult:
	var result := super()
	if not has_entries():
		result.add_error(
			&"spawn.no_entries",
			"%s has nothing to place." % get_debug_name(),
			resource_path,
			"entries"
		)
	if category == &"":
		result.add_warning(
			&"spawn.no_category",
			(
				"%s counts against no budget category, so nothing limits how "
				+ "many it places."
			) % get_debug_name(),
			resource_path,
			"category"
		)
	if applies_to_every_region():
		result.add_info(
			&"spawn.every_region",
			(
				"%s names no region tags, so it populates every region in the "
				+ "world including ones added later."
			) % get_debug_name(),
			resource_path,
			"region_tags"
		)
	if despawn == null:
		result.add_info(
			&"spawn.never_despawns",
			(
				"%s has no despawn policy, so what it places stays forever. "
				+ "Right for an authored encounter, wrong for ambient traffic."
			) % get_debug_name(),
			resource_path,
			"despawn"
		)
	else:
		result.merge(despawn.validate())
	for entry in entries:
		if entry == null:
			result.add_warning(
				&"spawn.empty_entry_slot",
				"%s has an empty entry slot." % get_debug_name(),
				resource_path,
				"entries"
			)
			continue
		result.merge(entry.validate())
	return result
