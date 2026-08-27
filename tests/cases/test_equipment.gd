extends FrameworkTestCase
## Covers EquipmentComponent, and holds the M4 exit gate: the world pickup ->
## inventory -> equip -> drop round trip.

var entity: Node = null
var stats: StatsComponent = null
var inventory: InventoryComponent = null
var equipment: EquipmentComponent = null
var sword: ItemDefinition = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	sword = ItemFixtures.weapon(&"item.sword", 5.0)

	stats = StatsComponent.new()
	stats.profile_override = ItemFixtures.stats_profile(10.0)
	stats.auto_tick = false
	entity.add_child(stats)

	inventory = InventoryComponent.new()
	inventory.profile_override = ItemFixtures.container(10)
	entity.add_child(inventory)

	equipment = EquipmentComponent.new()
	equipment.loadout_override = ItemFixtures.loadout()
	equipment.stats = stats
	equipment.inventory = inventory
	entity.add_child(equipment)

	for component in [stats, inventory, equipment]:
		component.initialize(EntityContext.create(entity))


# --- Equipping ------------------------------------------------------------

func test_equipping_fills_the_slot() -> void:
	var instance := ItemInstance.create(sword)
	assert_ok(equipment.equip(instance))
	assert_true(equipment.is_equipped(&"slot.main_hand"))
	assert_eq(equipment.get_equipped(&"slot.main_hand"), instance)


func test_equipping_grants_its_modifiers() -> void:
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0)
	equipment.equip(ItemInstance.create(sword))
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0)


func test_unequipping_takes_the_modifiers_back() -> void:
	equipment.equip(ItemInstance.create(sword))
	assert_ok(equipment.unequip(&"slot.main_hand"))
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0)


func test_equipping_is_announced() -> void:
	var seen: Array = []
	equipment.equipped.connect(
		func(slot: StringName, _i: ItemInstance) -> void: seen.append(slot)
	)
	equipment.equip(ItemInstance.create(sword))
	assert_eq(seen, [&"slot.main_hand"])


func test_the_slot_is_chosen_when_none_is_given() -> void:
	equipment.equip(ItemInstance.create(sword))
	assert_true(equipment.is_equipped(&"slot.main_hand"))


func test_an_unequippable_item_is_refused() -> void:
	assert_err(
		equipment.equip(ItemInstance.create(ItemFixtures.stackable())),
		&"equipment.not_equippable"
	)


func test_equipping_to_a_slot_the_entity_lacks_fails() -> void:
	assert_err(
		equipment.equip(ItemInstance.create(sword), &"slot.tail"),
		&"equipment.unknown_slot"
	)


func test_equipping_to_a_slot_the_item_does_not_fit_fails() -> void:
	assert_err(
		equipment.equip(ItemInstance.create(sword), &"slot.off_hand"),
		&"equipment.wrong_slot"
	)


func test_equipping_null_fails_cleanly() -> void:
	assert_err(equipment.equip(null), &"equipment.null_item")


func test_unequipping_an_empty_slot_fails() -> void:
	assert_err(equipment.unequip(&"slot.main_hand"), &"equipment.slot_empty")


# --- The per-instance sourcing that matters ------------------------------

func test_two_identical_items_unequip_independently() -> void:
	# Source modifiers by definition id instead and taking off one ring strips
	# both — a bug that only appears when a player wears two of something.
	var ring := ItemFixtures.weapon(&"item.ring", 3.0, &"slot.main_hand")
	ring.equipment.slots = [&"slot.main_hand", &"slot.off_hand"]
	ring.max_durability = 0.0

	equipment.equip(ItemInstance.create(ring), &"slot.main_hand")
	equipment.equip(ItemInstance.create(ring), &"slot.off_hand")
	assert_almost_eq(stats.get_value(&"stat.power"), 16.0, 0.0001, "both rings")

	equipment.unequip(&"slot.main_hand")
	assert_almost_eq(
		stats.get_value(&"stat.power"), 13.0, 0.0001, "the other ring survived"
	)


func test_an_instance_modifier_is_granted_alongside_the_profile_one() -> void:
	var instance := ItemInstance.create(sword)
	instance.modifiers = [StatModifier.flat(&"stat.power", 2.0, &"enchant")]
	equipment.equip(instance)
	assert_almost_eq(stats.get_value(&"stat.power"), 17.0, 0.0001, "5 + 2")


func test_an_instance_modifier_comes_off_with_the_item() -> void:
	var instance := ItemInstance.create(sword)
	instance.modifiers = [StatModifier.flat(&"stat.power", 2.0, &"enchant")]
	equipment.equip(instance)
	equipment.unequip(&"slot.main_hand")
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0)


# --- Swapping and blocking ------------------------------------------------

func test_equipping_over_an_occupied_slot_swaps() -> void:
	var first := ItemInstance.create(sword)
	var second := ItemInstance.create(ItemFixtures.weapon(&"item.axe", 8.0))
	equipment.equip(first)
	assert_ok(equipment.equip(second, &"slot.main_hand"))

	assert_eq(equipment.get_equipped(&"slot.main_hand"), second)
	assert_true(inventory.contains(first), "the old one went to the bag")
	assert_almost_eq(stats.get_value(&"stat.power"), 18.0, 0.0001, "only the axe")


func test_a_two_handed_weapon_blocks_the_off_hand() -> void:
	equipment.equip(ItemInstance.create(ItemFixtures.two_handed()))
	assert_true(equipment.is_blocked(&"slot.off_hand"))
	assert_false(equipment.is_slot_free(&"slot.off_hand"))
	assert_eq(equipment.get_blocking_slot(&"slot.off_hand"), &"slot.main_hand")


func test_a_blocked_slot_refuses_items() -> void:
	var shield := ItemFixtures.weapon(&"item.shield", 2.0, &"slot.off_hand")
	equipment.equip(ItemInstance.create(ItemFixtures.two_handed()))
	assert_err(
		equipment.equip(ItemInstance.create(shield), &"slot.off_hand"),
		&"equipment.slot_blocked"
	)


func test_unequipping_a_two_hander_frees_the_off_hand() -> void:
	equipment.equip(ItemInstance.create(ItemFixtures.two_handed()))
	equipment.unequip(&"slot.main_hand")
	assert_false(equipment.is_blocked(&"slot.off_hand"))
	assert_true(equipment.is_slot_free(&"slot.off_hand"))


func test_a_two_hander_displaces_what_is_in_the_off_hand() -> void:
	var shield := ItemFixtures.weapon(&"item.shield", 2.0, &"slot.off_hand")
	var shield_instance := ItemInstance.create(shield)
	equipment.equip(shield_instance, &"slot.off_hand")
	assert_almost_eq(stats.get_value(&"stat.power"), 12.0)

	equipment.equip(ItemInstance.create(ItemFixtures.two_handed()))
	assert_true(inventory.contains(shield_instance), "the shield went to the bag")
	assert_almost_eq(stats.get_value(&"stat.power"), 22.0, 0.0001, "only the greatsword")


# --- Requirements ---------------------------------------------------------

func test_an_unmet_stat_requirement_refuses_the_item() -> void:
	var heavy := ItemFixtures.weapon(&"item.warhammer", 20.0)
	heavy.equipment.stat_requirements = {&"stat.power": 50.0}
	assert_err(
		equipment.equip(ItemInstance.create(heavy)), &"equipment.requirement_not_met"
	)
	assert_false(equipment.is_equipped(&"slot.main_hand"))


func test_a_met_requirement_allows_it() -> void:
	var heavy := ItemFixtures.weapon(&"item.warhammer", 20.0)
	heavy.equipment.stat_requirements = {&"stat.power": 10.0}
	assert_ok(equipment.equip(ItemInstance.create(heavy)))


func test_a_stat_the_entity_lacks_entirely_fails_the_requirement() -> void:
	# A crate cannot wear plate armour by virtue of having no strength.
	var heavy := ItemFixtures.weapon(&"item.warhammer", 20.0)
	heavy.equipment.stat_requirements = {&"stat.charisma": 1.0}
	assert_err(equipment.equip(ItemInstance.create(heavy)), &"equipment.missing_stat")


func test_a_required_tag_is_checked_against_the_definition() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.mage"
	definition.tags = [&"class.mage"]
	definition.scene = PackedScene.new()

	var tagged := EquipmentComponent.new()
	tagged.loadout_override = ItemFixtures.loadout()
	tagged.stats = stats
	entity.add_child(tagged)
	tagged.initialize(EntityContext.create(entity, definition))

	var staff := ItemFixtures.weapon(&"item.staff", 4.0)
	staff.equipment.required_tags = [&"class.mage"]
	assert_ok(tagged.equip(ItemInstance.create(staff)))

	staff.equipment.required_tags = [&"class.warrior"]
	assert_err(
		tagged.equip(ItemInstance.create(staff), &"slot.main_hand"),
		&"equipment.missing_tag"
	)


# --- Degradation without stats or inventory ------------------------------

func test_equipment_works_with_no_stats() -> void:
	# A mannequin wears things and grants nothing.
	var bare_entity := add_test_node(Node.new())
	var bare := EquipmentComponent.new()
	bare.loadout_override = ItemFixtures.loadout()
	bare_entity.add_child(bare)
	bare.initialize(EntityContext.create(bare_entity))
	assert_ok(bare.equip(ItemInstance.create(sword)))


func test_equipment_works_with_no_inventory() -> void:
	# A fixed loadout that never goes in a bag: the caller hands over the
	# instance and gets it back.
	var fixed_entity := add_test_node(Node.new())
	var fixed := EquipmentComponent.new()
	fixed.loadout_override = ItemFixtures.loadout()
	fixed_entity.add_child(fixed)
	fixed.initialize(EntityContext.create(fixed_entity))

	fixed.equip(ItemInstance.create(sword))
	var removed := fixed.unequip(&"slot.main_hand")
	assert_ok(removed)
	assert_not_null(removed.payload)


func test_unequipping_fails_when_there_is_nowhere_to_put_it() -> void:
	# Silently destroying gear because the bag was full is not recoverable.
	var tiny := ItemFixtures.container(1)
	inventory.profile_override = tiny
	inventory.initialize(EntityContext.create(entity))
	inventory.add(ItemInstance.create(ItemFixtures.unique(&"item.rock")))

	equipment.equip(ItemInstance.create(sword))
	assert_err(equipment.unequip(&"slot.main_hand"), &"equipment.no_room_to_stow")
	assert_true(equipment.is_equipped(&"slot.main_hand"), "still worn, not lost")


# --- Starting loadout -----------------------------------------------------

func test_starting_items_are_equipped_on_initialisation() -> void:
	var loadout := ItemFixtures.loadout()
	loadout.starting_items = {&"slot.main_hand": sword}

	var guard_entity := add_test_node(Node.new())
	var guard := EquipmentComponent.new()
	guard.loadout_override = loadout
	guard_entity.add_child(guard)
	guard.initialize(EntityContext.create(guard_entity))

	assert_true(guard.is_equipped(&"slot.main_hand"))


func test_starting_items_can_be_turned_off() -> void:
	var loadout := ItemFixtures.loadout()
	loadout.starting_items = {&"slot.main_hand": sword}

	var guard_entity := add_test_node(Node.new())
	var guard := EquipmentComponent.new()
	guard.loadout_override = loadout
	guard.equip_starting_items = false
	guard_entity.add_child(guard)
	guard.initialize(EntityContext.create(guard_entity))

	assert_false(guard.is_equipped(&"slot.main_hand"))


func test_a_starting_item_in_the_wrong_slot_is_an_error() -> void:
	var loadout := ItemFixtures.loadout()
	loadout.starting_items = {&"slot.off_hand": sword}
	assert_true(loadout.validate().has_errors())


# --- Persistence ----------------------------------------------------------

func test_equipment_is_persistent() -> void:
	assert_true(equipment.is_persistent())


func test_worn_items_round_trip() -> void:
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	core.register_definition(sword)

	var instance := ItemInstance.create(sword)
	instance.degrade(30.0)
	equipment.equip(instance)
	var captured := equipment.capture_state()

	var restored_entity := add_test_node(Node.new())
	var restored_stats := StatsComponent.new()
	restored_stats.profile_override = ItemFixtures.stats_profile(10.0)
	restored_stats.auto_tick = false
	restored_entity.add_child(restored_stats)
	var restored := EquipmentComponent.new()
	restored.loadout_override = ItemFixtures.loadout()
	restored.stats = restored_stats
	restored_entity.add_child(restored)
	restored_stats.initialize(EntityContext.create(restored_entity, null, core))
	restored.initialize(EntityContext.create(restored_entity, null, core))
	restored.restore_state(captured)

	assert_true(restored.is_equipped(&"slot.main_hand"))
	assert_almost_eq(
		restored.get_equipped(&"slot.main_hand").durability, 70.0, 0.0001
	)
	assert_almost_eq(restored_stats.get_value(&"stat.power"), 15.0, 0.0001, "granted once")


func test_modifiers_are_not_saved() -> void:
	# They are rebuilt from the profile on restore; saving them too would grant
	# every bonus twice on load.
	equipment.equip(ItemInstance.create(sword))
	assert_has_not(equipment.capture_state().keys(), "modifiers")


# --- The M4 exit gate -----------------------------------------------------

func test_world_pickup_to_inventory_to_equip_to_drop() -> void:
	# The round trip the milestone is defined by, start to finish, with the
	# sword's condition surviving every leg of it.
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	core.register_definition(sword)

	# 1. A sword is lying in the world.
	var ground := add_test_node(Node.new())
	var pickup := ItemPickup.new()
	pickup.item = sword
	pickup.free_when_empty = false
	ground.add_child(pickup)
	pickup.initialize(EntityContext.create(ground, null, core))
	pickup.get_instance().degrade(25.0)
	assert_false(pickup.is_empty())

	# 2. Picked up into the inventory.
	assert_ok(pickup.take_by(inventory))
	assert_true(pickup.is_empty(), "the ground is clear")
	assert_eq(inventory.count(&"item.sword"), 1)

	# 3. Equipped out of the inventory.
	var held := inventory.find(&"item.sword")
	assert_ok(equipment.equip(held))
	assert_true(equipment.is_equipped(&"slot.main_hand"))
	assert_almost_eq(stats.get_value(&"stat.power"), 15.0, 0.0001, "the sword counts")
	assert_false(inventory.contains(held), "it left the bag when it went on")

	# 4. Dropped back into the world.
	var removed := equipment.unequip_to_hand(&"slot.main_hand")
	assert_ok(removed)
	assert_almost_eq(stats.get_value(&"stat.power"), 10.0, 0.0001, "and stops counting")

	var dropped := removed.payload as ItemInstance
	assert_almost_eq(dropped.durability, 75.0, 0.0001, "condition survived the trip")

	var world_entity := ItemPickup.spawn(dropped)
	assert_not_null(world_entity, "it is back on the ground")
	world_entity.free()


func test_a_pickup_takes_what_fits_and_leaves_the_rest() -> void:
	# The one place the framework prefers a partial operation to an atomic one:
	# nothing is destroyed either way, and nine of ten arrows with the tenth
	# still visible is more legible than refusing the lot.
	var arrow := ItemFixtures.stackable(&"item.arrow", 20, 0.1)
	var tiny_entity := add_test_node(Node.new())
	var tiny := InventoryComponent.new()
	tiny.profile_override = ItemFixtures.container(1)
	tiny_entity.add_child(tiny)
	tiny.initialize(EntityContext.create(tiny_entity))

	var ground := add_test_node(Node.new())
	var pickup := ItemPickup.new()
	pickup.item = arrow
	pickup.quantity = 30
	pickup.free_when_empty = false
	ground.add_child(pickup)
	pickup.initialize(EntityContext.create(ground))

	assert_ok(pickup.take_by(tiny))
	assert_eq(tiny.count(&"item.arrow"), 20)
	assert_eq(pickup.get_instance().quantity, 10, "ten left on the ground")


func test_a_pickup_into_a_full_bag_takes_nothing() -> void:
	var full_entity := add_test_node(Node.new())
	var full := InventoryComponent.new()
	full.profile_override = ItemFixtures.container(1)
	full_entity.add_child(full)
	full.initialize(EntityContext.create(full_entity))
	full.add(ItemInstance.create(ItemFixtures.unique(&"item.rock")))

	var ground := add_test_node(Node.new())
	var pickup := ItemPickup.new()
	pickup.item = sword
	pickup.free_when_empty = false
	ground.add_child(pickup)
	pickup.initialize(EntityContext.create(ground))

	assert_err(pickup.take_by(full), &"pickup.no_room")
	assert_false(pickup.is_empty(), "still on the ground")
