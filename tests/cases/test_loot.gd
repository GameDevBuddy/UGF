extends FrameworkTestCase
## Covers LootTableDefinition and LootComponent: what drops, how often, and
## the guarantee that a corpse is only generous once.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var sword: ItemDefinition = null
var coin: ItemDefinition = null
var gem: ItemDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	sword = ItemFixtures.unique(&"item.sword")
	coin = ItemFixtures.stackable(&"item.coin", 999)
	gem = ItemFixtures.unique(&"item.gem")
	for definition in [sword, coin, gem]:
		core.get_definition_registry().register(definition)


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _quantity_of(drops: Array, item_id: StringName) -> int:
	for drop in drops:
		if drop["item_id"] == item_id:
			return int(drop["quantity"])
	return 0


# --- Rolling --------------------------------------------------------------

func test_a_guaranteed_entry_always_drops() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.bandit",
		[CommerceFixtures.loot_entry(&"item.sword", 1, 1, 0.0, true)],
		0
	)
	for attempt in 10:
		assert_eq(_quantity_of(table.roll(_rng(attempt)), &"item.sword"), 1)


func test_a_guaranteed_entry_can_still_have_a_chance() -> void:
	var entry := CommerceFixtures.loot_entry(&"item.gem", 1, 1, 0.0, true)
	entry.chance = 0.5
	var table := CommerceFixtures.loot_table(&"loot.rare", [entry], 0)

	var dropped := 0
	for attempt in 200:
		if not table.roll(_rng(attempt)).is_empty():
			dropped += 1
	assert_true(dropped > 50 and dropped < 150, "roughly half of 200, got %d" % dropped)


func test_a_zero_chance_guaranteed_entry_never_drops() -> void:
	var entry := CommerceFixtures.loot_entry(&"item.gem", 1, 1, 0.0, true)
	entry.chance = 0.0
	var table := CommerceFixtures.loot_table(&"loot.never", [entry], 0)
	assert_empty(table.roll(_rng()))


func test_a_quantity_range_is_rolled() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.purse",
		[CommerceFixtures.loot_entry(&"item.coin", 5, 20, 0.0, true)],
		0
	)
	var low := 999
	var high := 0
	for attempt in 100:
		var amount := _quantity_of(table.roll(_rng(attempt)), &"item.coin")
		low = mini(low, amount)
		high = maxi(high, amount)
	assert_true(low >= 5 and high <= 20, "got %d..%d" % [low, high])
	assert_true(high > low, "the range should actually vary")


func test_weight_decides_which_entry_is_picked() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.weighted",
		[
			CommerceFixtures.loot_entry(&"item.coin", 1, 1, 90.0),
			CommerceFixtures.loot_entry(&"item.gem", 1, 1, 10.0),
		],
		1
	)
	var coins := 0
	for attempt in 200:
		if _quantity_of(table.roll(_rng(attempt)), &"item.coin") > 0:
			coins += 1
	assert_true(coins > 140, "the heavy entry should dominate, got %d of 200" % coins)


func test_the_same_seed_drops_the_same_loot() -> void:
	# So a networked game can hand every client the same stream.
	var table := CommerceFixtures.loot_table(
		&"loot.mixed",
		[
			CommerceFixtures.loot_entry(&"item.coin", 1, 10),
			CommerceFixtures.loot_entry(&"item.gem", 1, 2),
		],
		2
	)
	assert_eq(str(table.roll(_rng(99))), str(table.roll(_rng(99))))


func test_several_rolls_can_pick_the_same_entry_twice() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.coins", [CommerceFixtures.loot_entry(&"item.coin", 1, 1)], 3
	)
	assert_eq(_quantity_of(table.roll(_rng()), &"item.coin"), 3)


func test_duplicates_can_be_forbidden() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.unique",
		[
			CommerceFixtures.loot_entry(&"item.coin", 1, 1),
			CommerceFixtures.loot_entry(&"item.gem", 1, 1),
		],
		2
	)
	table.allows_duplicates = false
	var drops := table.roll(_rng())
	assert_eq(_quantity_of(drops, &"item.coin"), 1)
	assert_eq(_quantity_of(drops, &"item.gem"), 1)


func test_repeated_picks_of_one_entry_merge_into_one_stack() -> void:
	# Which is what an inventory would end up with anyway.
	var table := CommerceFixtures.loot_table(
		&"loot.coins", [CommerceFixtures.loot_entry(&"item.coin", 2, 2)], 3
	)
	assert_size(table.roll(_rng()), 1)


func test_an_empty_table_drops_nothing() -> void:
	assert_empty(CommerceFixtures.loot_table(&"loot.empty", [], 3).roll(_rng()))


# --- Validation -----------------------------------------------------------

func test_an_entry_with_no_item_is_a_content_error() -> void:
	assert_false(LootEntry.new().validate().is_valid())


func test_an_unreachable_entry_is_flagged() -> void:
	var entry := CommerceFixtures.loot_entry(&"item.gem", 1, 1, 0.0)
	assert_true(entry.validate().has_warnings())


func test_rolling_a_table_of_only_guaranteed_entries_is_flagged() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.fixed", [CommerceFixtures.loot_entry(&"item.sword", 1, 1, 0.0, true)], 2
	)
	assert_true(table.validate().has_warnings())


func test_more_rolls_than_entries_without_duplicates_is_flagged() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.short", [CommerceFixtures.loot_entry(&"item.coin")], 3
	)
	table.allows_duplicates = false
	assert_true(table.validate().has_warnings())


func test_a_table_that_rolls_itself_is_an_error() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.recursive", [CommerceFixtures.loot_entry(&"item.coin")]
	)
	var subs: Array[StringName] = [&"loot.recursive"]
	table.sub_tables = subs
	assert_false(table.validate().is_valid())


# --- The component --------------------------------------------------------

func _corpse(table: LootTableDefinition, with_health: bool = true) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Corpse"

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	if with_health:
		var health := HealthComponent.new()
		health.name = "HealthComponent"
		health.maximum_health = 100.0
		entity.add_child(health)

	var loot := LootComponent.new()
	loot.name = "LootComponent"
	loot.table_override = table
	entity.add_child(loot)

	CommerceFixtures.assemble(entity, core)
	loot.set_rng(_rng())
	return entity


func _loot_of(entity: Node) -> LootComponent:
	for component in DefinitionBinder.collect_components(entity):
		if component is LootComponent:
			return component as LootComponent
	return null


func test_rolling_fills_the_container() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.bandit",
		[
			CommerceFixtures.loot_entry(&"item.sword", 1, 1, 0.0, true),
			CommerceFixtures.loot_entry(&"item.coin", 5, 5, 0.0, true),
		],
		0
	)
	var corpse := _corpse(table)
	assert_ok(_loot_of(corpse).generate())

	var bag := CommerceFixtures.inventory_of(corpse)
	assert_eq(bag.count(&"item.sword"), 1)
	assert_eq(bag.count(&"item.coin"), 5)


func test_a_corpse_is_only_generous_once() -> void:
	# The bug this component exists to make impossible.
	var table := CommerceFixtures.loot_table(
		&"loot.bandit", [CommerceFixtures.loot_entry(&"item.coin", 5, 5, 0.0, true)], 0
	)
	var corpse := _corpse(table)
	_loot_of(corpse).generate()
	assert_err(_loot_of(corpse).generate(), &"loot.already_rolled")
	assert_eq(CommerceFixtures.inventory_of(corpse).count(&"item.coin"), 5)


func test_dying_rolls_the_table() -> void:
	# Wired through a local signal on a sibling component, so nothing in Loot
	# imports Combat (rule 7).
	var table := CommerceFixtures.loot_table(
		&"loot.bandit", [CommerceFixtures.loot_entry(&"item.coin", 3, 3, 0.0, true)], 0
	)
	var corpse := _corpse(table)
	assert_eq(CommerceFixtures.inventory_of(corpse).count(&"item.coin"), 0)

	for component in DefinitionBinder.collect_components(corpse):
		if component is HealthComponent:
			(component as HealthComponent).kill()

	assert_eq(CommerceFixtures.inventory_of(corpse).count(&"item.coin"), 3)
	assert_true(_loot_of(corpse).has_rolled())


func test_a_chest_can_roll_as_soon_as_it_is_placed() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.chest", [CommerceFixtures.loot_entry(&"item.gem", 1, 1, 0.0, true)], 0
	)
	var chest := add_test_node(Node3D.new()) as Node3D
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	chest.add_child(inventory)

	var loot := LootComponent.new()
	loot.name = "LootComponent"
	loot.table_override = table
	loot.rolls_on_bind = true
	loot.rolls_on_death = false
	chest.add_child(loot)
	CommerceFixtures.assemble(chest, core)

	assert_eq(inventory.count(&"item.gem"), 1)


func test_a_table_naming_an_unregistered_item_skips_that_line() -> void:
	# Skipping beats dropping nothing at all from an otherwise good table.
	var table := CommerceFixtures.loot_table(
		&"loot.partly_broken",
		[
			CommerceFixtures.loot_entry(&"item.nonexistent", 1, 1, 0.0, true),
			CommerceFixtures.loot_entry(&"item.coin", 2, 2, 0.0, true),
		],
		0
	)
	var corpse := _corpse(table)
	_loot_of(corpse).generate()
	assert_eq(CommerceFixtures.inventory_of(corpse).count(&"item.coin"), 2)


func test_sub_tables_are_rolled_as_well() -> void:
	# "A bandit drops bandit loot plus common loot" as one line.
	var common := CommerceFixtures.loot_table(
		&"loot.common", [CommerceFixtures.loot_entry(&"item.coin", 4, 4, 0.0, true)], 0
	)
	core.get_definition_registry().register(common)

	var bandit := CommerceFixtures.loot_table(
		&"loot.bandit", [CommerceFixtures.loot_entry(&"item.sword", 1, 1, 0.0, true)], 0
	)
	var subs: Array[StringName] = [&"loot.common"]
	bandit.sub_tables = subs

	var corpse := _corpse(bandit)
	_loot_of(corpse).generate()
	var bag := CommerceFixtures.inventory_of(corpse)
	assert_eq(bag.count(&"item.sword"), 1)
	assert_eq(bag.count(&"item.coin"), 4)


func test_a_cycle_across_tables_stops_rather_than_hanging() -> void:
	# Validation catches a direct self-reference and cannot catch this.
	var first := CommerceFixtures.loot_table(
		&"loot.first", [CommerceFixtures.loot_entry(&"item.coin", 1, 1, 0.0, true)], 0
	)
	var second := CommerceFixtures.loot_table(
		&"loot.second", [CommerceFixtures.loot_entry(&"item.gem", 1, 1, 0.0, true)], 0
	)
	var to_second: Array[StringName] = [&"loot.second"]
	var to_first: Array[StringName] = [&"loot.first"]
	first.sub_tables = to_second
	second.sub_tables = to_first
	core.get_definition_registry().register(first)
	core.get_definition_registry().register(second)

	var corpse := _corpse(first)
	assert_ok(_loot_of(corpse).generate())


func test_generation_is_announced() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.bandit", [CommerceFixtures.loot_entry(&"item.coin", 3, 3, 0.0, true)], 0
	)
	var corpse := _corpse(table)
	var generated: Array[ItemInstance] = []
	_loot_of(corpse).loot_generated.connect(
		func(instances: Array[ItemInstance]) -> void: generated.append_array(instances)
	)
	_loot_of(corpse).generate()
	assert_size(generated, 1)


func test_an_entity_with_no_table_drops_nothing() -> void:
	var corpse := _corpse(null)
	assert_err(_loot_of(corpse).generate(), &"loot.no_table")


func test_whether_it_was_looted_survives_a_save() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.bandit", [CommerceFixtures.loot_entry(&"item.coin", 3, 3, 0.0, true)], 0
	)
	var corpse := _corpse(table)
	_loot_of(corpse).generate()
	var saved := _loot_of(corpse).capture_state()

	_loot_of(corpse).reset()
	assert_false(_loot_of(corpse).has_rolled())
	_loot_of(corpse).restore_state(saved)
	assert_true(_loot_of(corpse).has_rolled())


func test_a_respawning_chest_can_be_rolled_again() -> void:
	var table := CommerceFixtures.loot_table(
		&"loot.chest", [CommerceFixtures.loot_entry(&"item.coin", 2, 2, 0.0, true)], 0
	)
	var chest := _corpse(table)
	_loot_of(chest).generate()
	_loot_of(chest).reset()
	assert_ok(_loot_of(chest).generate())
	assert_eq(CommerceFixtures.inventory_of(chest).count(&"item.coin"), 4)
