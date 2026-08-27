extends FrameworkTestCase
## Covers the shipped vehicle.tscn and VehicleEventAdapter.
##
## The other M13 suites test the components in isolation, which proves they
## work and proves nothing about whether the scene wires them together. A
## composition-first framework (rule 3) has to test the composition, or the
## exported NodePaths in a [code].tscn[/code] are the one part of the design
## nobody ever checks — and a mis-wired export fails silently, as a car that
## simply never burns fuel.

const VEHICLE_SCENE: String = "res://addons/universal_gameplay/vehicles/vehicle.tscn"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var core: Node = null
var definition: VehicleDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	definition = VehicleFixtures.definition(&"vehicle.scene_test")
	definition.scene = PackedScene.new()
	core.get_definition_registry().register(definition)


## Instantiates the scene with its definition already set, then puts it in the
## tree so the binder's own bind_on_ready path is what runs.
func _spawn() -> Node:
	var scene: PackedScene = load(VEHICLE_SCENE)
	var car := scene.instantiate()
	var binder := car.get_node("DefinitionBinder") as DefinitionBinder
	binder.definition = definition
	add_test_node(car)
	return car


# --- Composition -----------------------------------------------------------

func test_the_scene_carries_every_component_the_plan_lists() -> void:
	# Implementation Plan's VehicleEntity: controller, seats, health, fuel,
	# storage, interaction.
	var car := _spawn()
	assert_not_null(VehicleFixtures.find(car, VehicleComponent))
	assert_not_null(VehicleFixtures.find(car, VehicleControllerAdapter))
	assert_not_null(VehicleFixtures.find(car, SeatComponent))
	assert_not_null(VehicleFixtures.find(car, HealthComponent))
	assert_not_null(VehicleFixtures.find(car, FuelComponent))
	assert_not_null(VehicleFixtures.find(car, InventoryComponent))
	assert_not_null(VehicleFixtures.find(car, InteractionComponent))


func test_the_scene_binds_itself_and_resolves_its_definition() -> void:
	var car := _spawn()
	var vehicle := VehicleFixtures.vehicle_of(car)
	assert_eq(vehicle.get_vehicle(), definition)
	assert_not_null(vehicle.get_handling())


func test_the_exported_wiring_actually_connects() -> void:
	# A mis-wired NodePath is the silent failure this suite exists for.
	var car := _spawn()
	var vehicle := VehicleFixtures.vehicle_of(car)
	assert_eq(vehicle.adapter, VehicleFixtures.find(car, VehicleControllerAdapter))
	assert_eq(vehicle.seats, VehicleFixtures.find(car, SeatComponent))
	assert_eq(vehicle.fuel, VehicleFixtures.find(car, FuelComponent))
	assert_eq(vehicle.health, VehicleFixtures.find(car, HealthComponent))


func test_the_body_adapter_is_pointed_at_the_body() -> void:
	var car := _spawn()
	var adapter := VehicleFixtures.find(car, VehicleBodyAdapter) as VehicleBodyAdapter
	assert_eq(adapter.body, car)


func test_the_boot_is_the_inventory_module_with_a_different_container() -> void:
	# Rule 23: a vehicle's boot is not a new kind of container. The field is
	# named `inventory` rather than `storage` precisely so InventoryComponent's
	# existing resolution finds it -- a field nothing reads is worse than none.
	definition.inventory = ItemFixtures.container(30, 500.0)
	var car := _spawn()
	var boot := VehicleFixtures.find(car, InventoryComponent) as InventoryComponent
	assert_not_null(boot.get_profile())
	assert_eq(boot.get_free_slots(), 30)

	var crate := ItemFixtures.stackable(&"item.crate", 5, 10.0)
	core.get_definition_registry().register(crate)
	assert_ok(boot.add(ItemInstance.create(crate, 3)))
	assert_eq(boot.count(&"item.crate"), 3)


func test_upgrades_are_the_equipment_module_with_a_different_loadout() -> void:
	# A turbo is an item with an EquipmentProfile granting a stat, not a new
	# mechanism. Proven by fitting one and reading the stat back.
	var slot := ItemFixtures.slot(&"slot.engine")
	var fitting := LoadoutProfile.new()
	var slots: Array[EquipmentSlotDefinition] = [slot]
	fitting.slots = slots
	definition.loadout = fitting

	var turbo := ItemFixtures.unique(&"item.turbo")
	turbo.equipment = EquipmentProfile.new()
	var accepts: Array[StringName] = [&"slot.engine"]
	turbo.equipment.slots = accepts
	turbo.equipment.modifiers = [StatModifier.flat(&"stat.power", 25.0)]
	core.get_definition_registry().register(turbo)

	var car := _spawn()
	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = ItemFixtures.stats_profile(10.0)
	car.add_child(stats)
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.stats = stats
	car.add_child(equipment)
	VehicleFixtures.assemble(car, core, definition)

	assert_not_null(equipment.get_loadout(), "the loadout came from the definition")
	assert_ok(equipment.equip(ItemInstance.create(turbo, 1), &"slot.engine"))
	assert_almost_eq(stats.get_value(&"stat.power"), 35.0)


func test_the_scene_gets_its_seats_and_its_tank_from_the_definition() -> void:
	var car := _spawn()
	assert_eq(VehicleFixtures.seats_of(car).get_seat_count(), 2)
	assert_almost_eq(VehicleFixtures.fuel_of(car).get_capacity(), 50.0)


func test_the_scene_drives() -> void:
	var car := _spawn()
	var vehicle := VehicleFixtures.vehicle_of(car)
	assert_ok(vehicle.start_engine())
	vehicle.set_throttle(1.0)
	vehicle.tick(0.5)
	assert_true(vehicle.get_speed() > 0.0)


func test_the_scene_has_a_persistent_identity_prefixed_as_a_vehicle() -> void:
	var car := _spawn()
	var identity := VehicleFixtures.find(car, PersistentIdentity) as PersistentIdentity
	assert_true(identity.get_persistent_id() != &"")
	assert_true(
		String(identity.get_persistent_id()).begins_with("vehicle"),
		"got %s" % identity.get_persistent_id()
	)


func test_the_module_manifest_requires_only_entity() -> void:
	# Everything else degrades: no Input is a car only an AI can drive, no
	# Health is one that cannot be wrecked (rule 31).
	var module: FrameworkModule = load(
		"res://addons/universal_gameplay/vehicles/vehicles_module.gd"
	).new()
	var manifest := module.get_manifest()
	assert_eq(manifest.id, GameplayNames.MODULE_VEHICLES)
	assert_eq(manifest.requires, [GameplayNames.MODULE_ENTITY] as Array[StringName])


# --- The event seam --------------------------------------------------------

func _bus() -> Node:
	return make_autoload(BUS_SCRIPT, "EventBus")


func _heard(bus: Node, event_name: StringName) -> Array:
	var seen: Array = []
	bus.subscribe(event_name, func(event: FrameworkEvent) -> void: seen.append(event))
	return seen


func test_getting_in_becomes_a_cross_feature_fact() -> void:
	var bus := _bus()
	var entered := _heard(bus, GameplayNames.EVENT_VEHICLE_ENTERED)

	var car := _spawn()
	var adapter := (
		VehicleFixtures.find(car, VehicleEventAdapter) as VehicleEventAdapter
	)
	adapter.set_bus(bus)

	var driver := VehicleFixtures.occupant("Thief")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	assert_ok(VehicleFixtures.seats_of(car).enter(driver, &"seat.driver"))

	assert_size(entered, 1)
	assert_eq(entered[0].actor_id, &"thief.instance")
	assert_eq(entered[0].seat_id, &"seat.driver")
	assert_true(entered[0].driver, "stealing a car is entering as the driver")
	assert_true(entered[0].has_vehicle_tag(&"vehicle.car"))


func test_a_passenger_is_announced_as_not_the_driver() -> void:
	# The distinction "steal a car" needs and "get in the van" does not.
	var bus := _bus()
	var entered := _heard(bus, GameplayNames.EVENT_VEHICLE_ENTERED)

	var car := _spawn()
	(VehicleFixtures.find(car, VehicleEventAdapter) as VehicleEventAdapter).set_bus(bus)

	var rider := VehicleFixtures.occupant("Rider")
	add_test_node(rider)
	VehicleFixtures.assemble(rider, core)
	assert_ok(VehicleFixtures.seats_of(car).enter(rider, &"seat.passenger0"))

	assert_size(entered, 1)
	assert_false(entered[0].driver)


func test_getting_out_is_announced_too() -> void:
	var bus := _bus()
	var exited := _heard(bus, GameplayNames.EVENT_VEHICLE_EXITED)

	var car := _spawn()
	(VehicleFixtures.find(car, VehicleEventAdapter) as VehicleEventAdapter).set_bus(bus)

	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	var seats := VehicleFixtures.seats_of(car)
	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_ok(seats.exit(driver))

	assert_size(exited, 1)
	assert_eq(exited[0].seat_id, &"seat.driver")


func test_a_wreck_is_announced() -> void:
	var bus := _bus()
	var wrecked := _heard(bus, GameplayNames.EVENT_VEHICLE_DESTROYED)

	var car := _spawn()
	(VehicleFixtures.find(car, VehicleEventAdapter) as VehicleEventAdapter).set_bus(bus)
	(VehicleFixtures.find(car, HealthComponent) as HealthComponent).kill()

	assert_size(wrecked, 1)
	assert_true(wrecked[0].has_vehicle_tag(&"vehicle.car"))


func test_the_seam_is_deletable() -> void:
	# Rule 10 in one test. Remove the adapter and the vehicle still works;
	# nothing simply hears about it any more.
	var bus := _bus()
	var entered := _heard(bus, GameplayNames.EVENT_VEHICLE_ENTERED)

	var car := _spawn()
	var adapter := VehicleFixtures.find(car, VehicleEventAdapter) as VehicleEventAdapter
	adapter.set_bus(bus)
	adapter.get_parent().remove_child(adapter)
	adapter.free()

	var driver := VehicleFixtures.occupant("Driver")
	add_test_node(driver)
	VehicleFixtures.assemble(driver, core)
	var seats := VehicleFixtures.seats_of(car)

	assert_ok(seats.enter(driver, &"seat.driver"))
	assert_true(seats.contains(driver))
	assert_true(VehicleFixtures.vehicle_of(car).is_running())
	assert_empty(entered, "and the bus hears nothing")
