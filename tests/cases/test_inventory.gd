extends FrameworkTestCase
## Covers InventoryComponent: stacking, capacity, filters, and the atomicity
## that stops a failed transfer from destroying items.

var entity: Node = null
var inventory: InventoryComponent = null
var arrow: ItemDefinition = null
var trinket: ItemDefinition = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	arrow = ItemFixtures.stackable(&"item.arrow", 20, 0.1)
	trinket = ItemFixtures.unique(&"item.trinket", 1.0)

	inventory = InventoryComponent.new()
	inventory.profile_override = ItemFixtures.container(10)
	entity.add_child(inventory)
	inventory.initialize(EntityContext.create(entity))


func _other(slots: int = 10, weight: float = 0.0) -> InventoryComponent:
	var other_entity := add_test_node(Node.new())
	var other := InventoryComponent.new()
	other.profile_override = ItemFixtures.container(slots, weight)
	other_entity.add_child(other)
	other.initialize(EntityContext.create(other_entity))
	return other


# --- Storing --------------------------------------------------------------

func test_a_new_container_is_empty() -> void:
	assert_true(inventory.is_empty())
	assert_eq(inventory.get_used_slots(), 0)


func test_adding_stores_the_item() -> void:
	assert_ok(inventory.add(ItemInstance.create(arrow, 5)))
	assert_eq(inventory.count(&"item.arrow"), 5)
	assert_eq(inventory.get_used_slots(), 1)


func test_adding_is_announced() -> void:
	var seen: Array = []
	inventory.item_added.connect(
		func(i: ItemInstance, q: int) -> void: seen.append([i.get_definition_id(), q])
	)
	inventory.add(ItemInstance.create(arrow, 3))
	assert_size(seen, 1)
	assert_eq(seen[0][1], 3)


func test_a_second_stack_fills_the_first_before_taking_a_slot() -> void:
	# Otherwise an inventory fragments into twenty single arrows when it had
	# room in a stack all along.
	inventory.add(ItemInstance.create(arrow, 15))
	inventory.add(ItemInstance.create(arrow, 3))
	assert_eq(inventory.get_used_slots(), 1)
	assert_eq(inventory.count(&"item.arrow"), 18)


func test_overflowing_a_stack_takes_another_slot() -> void:
	inventory.add(ItemInstance.create(arrow, 25))
	assert_eq(inventory.get_used_slots(), 2)
	assert_eq(inventory.count(&"item.arrow"), 25)


func test_unstackable_items_each_take_a_slot() -> void:
	inventory.add(ItemInstance.create(trinket))
	inventory.add(ItemInstance.create(trinket))
	assert_eq(inventory.get_used_slots(), 2)


func test_adding_null_fails_cleanly() -> void:
	assert_err(inventory.add(null), &"inventory.null_item")


# --- Capacity -------------------------------------------------------------

func test_a_full_container_refuses() -> void:
	for _i in range(10):
		inventory.add(ItemInstance.create(trinket))
	assert_eq(inventory.get_used_slots(), 10)
	assert_err(inventory.add(ItemInstance.create(trinket)), &"inventory.no_room")


func test_a_refused_add_stores_nothing() -> void:
	# All or nothing: a partial store that then fails is how items vanish.
	for _i in range(10):
		inventory.add(ItemInstance.create(trinket))
	var overflow := ItemInstance.create(arrow, 5)
	assert_err(inventory.add(overflow), &"inventory.no_room")
	assert_eq(overflow.quantity, 5, "the caller still has all of it")
	assert_eq(inventory.count(&"item.arrow"), 0)


func test_a_weight_limit_is_enforced() -> void:
	var heavy := _other(100, 5.0)
	assert_ok(heavy.add(ItemInstance.create(arrow, 40)))
	assert_almost_eq(heavy.get_total_weight(), 4.0)
	assert_err(heavy.add(ItemInstance.create(arrow, 20)), &"inventory.no_room")


func test_weight_and_slots_are_both_respected() -> void:
	var tiny := _other(1, 1.0)
	assert_err(tiny.add(ItemInstance.create(arrow, 20)), &"inventory.no_room")
	assert_ok(tiny.add(ItemInstance.create(arrow, 10)))


func test_an_unlimited_container_never_fills() -> void:
	var vault := _other(0, 0.0)
	for _i in range(50):
		assert_ok(vault.add(ItemInstance.create(trinket)))
	assert_eq(vault.get_used_slots(), 50)
	assert_eq(vault.get_free_slots(), -1)


func test_space_for_reports_what_would_fit() -> void:
	inventory.add(ItemInstance.create(arrow, 15))
	# Five left in the open stack, plus nine free slots of twenty.
	assert_eq(inventory.space_for(ItemInstance.create(arrow, 1)), 5 + 9 * 20)


func test_add_up_to_takes_what_fits_and_leaves_the_rest() -> void:
	var tiny := _other(1, 0.0)
	var stack := ItemInstance.create(arrow, 30)
	assert_eq(tiny.add_up_to(stack), 20)
	assert_eq(stack.quantity, 10, "the rest stays with the caller")
	assert_eq(tiny.count(&"item.arrow"), 20)


# --- Filters --------------------------------------------------------------

func test_a_container_can_refuse_a_category() -> void:
	var profile := ItemFixtures.container(10)
	profile.rejected_categories = [&"item.ammo"]
	var quiver := _other()
	quiver.profile_override = profile
	quiver.initialize(EntityContext.create(entity))
	assert_err(quiver.add(ItemInstance.create(arrow, 1)), &"inventory.rejected")


func test_a_container_can_accept_only_one_category() -> void:
	var profile := ItemFixtures.container(10)
	profile.accepted_categories = [&"item.ammo"]
	var quiver := _other()
	quiver.profile_override = profile
	quiver.initialize(EntityContext.create(entity))
	assert_ok(quiver.add(ItemInstance.create(arrow, 1)))
	assert_err(quiver.add(ItemInstance.create(trinket)), &"inventory.rejected")


func test_rejection_beats_acceptance() -> void:
	# So a container can accept everything except one kind.
	var profile := ItemFixtures.container(10)
	profile.accepted_categories = [&"item.ammo"]
	profile.rejected_categories = [&"item.ammo"]
	assert_false(profile.accepts(arrow))


func test_a_contradictory_filter_is_an_error() -> void:
	var profile := ItemFixtures.container(10)
	profile.accepted_categories = [&"item.ammo"]
	profile.rejected_categories = [&"item.ammo"]
	assert_true(profile.validate().has_errors())


func test_being_refused_and_being_full_are_different_failures() -> void:
	var profile := ItemFixtures.container(10)
	profile.rejected_categories = [&"item.ammo"]
	var quiver := _other()
	quiver.profile_override = profile
	quiver.initialize(EntityContext.create(entity))

	var refused := quiver.add(ItemInstance.create(arrow, 1))
	assert_true(refused.failed_with(&"inventory.rejected"))
	assert_false(refused.failed_with(&"inventory.no_room"))


# --- Removing -------------------------------------------------------------

func test_removing_reduces_the_count() -> void:
	inventory.add(ItemInstance.create(arrow, 10))
	assert_ok(inventory.remove(&"item.arrow", 4))
	assert_eq(inventory.count(&"item.arrow"), 6)


func test_removing_more_than_held_removes_nothing() -> void:
	inventory.add(ItemInstance.create(arrow, 3))
	assert_err(inventory.remove(&"item.arrow", 5), &"inventory.insufficient")
	assert_eq(inventory.count(&"item.arrow"), 3, "untouched")


func test_removing_across_several_stacks() -> void:
	inventory.add(ItemInstance.create(arrow, 25))
	assert_eq(inventory.get_used_slots(), 2)
	assert_ok(inventory.remove(&"item.arrow", 22))
	assert_eq(inventory.count(&"item.arrow"), 3)


func test_an_emptied_stack_frees_its_slot() -> void:
	inventory.add(ItemInstance.create(arrow, 5))
	inventory.remove(&"item.arrow", 5)
	assert_eq(inventory.get_used_slots(), 0)


func test_taking_hands_back_a_separate_instance() -> void:
	inventory.add(ItemInstance.create(arrow, 10))
	var taken := inventory.take(&"item.arrow", 4)
	assert_ok(taken)
	assert_eq((taken.payload as ItemInstance).quantity, 4)
	assert_eq(inventory.count(&"item.arrow"), 6)


func test_removing_an_instance_that_is_not_held_fails() -> void:
	assert_err(
		inventory.remove_instance(ItemInstance.create(arrow, 1)), &"inventory.not_held"
	)


# --- Transfer: the atomicity that matters --------------------------------

func test_transfer_moves_items_between_containers() -> void:
	var chest := _other()
	inventory.add(ItemInstance.create(arrow, 10))
	assert_ok(inventory.transfer_to(chest, &"item.arrow", 6))
	assert_eq(inventory.count(&"item.arrow"), 4)
	assert_eq(chest.count(&"item.arrow"), 6)


func test_a_transfer_that_will_not_fit_leaves_the_source_intact() -> void:
	# Half-moving a stack and failing is how items get destroyed, and no
	# amount of care at the call site fixes it.
	var tiny := _other(1, 0.0)
	tiny.add(ItemInstance.create(trinket))

	inventory.add(ItemInstance.create(arrow, 10))
	var result := inventory.transfer_to(tiny, &"item.arrow", 10)

	assert_err(result, &"inventory.no_room")
	assert_eq(inventory.count(&"item.arrow"), 10, "source untouched")
	assert_eq(tiny.count(&"item.arrow"), 0, "destination untouched")


func test_a_transfer_the_destination_refuses_leaves_both_intact() -> void:
	var profile := ItemFixtures.container(10)
	profile.rejected_categories = [&"item.ammo"]
	var quiver := _other()
	quiver.profile_override = profile
	quiver.initialize(EntityContext.create(entity))

	inventory.add(ItemInstance.create(arrow, 5))
	assert_err(inventory.transfer_to(quiver, &"item.arrow", 5), &"inventory.rejected")
	assert_eq(inventory.count(&"item.arrow"), 5)


func test_transferring_more_than_held_fails_before_touching_anything() -> void:
	var chest := _other()
	inventory.add(ItemInstance.create(arrow, 3))
	assert_err(inventory.transfer_to(chest, &"item.arrow", 5), &"inventory.insufficient")
	assert_eq(inventory.count(&"item.arrow"), 3)
	assert_true(chest.is_empty())


func test_transferring_to_null_fails() -> void:
	assert_err(inventory.transfer_to(null, &"item.arrow", 1), &"inventory.null_destination")


func test_transferring_into_itself_fails() -> void:
	inventory.add(ItemInstance.create(arrow, 5))
	assert_err(
		inventory.transfer_to(inventory, &"item.arrow", 1), &"inventory.same_container"
	)
	assert_eq(inventory.count(&"item.arrow"), 5)


func test_no_items_are_created_or_destroyed_by_a_transfer() -> void:
	var chest := _other()
	inventory.add(ItemInstance.create(arrow, 17))
	var before := inventory.count(&"item.arrow") + chest.count(&"item.arrow")
	inventory.transfer_to(chest, &"item.arrow", 9)
	var after := inventory.count(&"item.arrow") + chest.count(&"item.arrow")
	assert_eq(after, before)


# --- Persistence ----------------------------------------------------------

func test_inventory_is_persistent() -> void:
	assert_true(inventory.is_persistent())


func test_contents_round_trip_through_a_registry() -> void:
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	core.register_definition(arrow)
	core.register_definition(trinket)

	inventory.add(ItemInstance.create(arrow, 12))
	inventory.add(ItemInstance.create(trinket))
	var captured := inventory.capture_state()

	var restored_entity := add_test_node(Node.new())
	var restored := InventoryComponent.new()
	restored.profile_override = ItemFixtures.container(10)
	restored_entity.add_child(restored)
	restored.initialize(EntityContext.create(restored_entity, null, core))
	restored.restore_state(captured)

	assert_eq(restored.count(&"item.arrow"), 12)
	assert_eq(restored.count(&"item.trinket"), 1)


func test_restore_drops_items_whose_definitions_are_gone() -> void:
	# A save from a build that had an item this one does not must load, not
	# fail: that is a normal case for a modded or updated game.
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	core.register_definition(arrow)

	var restored_entity := add_test_node(Node.new())
	var restored := InventoryComponent.new()
	restored.profile_override = ItemFixtures.container(10)
	restored_entity.add_child(restored)
	restored.initialize(EntityContext.create(restored_entity, null, core))
	restored.restore_state({
		"items": [
			{"definition": "item.arrow", "quantity": 3},
			{"definition": "item.removed_in_this_build", "quantity": 1},
		]
	})

	assert_eq(restored.count(&"item.arrow"), 3)
	assert_eq(restored.get_used_slots(), 1, "the unknown item was dropped")


func test_restore_tolerates_an_empty_save() -> void:
	inventory.add(ItemInstance.create(arrow, 5))
	inventory.restore_state({})
	assert_true(inventory.is_empty())
