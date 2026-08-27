class_name WorldStateService
extends FrameworkService
## Which regions exist, which are awake, and who is in them.
##
## [b]This is the registry the M14 exit gate turns on.[/b] "Region population
## scales without global per-frame scans" is not a property you can add later
## by optimising: it is a property of where the counts live. Here, population
## is a number the service already knows, maintained when an entity enters or
## leaves a region and at no other time. Asking "how many civilians are in the
## docks" is a dictionary lookup, not a walk of the world (rule 25 of the
## plan's performance rules).
##
## [b]It holds no flags.[/b] [NarrativeStateService] already owns flags,
## variables and counters, and a second store of them would be the same idea
## twice (rule 23). A region flag is
## [code]narrative.set_flag(&"region.docks.cleared")[/code] — a semantic id in
## the store that already exists, with no new code and nothing to keep in sync.
## What is genuinely not narrative is what lives here: who is where, and how
## many of them there are.

## Emitted when a region wakes or sleeps. What a spawner and a streaming layer
## both listen to.
signal region_activated(region_id: StringName)
signal region_deactivated(region_id: StringName)

## Emitted when an entity's region changes. [param from] is blank on entry and
## [param to] is blank on exit.
signal entity_moved(entity: Node, from: StringName, to: StringName)

## Emitted when a region's population in some category changes.
signal population_changed(region_id: StringName, category: StringName, count: int)

## Regions known to the world. Registered rather than discovered, because
## discovery is the scan this service exists to avoid.
var _regions: Dictionary[StringName, RegionDefinition] = {}

## Region id to active flag.
var _active: Dictionary[StringName, bool] = {}

## Region id to {category: {instance_id: entity}}. Nested rather than flat so
## a count is a size() and never a filter.
var _population: Dictionary[StringName, Dictionary] = {}

## Instance id to [region, category], so removing an entity does not need a
## search either.
var _placements: Dictionary[int, Array] = {}


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_WORLD_STATE


func service_stopped() -> void:
	clear()


# --- Regions --------------------------------------------------------------

func register_region(definition: RegionDefinition) -> FrameworkResult:
	if definition == null or definition.id == &"":
		return FrameworkResult.fail(
			&"world.no_region_id", "A region must have an id to be registered."
		)
	if _regions.has(definition.id):
		return FrameworkResult.fail(
			&"world.duplicate_region",
			"A region called '%s' is already registered." % definition.id
		)
	_regions[definition.id] = definition
	_population[definition.id] = {}
	_active[definition.id] = definition.starts_active
	return FrameworkResult.ok(definition)


func unregister_region(region_id: StringName) -> bool:
	if not _regions.has(region_id):
		return false
	for entity in get_entities_in(region_id):
		remove_entity(entity)
	_regions.erase(region_id)
	_population.erase(region_id)
	_active.erase(region_id)
	return true


func has_region(region_id: StringName) -> bool:
	return _regions.has(region_id)


func get_region(region_id: StringName) -> RegionDefinition:
	return _regions.get(region_id)


func get_region_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_regions.keys())
	return ids


func get_region_count() -> int:
	return _regions.size()


## Every region carrying [param tag]. What a spawn definition matches on, so
## one definition populates every city.
func find_regions_with_tag(tag: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for region_id in _regions:
		if _regions[region_id].has_region_tag(tag):
			found.append(region_id)
	return found


# --- Activation -----------------------------------------------------------

func is_active(region_id: StringName) -> bool:
	return _active.get(region_id, false)


func get_active_regions() -> Array[StringName]:
	var found: Array[StringName] = []
	for region_id in _active:
		if _active[region_id]:
			found.append(region_id)
	return found


func get_active_region_count() -> int:
	return get_active_regions().size()


func set_active(region_id: StringName, active: bool) -> bool:
	if not _regions.has(region_id) or _active.get(region_id, false) == active:
		return false
	_active[region_id] = active
	if active:
		region_activated.emit(region_id)
	else:
		region_deactivated.emit(region_id)
	return true


## Wakes regions within their activation distance of [param observer] and
## sleeps the rest.
##
## [b]This walks every region, and that is fine.[/b] The scan the exit gate
## forbids is over the world's *entities*, which grow without bound; regions
## are a handful of authored things and a project calls this when an observer
## has moved a meaningful distance, not every frame. Returns how many regions
## changed state, which is what a test asserts on and a debug panel shows.
func refresh_activation(observer: Vector3) -> int:
	var changed := 0
	for region_id in _regions:
		var definition := _regions[region_id]
		if definition.activation_distance <= 0.0:
			continue
		var wanted := definition.distance_to(observer) <= definition.activation_distance
		if set_active(region_id, wanted):
			changed += 1
	return changed


# --- Placement ------------------------------------------------------------
#
# Every count here is maintained on entry and exit and never recomputed. That
# is the whole design: a population question is a dictionary lookup, and no
# amount of world means more work per frame.

## Puts an entity in a region under a category. Moving between regions is the
## same call: the previous placement is lifted first.
func set_entity_region(
	entity: Node, region_id: StringName, category: StringName = &""
) -> FrameworkResult:
	if entity == null:
		return FrameworkResult.fail(&"world.no_entity", "There is no entity to place.")
	if region_id != &"" and not _regions.has(region_id):
		return FrameworkResult.fail(
			&"world.no_such_region", "No region called '%s' is registered." % region_id
		)

	var key := entity.get_instance_id()
	var previous := get_entity_region(entity)
	var previous_category := get_entity_category(entity)
	if previous == region_id and previous_category == category:
		return FrameworkResult.ok(region_id)

	if previous != &"":
		_take_out(key, previous, previous_category)
	if region_id == &"":
		_placements.erase(key)
		entity_moved.emit(entity, previous, &"")
		return FrameworkResult.ok(&"")

	_put_in(key, entity, region_id, category)
	_placements[key] = [region_id, category]
	entity_moved.emit(entity, previous, region_id)
	return FrameworkResult.ok(region_id)


## Takes an entity out of whatever region it was in. What a despawn calls.
func remove_entity(entity: Node) -> bool:
	if entity == null or not _placements.has(entity.get_instance_id()):
		return false
	set_entity_region(entity, &"")
	return true


func get_entity_region(entity: Node) -> StringName:
	if entity == null:
		return &""
	var placement: Array = _placements.get(entity.get_instance_id(), [])
	return placement[0] if placement.size() == 2 else &""


func get_entity_category(entity: Node) -> StringName:
	if entity == null:
		return &""
	var placement: Array = _placements.get(entity.get_instance_id(), [])
	return placement[1] if placement.size() == 2 else &""


func is_placed(entity: Node) -> bool:
	return entity != null and _placements.has(entity.get_instance_id())


## Which region a point falls in, or blank. Only regions with geometry are
## considered, and the first match wins — overlapping regions are a project's
## decision to disambiguate, not the framework's to guess at.
func find_region_at(point: Vector3) -> StringName:
	for region_id in _regions:
		if _regions[region_id].contains_point(point):
			return region_id
	return &""


# --- Population -----------------------------------------------------------

func get_population(region_id: StringName, category: StringName = &"") -> int:
	var region: Dictionary = _population.get(region_id, {})
	if category != &"":
		return (region.get(category, {}) as Dictionary).size()
	var total := 0
	for key in region:
		total += (region[key] as Dictionary).size()
	return total


func get_total_population() -> int:
	var total := 0
	for region_id in _population:
		total += get_population(region_id)
	return total


func get_categories_in(region_id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign((_population.get(region_id, {}) as Dictionary).keys())
	return found


## The live entities in a region, optionally of one category.
##
## Returns a fresh array of only what is in that region, so a caller iterating
## it is doing work proportional to the region rather than to the world. Dead
## references are dropped on the way out rather than being hunted for on a
## timer.
func get_entities_in(region_id: StringName, category: StringName = &"") -> Array[Node]:
	var found: Array[Node] = []
	var region: Dictionary = _population.get(region_id, {})
	for key in region:
		if category != &"" and key != category:
			continue
		for instance_id in (region[key] as Dictionary):
			# Read as Variant, not as Node. Assigning a freed instance to a
			# typed Node local throws "Trying to assign invalid previously
			# freed instance" *before* is_instance_valid() can be reached, so
			# the guard has to come first and the type second.
			var candidate: Variant = (region[key] as Dictionary)[instance_id]
			if candidate != null and is_instance_valid(candidate):
				found.append(candidate as Node)
	return found


## Whether a region has room for one more of [param category].
##
## Both caps apply: the category's own and the region's total. An uncapped
## category in a region with a total is still bounded by the total, which is
## what stops "unlimited civilians" meaning unlimited anything.
func has_room(region_id: StringName, category: StringName) -> bool:
	var definition := get_region(region_id)
	if definition == null:
		return false
	if definition.total_budget > 0 and get_population(region_id) >= definition.total_budget:
		return false
	var limit := definition.get_budget(category)
	if limit < 0:
		return true
	return get_population(region_id, category) < limit


## How many more of [param category] would fit, or -1 for unbounded.
func get_headroom(region_id: StringName, category: StringName) -> int:
	var definition := get_region(region_id)
	if definition == null:
		return 0
	var limit := definition.get_budget(category)
	var by_category := -1 if limit < 0 else maxi(0, limit - get_population(region_id, category))
	var by_total := -1
	if definition.total_budget > 0:
		by_total = maxi(0, definition.total_budget - get_population(region_id))
	if by_category < 0:
		return by_total
	if by_total < 0:
		return by_category
	return mini(by_category, by_total)


## Drops references to entities that have been freed.
##
## Called when something is known to have been destroyed outside the service's
## sight, not on a timer. A registry that sweeps itself every frame is the scan
## this service exists to avoid, wearing a different hat.
func prune(region_id: StringName = &"") -> int:
	var dropped := 0
	var region_ids: Array = [region_id] if region_id != &"" else _population.keys()
	for id in region_ids:
		var region: Dictionary = _population.get(id, {})
		for category in region.keys():
			var bucket: Dictionary = region[category]
			for instance_id in bucket.keys():
				# Variant, for the same reason get_entities_in() reads one: a
				# freed instance cannot be assigned to a typed local at all.
				var candidate: Variant = bucket[instance_id]
				if candidate == null or not is_instance_valid(candidate):
					bucket.erase(instance_id)
					_placements.erase(instance_id)
					dropped += 1
			if bucket.is_empty():
				region.erase(category)
			else:
				population_changed.emit(id, category, bucket.size())
	return dropped


func clear() -> void:
	_regions.clear()
	_active.clear()
	_population.clear()
	_placements.clear()


# --- Persistence ----------------------------------------------------------
#
# Which regions are awake, and nothing else. Populations are not saved: rule
# 23 of the plan's world layer says ambient population is regenerated from
# definitions rather than persisted, and authored entities save themselves
# through their own components.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var saved: Dictionary = {}
	for region_id in _active:
		saved[String(region_id)] = _active[region_id]
	return {"active_regions": saved}


func restore_state(data: Dictionary) -> void:
	for key in data.get("active_regions", {}):
		var region_id := StringName(key)
		if _regions.has(region_id):
			set_active(region_id, bool(data["active_regions"][key]))


# --- Internals ------------------------------------------------------------

func _put_in(key: int, entity: Node, region_id: StringName, category: StringName) -> void:
	var region: Dictionary = _population[region_id]
	if not region.has(category):
		region[category] = {}
	(region[category] as Dictionary)[key] = entity
	population_changed.emit(region_id, category, (region[category] as Dictionary).size())


func _take_out(key: int, region_id: StringName, category: StringName) -> void:
	var region: Dictionary = _population.get(region_id, {})
	if not region.has(category):
		return
	var bucket: Dictionary = region[category]
	bucket.erase(key)
	population_changed.emit(region_id, category, bucket.size())
	if bucket.is_empty():
		region.erase(category)
