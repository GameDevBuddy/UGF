extends FrameworkTestCase
## Covers ConsumableProfile, ConsumerComponent and EnvironmentZone: what eating
## something does, and what standing somewhere does.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var entity: Node3D = null
var needs: NeedsComponent = null
var consumer: ConsumerComponent = null
var inventory: InventoryComponent = null
var ration: ItemDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	ration = SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	core.get_definition_registry().register(ration)

	entity = SurvivalFixtures.survivor("Survivor", [SurvivalFixtures.need(&"need.hunger")])
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)

	needs = SurvivalFixtures.find(entity, NeedsComponent) as NeedsComponent
	consumer = SurvivalFixtures.find(entity, ConsumerComponent) as ConsumerComponent
	inventory = SurvivalFixtures.find(entity, InventoryComponent) as InventoryComponent


func _carry(definition: ItemDefinition, quantity: int = 1) -> ItemInstance:
	var instance := ItemInstance.create(definition, quantity)
	assert_ok(inventory.add(instance))
	return inventory.find(definition.id)


# --- Profile ---------------------------------------------------------------

func test_a_profile_reports_what_it_restores() -> void:
	var profile := ration.consumable
	assert_almost_eq(profile.restores(&"need.hunger"), 40.0)
	assert_almost_eq(profile.restores(&"need.thirst"), 0.0)


func test_mismatched_restore_arrays_are_an_error() -> void:
	var profile := ConsumableProfile.new()
	var names: Array[StringName] = [&"need.hunger", &"need.thirst"]
	var amounts: Array[float] = [10.0]
	profile.restores_needs = names
	profile.restore_amounts = amounts
	assert_true(profile.validate().has_errors())


func test_a_consumable_that_does_nothing_is_a_warning() -> void:
	assert_true(ConsumableProfile.new().validate().has_warnings())


# --- Consuming -------------------------------------------------------------

func test_eating_restores_a_need() -> void:
	needs.set_value(&"need.hunger", 20.0)
	var instance := _carry(ration)
	assert_ok(consumer.consume(instance))
	assert_almost_eq(needs.get_value(&"need.hunger"), 60.0)


func test_eating_takes_the_item_out_of_the_bag() -> void:
	_carry(ration, 3)
	assert_ok(consumer.consume_by_id(&"item.ration"))
	assert_eq(inventory.count(&"item.ration"), 2)


func test_a_consumable_that_is_not_consumed_stays() -> void:
	ration.consumable.consumed = false
	_carry(ration, 2)
	assert_ok(consumer.consume_by_id(&"item.ration"))
	assert_eq(inventory.count(&"item.ration"), 2)


func test_something_that_is_not_food_is_refused() -> void:
	var rock := ItemFixtures.unique(&"item.rock")
	core.get_definition_registry().register(rock)
	var instance := _carry(rock)
	assert_err(consumer.consume(instance), &"consume.not_consumable")


func test_eating_what_you_are_not_carrying_is_refused() -> void:
	assert_err(consumer.consume_by_id(&"item.ration"), &"consume.not_carried")


func test_a_consumable_needing_more_than_you_have_is_refused() -> void:
	ration.consumable.uses = 3
	_carry(ration, 2)
	assert_err(consumer.consume_by_id(&"item.ration"), &"consume.not_enough")


func test_a_multi_use_consumable_spends_all_its_uses() -> void:
	ration.consumable.uses = 2
	_carry(ration, 5)
	assert_ok(consumer.consume_by_id(&"item.ration"))
	assert_eq(inventory.count(&"item.ration"), 3)


func test_a_refusal_costs_nothing() -> void:
	# Validate-then-mutate: a meal that could not be eaten is not half eaten.
	ration.consumable.uses = 3
	needs.set_value(&"need.hunger", 10.0)
	_carry(ration, 2)
	assert_err(consumer.consume_by_id(&"item.ration"), &"consume.not_enough")
	assert_eq(inventory.count(&"item.ration"), 2)
	assert_almost_eq(needs.get_value(&"need.hunger"), 10.0)


func test_a_refusal_is_announced_with_its_reason() -> void:
	var refusals: Array = []
	consumer.consumption_refused.connect(
		func(_i: ItemInstance, reason: StringName) -> void: refusals.append(reason)
	)
	assert_err(consumer.consume(null), &"consume.nothing")
	assert_eq(refusals, [&"consume.nothing"])


func test_eating_is_announced() -> void:
	var eaten: Array = []
	consumer.consumed.connect(
		func(instance: ItemInstance, _p: ConsumableProfile) -> void:
			eaten.append(instance.get_definition_id())
	)
	_carry(ration)
	assert_ok(consumer.consume_by_id(&"item.ration"))
	assert_eq(eaten, [&"item.ration"])


func test_a_bandage_heals() -> void:
	var bandage := SurvivalFixtures.meal(&"item.bandage", [], [])
	bandage.consumable.health = 25.0
	core.get_definition_registry().register(bandage)

	var health := SurvivalFixtures.find(entity, HealthComponent) as HealthComponent
	health.set_current(50.0)
	_carry(bandage)
	assert_ok(consumer.consume_by_id(&"item.bandage"))
	assert_almost_eq(health.get_current(), 75.0)


func test_a_bad_mushroom_hurts() -> void:
	var mushroom := SurvivalFixtures.meal(&"item.mushroom", [&"need.hunger"], [10.0])
	mushroom.consumable.health = -30.0
	core.get_definition_registry().register(mushroom)

	var health := SurvivalFixtures.find(entity, HealthComponent) as HealthComponent
	_carry(mushroom)
	assert_ok(consumer.consume_by_id(&"item.mushroom"))
	assert_almost_eq(health.get_current(), 70.0)


func test_a_consumable_applies_its_status_effects() -> void:
	var effect := StatusEffectDefinition.new()
	effect.id = &"effect.well_fed"
	effect.display_name = "Well Fed"
	effect.duration = 60.0
	core.get_definition_registry().register(effect)

	var stew := SurvivalFixtures.meal(&"item.stew", [&"need.hunger"], [50.0])
	var effects: Array[StringName] = [&"effect.well_fed"]
	stew.consumable.effects = effects
	core.get_definition_registry().register(stew)

	_carry(stew)
	assert_ok(consumer.consume_by_id(&"item.stew"))
	var status := (
		SurvivalFixtures.find(entity, StatusEffectComponent) as StatusEffectComponent
	)
	assert_true(status.has_effect(&"effect.well_fed"))


func test_an_entity_with_no_needs_can_still_eat_for_health() -> void:
	# Rule 31: a missing module is a valid configuration, not a crash.
	var simple := Node3D.new()
	simple.name = "Simple"
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	simple.add_child(health)
	var bag := InventoryComponent.new()
	bag.name = "InventoryComponent"
	bag.profile_override = ItemFixtures.container(5)
	simple.add_child(bag)
	var eater := ConsumerComponent.new()
	eater.name = "ConsumerComponent"
	simple.add_child(eater)
	add_test_node(simple)
	SurvivalFixtures.assemble(simple, core)

	health.set_current(40.0)
	ration.consumable.health = 20.0
	assert_ok(bag.add(ItemInstance.create(ration, 1)))
	assert_ok(eater.consume_by_id(&"item.ration"))
	assert_almost_eq(health.get_current(), 60.0)


# --- Environment zones -----------------------------------------------------

func _zone(scale: float = 2.0, need: StringName = &"need.hunger") -> EnvironmentZone:
	var zone := EnvironmentZone.new()
	zone.name = "ColdZone"
	zone.zone_id = &"zone.cave"
	var affects: Array[StringName] = [need]
	var scales: Array[float] = [scale]
	zone.affects_needs = affects
	zone.decay_scales = scales
	return zone


func test_standing_in_a_zone_scales_decay() -> void:
	var zone := _zone(3.0)
	add_test_node(zone)
	assert_true(zone.apply_to(entity))
	needs.tick(10.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 70.0)


func test_leaving_a_zone_restores_the_rate_exactly() -> void:
	# Scaling rather than draining is what makes this exact: a zone that
	# drained directly would leave drift behind every walk in and out.
	var zone := _zone(3.0)
	add_test_node(zone)
	zone.apply_to(entity)
	zone.lift_from(entity)
	needs.tick(10.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 90.0)


func test_two_overlapping_zones_compose() -> void:
	var cave := _zone(2.0)
	var blizzard := _zone(3.0)
	blizzard.name = "Blizzard"
	blizzard.zone_id = &"zone.blizzard"
	add_test_node(cave)
	add_test_node(blizzard)
	cave.apply_to(entity)
	blizzard.apply_to(entity)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 6.0)


func test_leaving_one_of_two_zones_leaves_the_other_alone() -> void:
	var cave := _zone(2.0)
	var blizzard := _zone(3.0)
	blizzard.name = "Blizzard"
	blizzard.zone_id = &"zone.blizzard"
	add_test_node(cave)
	add_test_node(blizzard)
	cave.apply_to(entity)
	blizzard.apply_to(entity)
	cave.lift_from(entity)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 3.0)


func test_shelter_slows_decay() -> void:
	var hut := _zone(0.25)
	add_test_node(hut)
	hut.apply_to(entity)
	needs.tick(10.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 97.5)


func test_entering_twice_is_not_counted_twice() -> void:
	var zone := _zone(2.0)
	add_test_node(zone)
	assert_true(zone.apply_to(entity))
	assert_false(zone.apply_to(entity), "already inside")
	assert_eq(zone.get_occupant_count(), 1)


func test_a_zone_reports_who_is_inside() -> void:
	var zone := _zone()
	add_test_node(zone)
	assert_false(zone.contains(entity))
	zone.apply_to(entity)
	assert_true(zone.contains(entity))
	zone.lift_from(entity)
	assert_false(zone.contains(entity))
	assert_eq(zone.get_occupant_count(), 0)


func test_entering_and_leaving_are_announced() -> void:
	var moves: Array = []
	var zone := _zone()
	add_test_node(zone)
	zone.entity_entered.connect(func(who: Node) -> void: moves.append(["in", String(who.name)]))
	zone.entity_exited.connect(func(who: Node) -> void: moves.append(["out", String(who.name)]))
	zone.apply_to(entity)
	zone.lift_from(entity)
	assert_eq(moves, [["in", "Survivor"], ["out", "Survivor"]])


func test_a_zone_ignores_something_with_no_needs() -> void:
	var rock := Node3D.new()
	rock.name = "Rock"
	add_test_node(rock)
	var zone := _zone()
	add_test_node(zone)
	assert_false(zone.apply_to(rock))


func test_a_zone_can_be_restricted_to_a_group() -> void:
	var zone := _zone()
	zone.only_group = &"survivors"
	add_test_node(zone)
	assert_false(zone.apply_to(entity), "not in the group")
	entity.add_to_group("survivors")
	assert_true(zone.apply_to(entity))


func test_an_unloaded_zone_stops_affecting_who_was_inside() -> void:
	# An unloaded cave that went on freezing people who had walked out of the
	# level would be a leak with a body count.
	var zone := _zone(4.0)
	add_test_node(zone)
	zone.apply_to(entity)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 4.0)
	zone.get_parent().remove_child(zone)
	zone.free()
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 1.0)


func test_a_zone_whose_occupant_was_freed_unloads_cleanly() -> void:
	# Same trap as the vehicle seat: the zone held a typed reference to a
	# component that no longer exists, and lifting on unload crashed on the
	# read rather than skipping it.
	var zone := _zone(3.0)
	add_test_node(zone)
	assert_true(zone.apply_to(entity))

	entity.get_parent().remove_child(entity)
	entity.free()

	zone.get_parent().remove_child(zone)
	zone.free()
	assert_true(true, "unloading a zone over a freed occupant does not crash")


func test_mismatched_zone_arrays_are_an_error() -> void:
	var zone := EnvironmentZone.new()
	var affects: Array[StringName] = [&"need.hunger", &"need.thirst"]
	var scales: Array[float] = [2.0]
	zone.affects_needs = affects
	zone.decay_scales = scales
	assert_true(zone.validate().has_errors())
	zone.free()
