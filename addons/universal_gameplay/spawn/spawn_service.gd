class_name SpawnService
extends FrameworkService
## Keeps the world populated, and does no work for the parts of it nobody is
## looking at.
##
## [b]This is the M14 exit gate.[/b] "Region population scales without global
## per-frame scans" is not something you optimise your way to later — it is a
## property of where the work is indexed. Three things make it true here and
## nothing else has to:
##
## [b]1. Nothing is discovered.[/b] Anchors are registered into per-region
## buckets and pools are registered against region tags. Nothing here searches
## a group or walks the tree looking for work — [code]test_world_scaling.gd[/code]
## asserts that directly against this file's source.
##
## [b]2. Nothing is counted.[/b] Populations live in [WorldStateService],
## maintained on entry and exit. Asking a region how full it is is a dictionary
## lookup regardless of how many entities exist.
##
## [b]3. Dormant regions cost nothing.[/b] A tick iterates the active regions
## and only those. Ten thousand entities across fifty sleeping districts are
## exactly as cheap as none.
##
## [method get_last_tick_cost] reports how many regions and entities the last
## tick actually examined, which is what the exit-gate test asserts on and what
## the plan's Spawn Debugger shows.

## Emitted after something is placed.
signal spawned(entity: Node, region_id: StringName, category: StringName)
## Emitted after something is removed.
signal despawned(entity: Node, region_id: StringName, reason: StringName)
## Emitted when a spawn was refused, with why. What the Spawn Debugger's
## "reasons for rejection" column shows.
signal spawn_refused(definition_id: StringName, region_id: StringName, reason: StringName)
## Emitted when an encounter is placed, with everyone in it.
signal encounter_spawned(encounter_id: StringName, members: Array[Node])

## Where population and regions live. Injected: a spawner with no world has
## nowhere to count and refuses rather than guessing.
var world: WorldStateService = null

## Optional narrative, gating pools and encounters by flag. Absent, anything
## with required flags is simply unavailable (rule 31).
var narrative: NarrativeStateService = null

## Where definitions are resolved from. Any object with
## [code]get_definition(id)[/code]; in practice the core.
var registry: Object = null

## Where spawned entities are parented. Null parents them to this service,
## which keeps them in the tree and out of the way.
var container: Node = null

## Whether spawning happens at all. What a debug toggle and a cutscene move.
var enabled: bool = true

var _pools: Array[SpawnDefinition] = []
## Region id to anchors in it. The bucketing that makes placement a lookup.
var _anchors: Dictionary[StringName, Array] = {}
## Pool id to region id to seconds until the next attempt.
var _timers: Dictionary[StringName, Dictionary] = {}
## Entity instance id to [spawned_at_seconds, policy, region, category].
var _tracked: Dictionary[int, Array] = {}
## Encounter id to seconds until it may run again.
var _encounter_cooldowns: Dictionary[StringName, float] = {}
var _elapsed: float = 0.0
var _rng: RandomNumberGenerator = null

## What the last tick actually looked at. The exit gate's evidence.
var _last_regions_examined: int = 0
var _last_entities_examined: int = 0


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_SPAWN


func configure(
	p_world: WorldStateService,
	p_registry: Object = null,
	p_narrative: NarrativeStateService = null,
	p_container: Node = null
) -> void:
	world = p_world
	registry = p_registry
	narrative = p_narrative
	container = p_container


func service_stopped() -> void:
	clear()


## Deterministic randomness for every choice this service makes. Injected so a
## test gets the same crowd twice and a networked game can share the stream
## rather than each client inventing its own city.
func get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


# --- Registration ---------------------------------------------------------

func register_pool(definition: SpawnDefinition) -> FrameworkResult:
	if definition == null or definition.id == &"":
		return FrameworkResult.fail(
			&"spawn.no_pool_id", "A spawn pool must have an id to be registered."
		)
	if _pools.any(func(pool: SpawnDefinition) -> bool: return pool.id == definition.id):
		return FrameworkResult.fail(
			&"spawn.duplicate_pool",
			"A spawn pool called '%s' is already registered." % definition.id
		)
	_pools.append(definition)
	_timers[definition.id] = {}
	return FrameworkResult.ok(definition)


func unregister_pool(pool_id: StringName) -> bool:
	for index in _pools.size():
		if _pools[index].id == pool_id:
			_pools.remove_at(index)
			_timers.erase(pool_id)
			return true
	return false


func get_pools() -> Array[SpawnDefinition]:
	return _pools.duplicate()


## Puts an anchor in its region's bucket.
##
## The region is resolved once, here, and never again. An anchor that does not
## name one asks the world which region its position falls in — which needs the
## region to have geometry, and is why an anchor with neither says so in
## validation.
func register_anchor(anchor: SpawnAnchor) -> FrameworkResult:
	if anchor == null:
		return FrameworkResult.fail(&"spawn.no_anchor", "There is no anchor to register.")
	var region_id := anchor.get_region_id()
	if region_id == &"":
		if world == null:
			return FrameworkResult.fail(
				&"spawn.no_world", "There is no world to ask which region this is."
			)
		region_id = world.find_region_at(anchor.get_position())
		if region_id == &"":
			return FrameworkResult.fail(
				&"spawn.anchor_outside_regions",
				"This anchor stands in no registered region."
			)
		anchor.set_region_id(region_id)
	if not _anchors.has(region_id):
		_anchors[region_id] = []
	if (_anchors[region_id] as Array).has(anchor):
		return FrameworkResult.ok(anchor)
	(_anchors[region_id] as Array).append(anchor)
	return FrameworkResult.ok(anchor)


func unregister_anchor(anchor: SpawnAnchor) -> bool:
	if anchor == null:
		return false
	var bucket: Array = _anchors.get(anchor.get_region_id(), [])
	var index := bucket.find(anchor)
	if index < 0:
		return false
	bucket.remove_at(index)
	return true


func get_anchors_in(region_id: StringName) -> Array[SpawnAnchor]:
	var found: Array[SpawnAnchor] = []
	found.assign(_anchors.get(region_id, []))
	return found


func get_anchor_count(region_id: StringName = &"") -> int:
	if region_id != &"":
		return (_anchors.get(region_id, []) as Array).size()
	var total := 0
	for key in _anchors:
		total += (_anchors[key] as Array).size()
	return total


# --- Cost reporting -------------------------------------------------------

## Regions and entities the last tick examined.
##
## Reported rather than inferred, because "does this scale?" is a question a
## test should be able to answer directly instead of by timing something and
## hoping. The exit gate asserts these numbers stay flat as the world grows.
func get_last_tick_cost() -> Dictionary:
	return {
		"regions": _last_regions_examined,
		"entities": _last_entities_examined,
	}


func get_tracked_count() -> int:
	return _tracked.size()


# --- Ticking --------------------------------------------------------------

## Advances every active region. Called from a low-frequency timer, never from
## [method Node._process] — the plan's rule that ambient simulation is ticked
## rather than framed.
func tick(delta: float) -> void:
	_last_regions_examined = 0
	_last_entities_examined = 0
	if delta <= 0.0 or not enabled or world == null:
		return
	_elapsed += delta
	_tick_cooldowns(delta)

	# The whole exit gate is this loop's bound: active regions, never all of
	# them, and never anything per-entity outside a region being worked.
	for region_id in world.get_active_regions():
		_last_regions_examined += 1
		_tick_region(region_id, delta)


## Removes what the despawn policies allow, given where the observer is.
##
## Separate from [method tick] and separately budgeted, because "top the world
## up" and "clean the world out" want different frequencies: a project may
## repopulate every second and sweep every ten.
func sweep(observer: Vector3, region_id: StringName = &"") -> int:
	if world == null:
		return 0
	var removed := 0
	var regions: Array = (
		[region_id] if region_id != &"" else world.get_active_regions()
	)
	for id in regions:
		_last_regions_examined += 1
		for entity in world.get_entities_in(id):
			_last_entities_examined += 1
			if _should_despawn(entity, observer, id):
				if despawn(entity, &"despawn.policy"):
					removed += 1
	return removed


# --- Spawning -------------------------------------------------------------

## Places one entity from [param pool] in [param region_id].
##
## Every reason it can refuse is a code rather than a null, because the plan's
## Spawn Debugger asks for "reasons for rejection" and reconstructing them
## afterwards is guesswork.
func spawn_one(pool: SpawnDefinition, region_id: StringName) -> FrameworkResult:
	if not enabled:
		return _refuse(pool, region_id, &"spawn.disabled", "Spawning is switched off.")
	if world == null:
		return _refuse(pool, region_id, &"spawn.no_world", "There is no world to spawn into.")
	var region := world.get_region(region_id)
	if region == null:
		return _refuse(pool, region_id, &"spawn.no_such_region", "No such region.")
	if not world.is_active(region_id):
		return _refuse(pool, region_id, &"spawn.region_dormant", "That region is asleep.")
	if not pool.is_unlocked(narrative):
		return _refuse(pool, region_id, &"spawn.locked", "The story has not unlocked it.")

	var entry := pool.pick(region, narrative, get_rng())
	if entry == null:
		return _refuse(pool, region_id, &"spawn.no_entry", "Nothing in the pool applies here.")
	var category := entry.get_category(pool.category)
	if not world.has_room(region_id, category):
		return _refuse(pool, region_id, &"spawn.budget_full", "The budget is full.")

	var anchor := _pick_anchor(region_id, category)
	if anchor == null:
		return _refuse(pool, region_id, &"spawn.no_anchor", "There is nowhere to put it.")

	var placed := _place(entry.definition_id, anchor.get_spawn_position(get_rng()), region_id, category, pool.despawn)
	if placed.is_err():
		spawn_refused.emit(pool.id, region_id, placed.code)
		return placed
	anchor.mark_used(placed.payload)
	return placed


## Places a whole encounter at a position. What a mission and a trigger call.
func spawn_encounter(
	encounter: EncounterDefinition, region_id: StringName, origin: Vector3
) -> FrameworkResult:
	if not enabled:
		return FrameworkResult.fail(&"spawn.disabled", "Spawning is switched off.")
	if encounter == null:
		return FrameworkResult.fail(&"spawn.no_encounter", "There is no encounter.")
	if world == null or world.get_region(region_id) == null:
		return FrameworkResult.fail(&"spawn.no_such_region", "No such region.")
	if not encounter.is_available(narrative):
		return FrameworkResult.fail(&"spawn.locked", "The story has not unlocked it.")
	if _encounter_cooldowns.get(encounter.id, 0.0) > 0.0:
		return FrameworkResult.fail(&"spawn.cooling_down", "It happened too recently.")

	var placeable: Array[SpawnEntry] = []
	for member in encounter.members:
		if member != null:
			placeable.append(member)
	if placeable.is_empty():
		return FrameworkResult.fail(&"spawn.no_members", "There is nobody in it.")

	# Room for everyone is checked before anybody is placed, so a refused
	# encounter does not leave half an ambush standing about (rule 17).
	if world.get_headroom(region_id, encounter.category) >= 0:
		if world.get_headroom(region_id, encounter.category) < placeable.size():
			return FrameworkResult.fail(
				&"spawn.budget_full", "There is not room for all of them."
			)

	var positions := encounter.get_member_positions(origin, placeable.size(), get_rng())
	var members: Array[Node] = []
	for index in placeable.size():
		var placed := _place(
			placeable[index].definition_id,
			positions[index],
			region_id,
			placeable[index].get_category(encounter.category),
			encounter.despawn
		)
		if placed.is_ok():
			members.append(placed.payload)

	if members.is_empty():
		return FrameworkResult.fail(
			&"spawn.nothing_placed", "None of its members could be placed."
		)
	if encounter.repeatable:
		_encounter_cooldowns[encounter.id] = encounter.cooldown
	elif narrative != null:
		# A once-only encounter records itself in the store that already exists
		# rather than in a set of its own, so it survives a save for free.
		narrative.set_flag(_encounter_flag(encounter.id), true)
	encounter_spawned.emit(encounter.id, members)
	return FrameworkResult.ok(members)


## Whether a non-repeatable encounter has already happened.
func has_run(encounter: EncounterDefinition) -> bool:
	if encounter == null or encounter.repeatable:
		return false
	return narrative != null and narrative.get_flag(_encounter_flag(encounter.id))


## Removes an entity, taking it out of the population count.
func despawn(entity: Node, reason: StringName = &"despawn.requested") -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var region_id := world.get_entity_region(entity) if world != null else &""
	if world != null:
		world.remove_entity(entity)
	_tracked.erase(entity.get_instance_id())
	if entity.get_parent() != null:
		entity.get_parent().remove_child(entity)
	entity.queue_free()
	despawned.emit(entity, region_id, reason)
	return true


## Removes everything this service placed in a region. What unloading a
## district calls.
func despawn_region(region_id: StringName, reason: StringName = &"despawn.region") -> int:
	if world == null:
		return 0
	var removed := 0
	for entity in world.get_entities_in(region_id):
		if _tracked.has(entity.get_instance_id()) and despawn(entity, reason):
			removed += 1
	return removed


## Registers an entity this service did not create, so it counts against the
## budget and can be swept like anything else. What an authored NPC placed by
## hand in the editor uses.
func adopt(
	entity: Node,
	region_id: StringName,
	category: StringName,
	policy: DespawnPolicy = null
) -> FrameworkResult:
	if entity == null:
		return FrameworkResult.fail(&"spawn.no_entity", "There is no entity to adopt.")
	if world == null:
		return FrameworkResult.fail(&"spawn.no_world", "There is no world to adopt it into.")
	var placed := world.set_entity_region(entity, region_id, category)
	if placed.is_err():
		return placed
	_tracked[entity.get_instance_id()] = [_elapsed, policy, region_id, category]
	return FrameworkResult.ok(entity)


func get_age(entity: Node) -> float:
	if entity == null:
		return 0.0
	var record: Array = _tracked.get(entity.get_instance_id(), [])
	return _elapsed - float(record[0]) if record.size() == 4 else 0.0


func clear() -> void:
	_pools.clear()
	_anchors.clear()
	_timers.clear()
	_tracked.clear()
	_encounter_cooldowns.clear()


# --- Internals ------------------------------------------------------------

func _tick_region(region_id: StringName, delta: float) -> void:
	var region := world.get_region(region_id)
	if region == null:
		return
	for anchor in get_anchors_in(region_id):
		anchor.tick(delta)

	for pool in _pools:
		if not pool.applies_to(region):
			continue
		# Decrement first, then decide. Testing the old value and subtracting
		# afterwards costs the tick that exhausts the interval its own turn, so
		# a ten-second pool actually waits ten seconds plus one tick.
		var timers: Dictionary = _timers[pool.id]
		var remaining := float(timers.get(region_id, 0.0)) - delta
		if remaining > 0.0:
			timers[region_id] = remaining
			continue

		var target := pool.get_target_population(region)
		var current := world.get_population(region_id, pool.category)
		if current >= target:
			timers[region_id] = pool.interval
			continue

		var wanted := mini(pool.batch_size, target - current)
		for attempt in wanted:
			if spawn_one(pool, region_id).is_err():
				break
		timers[region_id] = pool.interval


func _tick_cooldowns(delta: float) -> void:
	for id in _encounter_cooldowns.keys():
		var remaining: float = _encounter_cooldowns[id] - delta
		if remaining <= 0.0:
			_encounter_cooldowns.erase(id)
		else:
			_encounter_cooldowns[id] = remaining


## Weighted pick among a region's ready anchors. Bucketed by region, so the
## work is proportional to that district's anchors and not the world's.
func _pick_anchor(region_id: StringName, category: StringName) -> SpawnAnchor:
	var usable: Array[SpawnAnchor] = []
	var total := 0.0
	for anchor in get_anchors_in(region_id):
		if anchor != null and is_instance_valid(anchor) and anchor.accepts(category):
			usable.append(anchor)
			total += maxf(0.0, anchor.weight)
	if usable.is_empty() or total <= 0.0:
		return null
	var roll := get_rng().randf() * total
	for anchor in usable:
		roll -= maxf(0.0, anchor.weight)
		if roll <= 0.0:
			return anchor
	return usable.back()


func _place(
	definition_id: StringName,
	position: Vector3,
	region_id: StringName,
	category: StringName,
	policy: DespawnPolicy
) -> FrameworkResult:
	# EntityFactory already owns "resolve a definition, instantiate its scene,
	# switch bind_on_ready off, add to the tree, bind". Reimplementing that
	# here would be a second load path that drifts from the one saves use
	# (rule 23) -- and it is the load path the whole architecture is designed
	# around, so a spawner that bypassed it would produce entities subtly
	# unlike every other entity in the game.
	var built := EntityFactory.spawn(registry, definition_id, container if container != null else self)
	if built.is_err():
		return built
	var entity: Node = built.payload

	var spatial := entity as Node3D
	if spatial != null:
		spatial.global_position = position

	world.set_entity_region(entity, region_id, category)
	_tracked[entity.get_instance_id()] = [_elapsed, policy, region_id, category]
	spawned.emit(entity, region_id, category)
	return FrameworkResult.ok(entity)


func _should_despawn(entity: Node, observer: Vector3, region_id: StringName) -> bool:
	var record: Array = _tracked.get(entity.get_instance_id(), [])
	if record.size() != 4:
		return false
	var policy: DespawnPolicy = record[1]
	if policy == null:
		return false
	if policy.is_protected_by_state(_states_of(entity)):
		return false
	var spatial := entity as Node3D
	var distance := 0.0
	if spatial != null and spatial.is_inside_tree():
		distance = spatial.global_position.distance_to(observer)
	return policy.allows_despawn(
		_elapsed - float(record[0]), distance, false, world.is_active(region_id)
	)


func _states_of(entity: Node) -> Array[StringName]:
	for component in DefinitionBinder.collect_components(entity):
		if component is SemanticState:
			return (component as SemanticState).get_states()
	return []


func _refuse(
	pool: SpawnDefinition, region_id: StringName, code: StringName, message: String
) -> FrameworkResult:
	spawn_refused.emit(pool.id if pool != null else &"", region_id, code)
	return FrameworkResult.fail(code, message)


static func _encounter_flag(encounter_id: StringName) -> StringName:
	return StringName("encounter.%s.run" % encounter_id)
