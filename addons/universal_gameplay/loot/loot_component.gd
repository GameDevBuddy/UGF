class_name LootComponent
extends FrameworkComponent
## What this entity leaves behind.
##
## Rolls a table into a container: a corpse's pockets, a chest's contents, a
## crate's spill. It rolls once and remembers, so opening the same corpse twice
## does not generate two sets of loot -- which is the bug this component exists
## to make impossible.

## Emitted when the table is rolled, with what came out.
signal loot_generated(instances: Array[ItemInstance])

## What drops. Takes precedence over the definition's.
@export var table_override: LootTableDefinition

## Where it goes. Found among this entity's own components when not wired.
@export var container: InventoryComponent

## Roll as soon as the entity is assembled, rather than waiting to be asked.
## Off is the usual case for a corpse -- it is rolled when it dies -- and on
## suits a chest placed in the world.
@export var rolls_on_bind: bool = false

## Roll when the entity's health reaches zero. The corpse case, wired without
## anything in Loot importing Combat: it observes a local signal on a sibling
## component, which is rule 7's plain default.
@export var rolls_on_death: bool = true

@export var health: HealthComponent

var _table: LootTableDefinition = null
var _rolled: bool = false
var _rng: RandomNumberGenerator = null


func initialize(context: EntityContext) -> void:
	super(context)
	_table = _resolve_table()
	if container == null:
		container = _find_container()
	if health == null:
		health = _find_health()
	if rolls_on_death and health != null and not health.died.is_connected(_on_died):
		health.died.connect(_on_died)
	if rolls_on_bind and not _rolled:
		generate()


func _exit_tree() -> void:
	if health != null and health.died.is_connected(_on_died):
		health.died.disconnect(_on_died)


func get_table() -> LootTableDefinition:
	return _table


func has_rolled() -> bool:
	return _rolled


## Deterministic randomness. Injected so a test gets the same drop twice and a
## networked game can share the stream.
func get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Rolls the table into the container.
##
## Refuses a second time. A corpse searched twice should not be twice as
## generous, and making that the component's rule rather than every caller's is
## the whole reason this is a component.
func generate() -> FrameworkResult:
	if _rolled:
		return FrameworkResult.fail(
			&"loot.already_rolled", "This has already been looted."
		)
	if _table == null:
		return FrameworkResult.fail(&"loot.no_table", "There is nothing to drop.")

	_rolled = true
	var instances: Array[ItemInstance] = []
	for drop in _roll_with_sub_tables(_table, get_rng(), 0):
		var definition := _resolve_item(drop["item_id"])
		if definition == null:
			# Content naming an item that is not registered. Skipping the line
			# beats dropping nothing at all from an otherwise good table.
			push_warning(
				"LootComponent: table '%s' drops unregistered item '%s'." % [
					_table.id, drop["item_id"]
				]
			)
			continue
		var instance := ItemInstance.create(definition, int(drop["quantity"]))
		if container != null:
			container.add(instance)
		instances.append(instance)

	loot_generated.emit(instances)
	return FrameworkResult.ok(instances)


## Lets it be rolled again. What a respawning chest calls.
func reset() -> void:
	_rolled = false


# --- Persistence ----------------------------------------------------------
#
# Whether it has been rolled survives; the contents do not, because they live
# in the container, which saves itself.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"rolled": _rolled}


func restore_state(data: Dictionary) -> void:
	_rolled = bool(data.get("rolled", false))


# --- Internals ------------------------------------------------------------

func _on_died(_context: DamageContext) -> void:
	if not _rolled:
		generate()


## Rolls a table and everything it points at. The depth cap is the guard
## against content that references itself in a cycle, which validation catches
## for a direct self-reference and cannot catch across three tables.
func _roll_with_sub_tables(
	table: LootTableDefinition, rng: RandomNumberGenerator, depth: int
) -> Array[Dictionary]:
	var dropped := table.roll(rng)
	if depth >= 4:
		push_warning(
			"LootComponent: table '%s' nests more than four deep; stopping." % table.id
		)
		return dropped
	for sub_id in table.sub_tables:
		var sub := _resolve_table_by_id(sub_id)
		if sub != null:
			dropped.append_array(_roll_with_sub_tables(sub, rng, depth + 1))
	return dropped


func _resolve_item(item_id: StringName) -> ItemDefinition:
	return _from_registry(item_id) as ItemDefinition


func _resolve_table_by_id(table_id: StringName) -> LootTableDefinition:
	return _from_registry(table_id) as LootTableDefinition


func _from_registry(id: StringName) -> FrameworkDefinition:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", id) as FrameworkDefinition


## Read by property name rather than by casting, so a crate or a vehicle with
## its own definition type can carry loot (rule 9).
func _resolve_table() -> LootTableDefinition:
	if table_override != null:
		return table_override
	var definition := get_definition()
	if definition != null and "loot" in definition:
		var candidate: Variant = definition.get("loot")
		if candidate is LootTableDefinition:
			return candidate as LootTableDefinition
	return null


func _find_container() -> InventoryComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _find_health() -> HealthComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is HealthComponent:
			return component as HealthComponent
	return null
