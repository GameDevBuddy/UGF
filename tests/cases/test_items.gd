extends FrameworkTestCase
## Covers ItemDefinition and ItemInstance — chiefly the split between them,
## which is rule 16 and the thing that stops a thousand arrows sharing one
## count.


# --- The split ------------------------------------------------------------

func test_instances_share_one_definition() -> void:
	var definition := ItemFixtures.stackable()
	var first := ItemInstance.create(definition, 5)
	var second := ItemInstance.create(definition, 3)

	assert_eq(first.definition, second.definition, "one shared definition")
	assert_ne(first.quantity, second.quantity, "independent counts")


func test_changing_one_instance_leaves_the_other_alone() -> void:
	var definition := ItemFixtures.weapon()
	var first := ItemInstance.create(definition)
	var second := ItemInstance.create(definition)

	first.degrade(40.0)
	assert_almost_eq(first.durability, 60.0)
	assert_almost_eq(second.durability, 100.0, 0.0001, "the other sword is fine")


func test_every_instance_has_its_own_id() -> void:
	# Equipment removes modifiers by source; two identical rings must unequip
	# independently, which needs a per-instance source.
	var definition := ItemFixtures.weapon()
	var first := ItemInstance.create(definition)
	var second := ItemInstance.create(definition)
	assert_ne(first.get_stack_id(), second.get_stack_id())


func test_the_id_is_stable_across_calls() -> void:
	var instance := ItemInstance.create(ItemFixtures.unique())
	assert_eq(instance.get_stack_id(), instance.get_stack_id())


func test_an_instance_starts_at_full_durability() -> void:
	var instance := ItemInstance.create(ItemFixtures.weapon())
	assert_almost_eq(instance.durability, 100.0)
	assert_almost_eq(instance.get_condition(), 1.0)


func test_an_item_without_durability_reports_full_condition() -> void:
	# So a UI can ask every item and get a sensible answer.
	var instance := ItemInstance.create(ItemFixtures.stackable())
	assert_false(instance.has_durability())
	assert_almost_eq(instance.get_condition(), 1.0)


# --- Stacking -------------------------------------------------------------

func test_two_plain_stacks_of_the_same_item_can_merge() -> void:
	var definition := ItemFixtures.stackable()
	var first := ItemInstance.create(definition, 5)
	var second := ItemInstance.create(definition, 3)
	assert_true(first.can_stack_with(second))


func test_different_items_never_stack() -> void:
	var first := ItemInstance.create(ItemFixtures.stackable(&"item.arrow"))
	var second := ItemInstance.create(ItemFixtures.stackable(&"item.bolt"))
	assert_false(first.can_stack_with(second))


func test_an_unstackable_item_never_stacks() -> void:
	var definition := ItemFixtures.unique()
	assert_false(
		ItemInstance.create(definition).can_stack_with(ItemInstance.create(definition))
	)


func test_items_at_different_durability_do_not_stack() -> void:
	# Merging them would silently discard one side's condition.
	var definition := ItemFixtures.stackable()
	definition.max_durability = 50.0
	var fresh := ItemInstance.create(definition, 1)
	var worn := ItemInstance.create(definition, 1)
	worn.degrade(10.0)
	assert_false(fresh.can_stack_with(worn))


func test_items_with_modifiers_do_not_stack() -> void:
	var definition := ItemFixtures.stackable()
	var plain := ItemInstance.create(definition, 1)
	var enchanted := ItemInstance.create(definition, 1)
	enchanted.modifiers = [StatModifier.flat(&"stat.power", 1.0, &"enchant")]
	assert_false(plain.can_stack_with(enchanted))


func test_items_with_different_custom_state_do_not_stack() -> void:
	var definition := ItemFixtures.stackable()
	var plain := ItemInstance.create(definition, 1)
	var inscribed := ItemInstance.create(definition, 1)
	inscribed.custom_state = {"inscription": "for valour"}
	assert_false(plain.can_stack_with(inscribed))


func test_an_instance_does_not_stack_with_itself() -> void:
	var instance := ItemInstance.create(ItemFixtures.stackable(), 5)
	assert_false(instance.can_stack_with(instance))


func test_merging_moves_what_fits() -> void:
	var definition := ItemFixtures.stackable(&"item.arrow", 20)
	var target := ItemInstance.create(definition, 18)
	var source := ItemInstance.create(definition, 5)

	assert_eq(target.merge_from(source), 2)
	assert_eq(target.quantity, 20)
	assert_eq(source.quantity, 3, "the rest stayed put")


func test_merging_into_a_full_stack_moves_nothing() -> void:
	var definition := ItemFixtures.stackable(&"item.arrow", 20)
	var target := ItemInstance.create(definition, 20)
	var source := ItemInstance.create(definition, 5)
	assert_eq(target.merge_from(source), 0)
	assert_eq(source.quantity, 5)


func test_splitting_takes_units_into_a_new_stack() -> void:
	var instance := ItemInstance.create(ItemFixtures.stackable(), 10)
	var taken := instance.split(4)
	assert_not_null(taken)
	assert_eq(taken.quantity, 4)
	assert_eq(instance.quantity, 6)


func test_splitting_everything_is_refused() -> void:
	# Splitting the whole stack would leave an empty instance behind.
	var instance := ItemInstance.create(ItemFixtures.stackable(), 10)
	assert_null(instance.split(10))
	assert_null(instance.split(0))


func test_a_split_inherits_condition_and_state() -> void:
	var definition := ItemFixtures.stackable()
	var instance := ItemInstance.create(definition, 10)
	instance.custom_state = {"origin": "crafted"}
	var taken := instance.split(3)
	assert_eq(taken.custom_state, {"origin": "crafted"})


# --- Weight and worth -----------------------------------------------------

func test_weight_counts_every_unit() -> void:
	var instance := ItemInstance.create(ItemFixtures.stackable(&"item.arrow", 20, 0.5), 6)
	assert_almost_eq(instance.get_total_weight(), 3.0)


func test_value_counts_every_unit() -> void:
	var instance := ItemInstance.create(ItemFixtures.stackable(), 4)
	assert_almost_eq(instance.get_total_value(), 4.0)


# --- Durability -----------------------------------------------------------

func test_degrading_reduces_condition() -> void:
	var instance := ItemInstance.create(ItemFixtures.weapon())
	assert_almost_eq(instance.degrade(25.0), 25.0)
	assert_almost_eq(instance.get_condition(), 0.75)


func test_durability_stops_at_zero() -> void:
	var instance := ItemInstance.create(ItemFixtures.weapon())
	assert_almost_eq(instance.degrade(500.0), 100.0)
	assert_true(instance.is_broken())


func test_repair_stops_at_the_maximum() -> void:
	var instance := ItemInstance.create(ItemFixtures.weapon())
	instance.degrade(30.0)
	assert_almost_eq(instance.repair(500.0), 30.0)
	assert_almost_eq(instance.durability, 100.0)


func test_degrading_an_item_without_durability_does_nothing() -> void:
	var instance := ItemInstance.create(ItemFixtures.stackable())
	assert_almost_eq(instance.degrade(10.0), 0.0)
	assert_false(instance.is_broken())


# --- Persistence ----------------------------------------------------------

func test_capture_records_the_definition_id_not_a_path() -> void:
	# Rule 32: moving item_sword.tres must not break existing saves.
	var instance := ItemInstance.create(ItemFixtures.weapon(), 1)
	var captured := instance.capture_state()
	assert_eq(captured["definition"], "item.sword")
	assert_has_not(captured.keys(), "resource_path")


func test_an_instance_round_trips_through_a_registry() -> void:
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	var definition := ItemFixtures.weapon()
	core.register_definition(definition)

	var instance := ItemInstance.create(definition)
	instance.degrade(40.0)
	instance.custom_state = {"owner": "guard"}

	var restored := ItemInstance.restore_state(instance.capture_state(), core)
	assert_not_null(restored)
	assert_eq(restored.definition, definition)
	assert_almost_eq(restored.durability, 60.0)
	assert_eq(restored.custom_state, {"owner": "guard"})


func test_restoring_an_unregistered_item_returns_null() -> void:
	# A save from a build that had an item this one does not is a normal case
	# for a modded or updated game, not a corrupt file.
	var core := make_autoload(
		"res://addons/universal_gameplay/core/framework_core.gd", "CoreUnderTest"
	)
	core.bootstrap(FrameworkSettings.new())
	assert_null(ItemInstance.restore_state({"definition": "item.gone"}, core))


func test_restoring_without_a_registry_returns_null() -> void:
	assert_null(ItemInstance.restore_state({"definition": "item.sword"}, null))


# --- Validation -----------------------------------------------------------

func test_a_well_formed_item_validates_clean() -> void:
	var result := ItemFixtures.stackable().validate()
	assert_false(result.has_errors(), result.format_report())
	assert_false(result.has_warnings(), result.format_report())


func test_an_item_with_no_category_is_flagged() -> void:
	var definition := ItemFixtures.stackable()
	definition.category = &""
	assert_true(definition.validate().has_warnings())


func test_negative_weight_is_an_error() -> void:
	var definition := ItemFixtures.stackable()
	definition.weight = -1.0
	assert_true(definition.validate().has_errors())


func test_a_stackable_item_with_durability_is_an_error() -> void:
	# Two units at different conditions cannot share one number, so one side's
	# state would be silently lost on every merge.
	var definition := ItemFixtures.stackable()
	definition.max_durability = 50.0
	var result := definition.validate()
	assert_true(result.has_errors())
	assert_true(result.format_report().contains("silently lost"))


func test_an_item_with_no_scene_cannot_be_a_pickup() -> void:
	var definition := ItemFixtures.stackable()
	definition.scene = null
	assert_true(definition.validate().has_errors())


func test_a_stackable_equippable_item_is_flagged() -> void:
	var definition := ItemFixtures.weapon()
	definition.max_stack = 5
	definition.max_durability = 0.0
	assert_true(definition.validate().has_warnings())
