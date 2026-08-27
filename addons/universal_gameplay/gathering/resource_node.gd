class_name ResourceNode
extends FrameworkComponent
## A tree, a vein, a bush: something the world gives up when worked.
##
## Rolls a loot table into the harvester's bag, wears their tool, spends a
## charge and respawns on a timer. Every harvest is validate-then-mutate: the
## tool, the charges and the room are checked before anything is yielded.

## Emitted when the node is worked, with what came out.
signal harvested(by: Node, instances: Array[ItemInstance])
## Emitted when a harvest was refused.
signal harvest_refused(by: Node, reason: StringName)
## Emitted when the last charge is spent.
signal depleted
## Emitted when it comes back.
signal replenished

## What this node is. Takes precedence over the definition's.
@export var node_override: ResourceNodeDefinition

## Tick the respawn clock. Off when something else owns time, and irrelevant
## for a node that never respawns.
@export var auto_tick: bool = true

var _definition: ResourceNodeDefinition = null
var _charges: int = 0
var _since_depleted: float = 0.0
var _rng: RandomNumberGenerator = null


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _needs_ticking())


func initialize(context: EntityContext) -> void:
	super(context)
	_definition = _resolve_definition()
	if _definition != null:
		_charges = _definition.charges
	set_physics_process(auto_tick and _needs_ticking())


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

func get_node_definition() -> ResourceNodeDefinition:
	return _definition


func get_charges() -> int:
	return _charges


func is_depleted() -> bool:
	if _definition == null:
		return true
	return not _definition.is_unlimited() and _charges <= 0


func get_time_until_respawn() -> float:
	if not is_depleted() or _definition == null or not _definition.respawns():
		return 0.0
	return maxf(0.0, _definition.respawn_time - _since_depleted)


## Deterministic randomness for the yield roll. Injected so a test gets the
## same drop twice and a networked game can share the stream.
func get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Whether [param harvester] could work this node right now.
func can_harvest(harvester: Node) -> FrameworkResult:
	if _definition == null:
		return FrameworkResult.fail(&"node.not_a_resource", "There is nothing to gather.")
	if is_depleted():
		return FrameworkResult.fail(&"node.depleted", "There is nothing left here.")
	var bag := _inventory_of(harvester)
	if bag == null:
		return FrameworkResult.fail(&"node.no_inventory", "There is nowhere to put it.")
	if _definition.needs_tool() and _find_tool(bag) == null:
		return FrameworkResult.fail(
			&"node.no_tool", "You need a %s." % _definition.required_tool_tag
		)
	return FrameworkResult.ok(_definition)


## The tool [param harvester] would use, or null when none is needed or held.
func find_tool(harvester: Node) -> ItemInstance:
	if _definition == null or not _definition.needs_tool():
		return null
	return _find_tool(_inventory_of(harvester))


# --- Harvesting -----------------------------------------------------------

## Works the node: rolls its table into the harvester's bag, wears their tool
## and spends a charge.
func harvest(harvester: Node) -> FrameworkResult:
	var allowed := can_harvest(harvester)
	if allowed.is_err():
		harvest_refused.emit(harvester, allowed.code)
		return allowed

	var bag := _inventory_of(harvester)
	var table := _lookup(_definition.loot_table_id) as LootTableDefinition
	if table == null:
		return FrameworkResult.fail(
			&"node.unknown_table",
			"No loot table is registered as '%s'." % _definition.loot_table_id
		)

	var tool := _find_tool(bag)
	if tool != null and _definition.tool_wear > 0.0 and tool.has_durability():
		tool.degrade(_definition.tool_wear)

	var yielded: Array[ItemInstance] = []
	for drop in table.roll(get_rng()):
		var item := _lookup(drop["item_id"]) as ItemDefinition
		if item == null:
			push_warning(
				"ResourceNode: table '%s' yields unregistered item '%s'." % [
					table.id, drop["item_id"]
				]
			)
			continue
		var instance := ItemInstance.create(item, int(drop["quantity"]))
		bag.add(instance)
		yielded.append(instance)

	if not _definition.is_unlimited():
		_charges -= 1
		if _charges <= 0:
			_since_depleted = 0.0
			set_physics_process(auto_tick and _needs_ticking())
			depleted.emit()

	harvested.emit(harvester, yielded)
	return FrameworkResult.ok(yielded)


## Brings a spent node back. What a respawn timer and a world reset call.
func replenish() -> void:
	if _definition == null:
		return
	_charges = _definition.charges
	_since_depleted = 0.0
	replenished.emit()


func tick(delta: float) -> void:
	if delta <= 0.0 or not _needs_ticking():
		return
	_since_depleted += delta
	if _since_depleted >= _definition.respawn_time:
		replenish()


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"charges": _charges, "since_depleted": _since_depleted}


func restore_state(data: Dictionary) -> void:
	_charges = int(data.get("charges", _charges))
	_since_depleted = float(data.get("since_depleted", 0.0))
	set_physics_process(auto_tick and _needs_ticking())


# --- Internals ------------------------------------------------------------

func _needs_ticking() -> bool:
	return is_depleted() and _definition != null and _definition.respawns()


func _find_tool(bag: InventoryComponent) -> ItemInstance:
	if bag == null or _definition == null or not _definition.needs_tool():
		return null
	for instance in bag.get_items():
		if instance.definition == null:
			continue
		if not instance.definition.has_tag(_definition.required_tool_tag):
			continue
		# A broken axe is not an axe. Letting one work would make durability
		# decorative.
		if instance.has_durability() and instance.is_broken():
			continue
		return instance
	return null


func _inventory_of(node: Node) -> InventoryComponent:
	if node == null:
		return null
	for component in DefinitionBinder.collect_components(node):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _lookup(id: StringName) -> FrameworkDefinition:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", id) as FrameworkDefinition


## Read by property name rather than by casting, so a world object with its own
## definition type can be harvestable (rule 9).
func _resolve_definition() -> ResourceNodeDefinition:
	if node_override != null:
		return node_override
	var definition := get_definition()
	if definition is ResourceNodeDefinition:
		return definition as ResourceNodeDefinition
	if definition != null and "resource_node" in definition:
		var candidate: Variant = definition.get("resource_node")
		if candidate is ResourceNodeDefinition:
			return candidate as ResourceNodeDefinition
	return null
