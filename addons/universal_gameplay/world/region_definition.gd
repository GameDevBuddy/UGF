class_name RegionDefinition
extends FrameworkDefinition
## A named piece of the world: a district, an island, a floor, a zone.
##
## [b]Regions exist so that work can be skipped.[/b] The M14 exit gate is
## "region population scales without global per-frame scans", and a region is
## the unit that makes skipping possible: population is counted per region,
## budgets are enforced per region, and a dormant region costs nothing at all.
## Without them every population question is a question about the whole world,
## which is the shape that stops scaling somewhere around the second district.
##
## Geometry is a sphere by default and optional entirely. A project with its
## own streaming volumes calls [method WorldStateService.set_entity_region]
## itself and never gives a region a position (rule 24).

## Where the region is centred, when it has geometry.
@export var centre: Vector3 = Vector3.ZERO

## Radius in metres. Zero means the region has no geometry: membership is
## whatever a project says it is.
@export_range(0.0, 100000.0, 1.0, "or_greater") var radius: float = 0.0

@export_group("Population")
## Caps per category. Categories are semantic ids a project chooses:
## [code]population.civilian[/code], [code]population.traffic[/code]. Parallel
## arrays because Godot exports those and not typed dictionaries.
@export var budget_categories: Array[StringName] = []

@export var budget_limits: Array[int] = []

## Cap across every category. Zero is no overall cap, only per-category ones.
@export_range(0, 10000) var total_budget: int = 0

@export_group("Activation")
## Whether the region starts active. A dormant region is not simulated and is
## not spawned into, which is the whole point of having regions.
@export var starts_active: bool = true

## Distance from an observer within which the region wakes, when a project
## drives activation by distance. Zero leaves activation entirely explicit.
@export_range(0.0, 100000.0, 1.0, "or_greater") var activation_distance: float = 0.0

@export_group("Vocabulary")
## What kind of place this is: [code]region.urban[/code],
## [code]region.wilderness[/code]. What a spawn definition matches on, so one
## definition populates every city rather than one per city (rule 11).
@export var region_tags: Array[StringName] = []


func has_geometry() -> bool:
	return radius > 0.0


func contains_point(point: Vector3) -> bool:
	if not has_geometry():
		return false
	return centre.distance_squared_to(point) <= radius * radius


## Distance from [param point] to the region's edge, zero inside it. What a
## project driving activation by distance compares against.
func distance_to(point: Vector3) -> float:
	if not has_geometry():
		return 0.0
	return maxf(0.0, centre.distance_to(point) - radius)


## The cap for one category, or -1 when uncapped. Minus one rather than zero,
## because zero is a real and useful budget: "no traffic here".
func get_budget(category: StringName) -> int:
	var index := budget_categories.find(category)
	if index < 0 or index >= budget_limits.size():
		return -1
	return budget_limits[index]


func has_budget_for(category: StringName) -> bool:
	return get_budget(category) >= 0


func get_budgeted_categories() -> Array[StringName]:
	var found: Array[StringName] = []
	var count := mini(budget_categories.size(), budget_limits.size())
	for index in count:
		found.append(budget_categories[index])
	return found


func has_region_tag(tag: StringName) -> bool:
	return region_tags.has(tag)


func has_all_region_tags(required: Array[StringName]) -> bool:
	for tag in required:
		if not region_tags.has(tag):
			return false
	return true


func validate() -> ValidationResult:
	var result := super()
	if budget_categories.size() != budget_limits.size():
		result.add_error(
			&"region.mismatched_budgets",
			(
				"%s names %d budget categories and %d limits; the extras on one "
				+ "side are never enforced."
			) % [get_debug_name(), budget_categories.size(), budget_limits.size()],
			resource_path,
			"budget_limits"
		)
	if activation_distance > 0.0 and not has_geometry():
		result.add_warning(
			&"region.distance_without_geometry",
			(
				"%s activates by distance but has no radius, so the distance is "
				+ "measured to a point rather than to the region."
			) % get_debug_name(),
			resource_path,
			"activation_distance"
		)
	var total := 0
	for limit in budget_limits:
		total += maxi(0, limit)
	if total_budget > 0 and total > 0 and total_budget > total:
		result.add_info(
			&"region.slack_total_budget",
			(
				"%s allows %d in total but only %d across its categories, so the "
				+ "total is never the binding limit."
			) % [get_debug_name(), total_budget, total],
			resource_path,
			"total_budget"
		)
	return result
