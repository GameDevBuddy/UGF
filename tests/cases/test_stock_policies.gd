extends FrameworkTestCase
## The two stock policies the plan names and M11 did not build: generated and
## rotating (implementation-plan.md line 470).
##
## The other three are already there and are per-line rather than per-shop:
## [i]fixed[/i] is an authored [StockEntry], [i]finite[/i] is a positive
## quantity and [i]unlimited[/i] is minus one. These two are decisions about
## the shelf itself, which is why they live on [VendorDefinition].

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


func _entry(item_id: StringName, quantity: int = 3) -> StockEntry:
	var entry := StockEntry.new()
	entry.item_id = item_id
	entry.quantity = quantity
	entry.maximum = quantity
	entry.restock_amount = quantity
	return entry


func _definition(entries: Array) -> VendorDefinition:
	var definition := VendorDefinition.new()
	definition.id = &"vendor.test"
	definition.display_name = "Test"
	var typed: Array[StockEntry] = []
	typed.assign(entries)
	definition.stock = typed
	definition.currency = &"currency.gold"
	definition.restock_interval = 10.0
	return definition


func _rng(seed_value: int = 20260827) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _vendor(definition: VendorDefinition) -> VendorComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Merchant"
	var component := VendorComponent.new()
	component.name = "VendorComponent"
	component.vendor_override = definition
	component.auto_tick = false
	entity.add_child(component)
	component.set_rng(_rng())
	component.initialize(EntityContext.create(entity, null, core))
	return component


func _stocked_ids(vendor: VendorComponent) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in vendor.get_stock():
		if entry != null:
			ids.append(entry.item_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return ids


# --- Fixed, unchanged -----------------------------------------------------

func test_a_fixed_shop_stocks_everything_it_was_authored_with() -> void:
	var vendor := _vendor(
		_definition([_entry(&"item.a"), _entry(&"item.b"), _entry(&"item.c")])
	)
	assert_size(vendor.get_stock(), 3)


# --- Rotating -------------------------------------------------------------

func test_a_rotating_shop_stocks_only_its_slots() -> void:
	var definition := _definition(
		[_entry(&"item.a"), _entry(&"item.b"), _entry(&"item.c"), _entry(&"item.d")]
	)
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 2

	assert_size(_vendor(definition).get_stock(), 2)


func test_a_rotating_shop_never_stocks_the_same_line_twice() -> void:
	var definition := _definition(
		[_entry(&"item.a"), _entry(&"item.b"), _entry(&"item.c")]
	)
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 3

	var ids := _stocked_ids(_vendor(definition))

	assert_eq(ids, [&"item.a", &"item.b", &"item.c"] as Array[StringName])


func test_rotating_reshuffles_on_restock_rather_than_topping_up() -> void:
	# Topping up the current lines would make the rotation never happen, which
	# is the whole failure this mode exists to avoid.
	var definition := _definition([
		_entry(&"item.a"), _entry(&"item.b"), _entry(&"item.c"),
		_entry(&"item.d"), _entry(&"item.e"), _entry(&"item.f"),
	])
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 2

	var vendor := _vendor(definition)
	var seen: Dictionary[StringName, bool] = {}
	for _week in 12:
		for id in _stocked_ids(vendor):
			seen[id] = true
		vendor.restock()

	assert_true(
		seen.size() > 2,
		"The shelf never changed: only %d distinct lines in twelve restocks" % seen.size()
	)


func test_more_slots_than_lines_stocks_all_of_them() -> void:
	# A no-op rather than an error: asking for five of three is a shop that
	# sells three things.
	var definition := _definition([_entry(&"item.a"), _entry(&"item.b")])
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 5

	assert_size(_vendor(definition).get_stock(), 2)


func test_a_rotating_shop_keeps_what_the_player_sold_it() -> void:
	# A fence that forgot your goods every time it rotated would eat them, and
	# "the shop lost my sword" is a bug report nobody enjoys.
	var definition := _definition([_entry(&"item.a"), _entry(&"item.b"), _entry(&"item.c")])
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 1

	var vendor := _vendor(definition)
	vendor.give_stock(&"item.players_sword", 1)

	vendor.restock()

	assert_true(
		_stocked_ids(vendor).has(&"item.players_sword"),
		"The rotation threw away what the player sold"
	)


# --- Generated ------------------------------------------------------------

func _register_table(item_ids: Array[StringName]) -> LootTableDefinition:
	var entries: Array[LootEntry] = []
	for id in item_ids:
		var entry := LootEntry.new()
		entry.item_id = id
		entry.minimum = 2
		entry.maximum = 2
		entry.guaranteed = true
		entries.append(entry)

	var table := LootTableDefinition.new()
	table.id = &"loot.fence"
	table.display_name = "Fence"
	table.entries = entries
	core.register_definition(table)
	return table


func test_a_generated_shop_stocks_what_the_table_rolled() -> void:
	var ids: Array[StringName] = [&"item.x", &"item.y"]
	_register_table(ids)

	var definition := _definition([])
	definition.stock_mode = VendorDefinition.StockMode.GENERATED
	definition.generated_table_id = &"loot.fence"

	var vendor := _vendor(definition)

	assert_eq(_stocked_ids(vendor), [&"item.x", &"item.y"] as Array[StringName])


func test_a_generated_line_is_capped() -> void:
	# So a lucky roll does not produce a shop with four hundred of something.
	var entry := LootEntry.new()
	entry.item_id = &"item.x"
	entry.minimum = 500
	entry.maximum = 500
	entry.guaranteed = true
	var table := LootTableDefinition.new()
	table.id = &"loot.flood"
	table.display_name = "Flood"
	var entries: Array[LootEntry] = [entry]
	table.entries = entries
	core.register_definition(table)

	var definition := _definition([])
	definition.stock_mode = VendorDefinition.StockMode.GENERATED
	definition.generated_table_id = &"loot.flood"
	definition.generated_maximum = 4

	assert_eq(_vendor(definition).get_stock()[0].quantity, 4)


func test_a_generated_shop_falls_back_to_its_authored_shelf() -> void:
	# A shop with nothing on it and no error is a bug report reading "the
	# merchant sells nothing".
	var definition := _definition([_entry(&"item.fallback")])
	definition.stock_mode = VendorDefinition.StockMode.GENERATED
	definition.generated_table_id = &"loot.not_registered"

	assert_eq(_stocked_ids(_vendor(definition)), [&"item.fallback"] as Array[StringName])


func test_a_generated_shop_rerolls_on_restock() -> void:
	var ids: Array[StringName] = [&"item.x"]
	_register_table(ids)
	var definition := _definition([])
	definition.stock_mode = VendorDefinition.StockMode.GENERATED
	definition.generated_table_id = &"loot.fence"

	var vendor := _vendor(definition)
	vendor.take_stock(&"item.x", 2)
	assert_eq(vendor.find_stock(&"item.x").quantity, 0, "Sold out")

	vendor.restock()

	assert_true(vendor.has_stock(&"item.x", 1), "The shelf was not rebuilt")


# --- Building a shelf with nothing injected -------------------------------

func test_a_definition_builds_a_shelf_with_no_rng_and_no_registry() -> void:
	# Rule 33: a definition stays usable in a test with nothing wired up. A
	# rotating shop with no generator stocks its whole pool rather than
	# nothing at all.
	var definition := _definition([_entry(&"item.a"), _entry(&"item.b")])
	definition.stock_mode = VendorDefinition.StockMode.ROTATING
	definition.rotating_slots = 1

	assert_size(definition.build_stock(), 2)
