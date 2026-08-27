extends FrameworkTestCase
## The three things the plan's Loot section asked for and M11 did not build:
## rarity, conditional entries and currency rewards
## (implementation-plan.md lines 358, 360, 364).
##
## M11 shipped weighted tables, guarantees and per-entry chance -- all
## probability, no predicate, and nothing that knew what a coin was.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var narrative: NarrativeStateService = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	narrative = NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)


func _item(id: StringName, rarity: StringName = &"") -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.category = &"item.material"
	definition.max_stack = 99
	definition.rarity = rarity
	core.register_definition(definition)
	return definition


func _entry(
	item_id: StringName, quantity: int = 1, weight: float = 1.0, guaranteed: bool = true
) -> LootEntry:
	var entry := LootEntry.new()
	entry.item_id = item_id
	entry.minimum = quantity
	entry.maximum = quantity
	entry.weight = weight
	entry.guaranteed = guaranteed
	return entry


func _table(entries: Array, rolls: int = 0) -> LootTableDefinition:
	var definition := LootTableDefinition.new()
	definition.id = &"loot.test"
	definition.display_name = "Test"
	var typed: Array[LootEntry] = []
	typed.assign(entries)
	definition.entries = typed
	definition.rolls = rolls
	return definition


func _rng(seed_value: int = 20260827) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A corpse with a bag, a purse and a table.
func _corpse(table: LootTableDefinition) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Corpse"

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var profile := InventoryProfile.new()
	profile.slot_count = 20
	inventory.profile_override = profile
	entity.add_child(inventory)

	entity.add_child(CommerceFixtures.wallet(0.0))

	var loot := LootComponent.new()
	loot.name = "LootComponent"
	loot.table_override = table
	loot.container = inventory
	loot.narrative = narrative
	loot.rolls_on_death = false
	entity.add_child(loot)

	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)

	for child in entity.get_children():
		if child is LootComponent:
			(child as LootComponent).wallet = CommerceFixtures.wallet_of(entity)
	return entity


func _loot_of(entity: Node) -> LootComponent:
	for child in entity.get_children():
		if child is LootComponent:
			return child as LootComponent
	return null


func _inventory_of(entity: Node) -> InventoryComponent:
	for child in entity.get_children():
		if child is InventoryComponent:
			return child as InventoryComponent
	return null


# --- Conditional entries --------------------------------------------------

func test_an_entry_requiring_an_unset_flag_does_not_drop() -> void:
	_item(&"item.relic")
	var entry := _entry(&"item.relic")
	var required: Array[StringName] = [&"flag.quest_started"]
	entry.required_flags = required

	var corpse := _corpse(_table([entry]))
	_loot_of(corpse).generate()

	assert_eq(_inventory_of(corpse).count(&"item.relic"), 0)


func test_the_same_entry_drops_once_the_flag_is_set() -> void:
	_item(&"item.relic")
	var entry := _entry(&"item.relic")
	var required: Array[StringName] = [&"flag.quest_started"]
	entry.required_flags = required
	narrative.set_flag(&"flag.quest_started")

	var corpse := _corpse(_table([entry]))
	_loot_of(corpse).generate()

	assert_eq(_inventory_of(corpse).count(&"item.relic"), 1)


func test_a_forbidden_flag_stops_a_drop_the_player_already_has() -> void:
	_item(&"item.key")
	var entry := _entry(&"item.key")
	var forbidden: Array[StringName] = [&"flag.has_key"]
	entry.forbidden_flags = forbidden
	narrative.set_flag(&"flag.has_key")

	var corpse := _corpse(_table([entry]))
	_loot_of(corpse).generate()

	assert_eq(_inventory_of(corpse).count(&"item.key"), 0)


func test_a_conditional_entry_with_no_flag_store_is_ineligible_not_free() -> void:
	# A condition that cannot be evaluated has not been met. Dropping it would
	# make deleting the Narrative module silently unlock every gated drop.
	_item(&"item.relic")
	var entry := _entry(&"item.relic")
	var required: Array[StringName] = [&"flag.quest_started"]
	entry.required_flags = required

	assert_false(entry.is_eligible(null))
	assert_true(_entry(&"item.rock").is_eligible(null), "An ungated entry needs no store")


func test_an_ineligible_entry_does_not_consume_a_roll() -> void:
	# Removed from the pool rather than skipped when picked. Skipping would
	# make a table drop less the more conditions it carried, which reads as
	# "the loot got worse" and is very hard to trace back to a flag.
	_item(&"item.common")
	_item(&"item.gated")
	var open := _entry(&"item.common", 1, 1.0, false)
	var gated := _entry(&"item.gated", 1, 1.0, false)
	var required: Array[StringName] = [&"flag.never"]
	gated.required_flags = required

	# Rolled many times: one seed landing on the eligible entry proves nothing,
	# because with the filter removed it would land there half the time anyway.
	var table := _table([open, gated], 1)
	var commons := 0
	var gateds := 0
	var rng := _rng()
	for _attempt in 60:
		var corpse := _corpse(table)
		_loot_of(corpse).set_rng(rng)
		_loot_of(corpse).generate()
		commons += _inventory_of(corpse).count(&"item.common")
		gateds += _inventory_of(corpse).count(&"item.gated")

	assert_eq(gateds, 0, "The gated entry dropped despite its flag being unset")
	assert_eq(commons, 60, "Every roll should have landed on the one eligible entry")


# --- Currency -------------------------------------------------------------

func _currency_entry(currency: StringName, amount: int) -> LootEntry:
	var entry := LootEntry.new()
	entry.currency_id = currency
	entry.minimum = amount
	entry.maximum = amount
	entry.guaranteed = true
	return entry


func test_a_currency_entry_pays_into_the_wallet() -> void:
	var corpse := _corpse(_table([_currency_entry(&"currency.gold", 40)]))
	assert_eq(CommerceFixtures.wallet_of(corpse).get_balance(&"currency.gold"), 0.0)

	_loot_of(corpse).generate()

	assert_eq(CommerceFixtures.wallet_of(corpse).get_balance(&"currency.gold"), 40.0)


func test_currency_is_announced_separately_from_items() -> void:
	# An item list containing something that is not an item would make every
	# existing listener check what it got.
	_item(&"item.rock")
	var corpse := _corpse(
		_table([_entry(&"item.rock"), _currency_entry(&"currency.gold", 10)])
	)
	var money: Array[Dictionary] = []
	var things: Array[int] = []
	_loot_of(corpse).currency_generated.connect(
		func(amounts: Dictionary) -> void: money.append(amounts)
	)
	_loot_of(corpse).loot_generated.connect(
		func(instances: Array[ItemInstance]) -> void: things.append(instances.size())
	)

	_loot_of(corpse).generate()

	assert_size(money, 1)
	assert_eq(money[0][&"currency.gold"], 10)
	assert_eq(things[0], 1, "The item list carries only the item")


func test_currency_with_no_wallet_is_still_reported() -> void:
	# Rule 31: the right behaviour for a corpse in a project with no Commerce.
	var corpse := _corpse(_table([_currency_entry(&"currency.gold", 25)]))
	_loot_of(corpse).wallet = null
	var money: Array[Dictionary] = []
	_loot_of(corpse).currency_generated.connect(
		func(amounts: Dictionary) -> void: money.append(amounts)
	)

	assert_ok(_loot_of(corpse).generate())

	assert_size(money, 1, "The drop happened; it just landed nowhere")


func test_an_entry_naming_both_an_item_and_a_currency_is_rejected() -> void:
	var entry := _entry(&"item.rock")
	entry.currency_id = &"currency.gold"
	assert_true(entry.validate().has_errors())


func test_an_entry_naming_neither_is_rejected() -> void:
	assert_true(LootEntry.new().validate().has_errors())


func test_an_entry_that_requires_and_forbids_one_flag_is_rejected() -> void:
	var entry := _entry(&"item.rock")
	var both: Array[StringName] = [&"flag.x"]
	entry.required_flags = both
	entry.forbidden_flags = both
	assert_true(entry.validate().has_errors())


# --- Rarity ---------------------------------------------------------------

func test_rarity_biases_which_entry_is_picked() -> void:
	# Rolled many times with one seeded generator: a legendary weighted at a
	# hundredth should be rare, not absent, and the common should dominate.
	_item(&"item.common", &"rarity.common")
	_item(&"item.legendary", &"rarity.legendary")

	var common := _entry(&"item.common", 1, 1.0, false)
	var legendary := _entry(&"item.legendary", 1, 1.0, false)
	var table := _table([common, legendary], 1)

	var weights: Dictionary[StringName, float] = {
		&"rarity.common": 1.0, &"rarity.legendary": 0.01
	}
	var commons := 0
	var legendaries := 0
	var rng := _rng()
	for _attempt in 200:
		var corpse := _corpse(table)
		var loot := _loot_of(corpse)
		loot.rarity_weights = weights
		loot.set_rng(rng)
		loot.generate()
		commons += _inventory_of(corpse).count(&"item.common")
		legendaries += _inventory_of(corpse).count(&"item.legendary")

	assert_eq(commons + legendaries, 200, "Every roll dropped exactly one thing")
	assert_true(
		commons > legendaries * 10,
		"Rarity did not bias the pick: %d common to %d legendary" % [commons, legendaries]
	)


func test_without_a_rarity_table_nothing_is_biased() -> void:
	# A table with no rarity configuration must behave exactly as it did
	# before rarity existed.
	_item(&"item.common", &"rarity.common")
	_item(&"item.legendary", &"rarity.legendary")
	var table := _table(
		[_entry(&"item.common", 1, 1.0, false), _entry(&"item.legendary", 1, 1.0, false)], 1
	)

	var legendaries := 0
	var rng := _rng()
	for _attempt in 200:
		var corpse := _corpse(table)
		_loot_of(corpse).set_rng(rng)
		_loot_of(corpse).generate()
		legendaries += _inventory_of(corpse).count(&"item.legendary")

	assert_true(legendaries > 50, "Equal weights should split roughly evenly, got %d" % legendaries)


func test_an_item_with_no_rarity_is_never_biased() -> void:
	_item(&"item.plain")
	var corpse := _corpse(_table([_entry(&"item.plain")]))
	var weights: Dictionary[StringName, float] = {&"rarity.legendary": 0.0}
	_loot_of(corpse).rarity_weights = weights

	_loot_of(corpse).generate()

	assert_eq(_inventory_of(corpse).count(&"item.plain"), 1)


# --- Durability degradation policy ----------------------------------------
#
# ItemDefinition.breaks_when_worn_out was declared in M4 and read by nothing
# except its own validator. Gathering and crafting both wore tools down and
# neither destroyed one, so a worn-out axe stayed in the bag forever as an
# entry the harvest loop skipped -- which made durability decorative.

func _axe(breaks: bool) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = &"item.axe"
	definition.display_name = "Axe"
	definition.category = &"item.tool"
	definition.max_stack = 1
	definition.max_durability = 10.0
	definition.breaks_when_worn_out = breaks
	core.register_definition(definition)
	return definition


func _bag_with(definition: ItemDefinition) -> InventoryComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Woodcutter"
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var profile := InventoryProfile.new()
	profile.slot_count = 10
	inventory.profile_override = profile
	entity.add_child(inventory)
	inventory.initialize(EntityContext.create(entity, null, core))
	inventory.add(ItemInstance.create(definition, 1))
	return inventory


func test_wearing_an_item_out_destroys_it_when_its_definition_says_so() -> void:
	var bag := _bag_with(_axe(true))
	var axe := bag.find(&"item.axe")

	bag.wear(axe, 4.0)
	assert_eq(bag.count(&"item.axe"), 1, "Worn, not gone")

	bag.wear(axe, 6.0)

	assert_eq(bag.count(&"item.axe"), 0, "It wore out and was not destroyed")


func test_an_item_that_does_not_break_stays_in_the_bag_at_zero() -> void:
	# A whetstone-able sword: useless until repaired, but still yours.
	var bag := _bag_with(_axe(false))
	var axe := bag.find(&"item.axe")

	bag.wear(axe, 20.0)

	assert_eq(bag.count(&"item.axe"), 1)
	assert_true(axe.is_broken())


func test_breaking_is_announced() -> void:
	var bag := _bag_with(_axe(true))
	var broken: Array[StringName] = []
	bag.item_broke.connect(func(id: StringName) -> void: broken.append(id))

	bag.wear(bag.find(&"item.axe"), 99.0)

	assert_eq(broken, [&"item.axe"] as Array[StringName])


func test_wearing_an_item_with_no_durability_does_nothing() -> void:
	var plain := _item(&"item.rock")
	var bag := _bag_with(plain)
	assert_eq(bag.wear(bag.find(&"item.rock"), 5.0), 0.0)
	assert_eq(bag.count(&"item.rock"), 1)


func test_wearing_somebody_elses_tool_does_not_delete_ours() -> void:
	# Removal is by instance, not by id. Two people holding the same kind of
	# axe must not lose theirs when ours breaks.
	var definition := _axe(true)
	var ours := _bag_with(definition)
	var theirs := ItemInstance.create(definition, 1)

	ours.wear(theirs, 99.0)

	assert_eq(ours.count(&"item.axe"), 1, "Our axe was destroyed by their wear")
