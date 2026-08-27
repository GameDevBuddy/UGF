extends FrameworkTestCase
## Covers WeaponComponent: ammunition, reloading, cadence and aim drift.

var entity: Node3D = null
var weapon: WeaponComponent = null


func before_each() -> void:
	entity = add_test_node(CombatFixtures.fighter("Shooter")) as Node3D
	weapon = CombatFixtures.weapon_of(entity)
	weapon.profile_override = CombatFixtures.rifle(20.0, 5)
	CombatFixtures.assemble(entity)


# --- Adopting a weapon ----------------------------------------------------

func test_a_fresh_weapon_starts_loaded() -> void:
	assert_eq(weapon.get_magazine(), 5)
	assert_eq(weapon.get_reserve(), 10)
	assert_true(weapon.has_weapon())


func test_an_unarmed_component_refuses_to_fire() -> void:
	var unarmed := add_test_node(CombatFixtures.fighter("Brawler")) as Node3D
	CombatFixtures.assemble(unarmed)
	assert_err(CombatFixtures.weapon_of(unarmed).can_fire(), &"weapon.none")


func test_handing_over_a_weapon_announces_it() -> void:
	var announced: Array[WeaponProfile] = []
	weapon.weapon_changed.connect(func(p: WeaponProfile) -> void: announced.append(p))
	var sword := CombatFixtures.sword()
	weapon.set_profile(sword, &"item.sword")
	assert_eq(weapon.get_profile(), sword)
	assert_eq(weapon.get_weapon_id(), &"item.sword")
	assert_size(announced, 1)


func test_a_melee_weapon_has_no_ammunition_to_track() -> void:
	weapon.set_profile(CombatFixtures.sword())
	assert_true(weapon.has_unlimited_ammo())
	assert_false(weapon.is_magazine_empty())
	assert_ok(weapon.can_fire())


# --- Firing ---------------------------------------------------------------

func test_a_shot_spends_a_round() -> void:
	assert_ok(weapon.consume_shot())
	assert_eq(weapon.get_magazine(), 4)


func test_the_magazine_runs_out() -> void:
	for shot in 5:
		weapon.consume_shot()
		weapon.tick(1.0)
	assert_eq(weapon.get_magazine(), 0)
	assert_true(weapon.is_magazine_empty())
	assert_err(weapon.can_fire(), &"weapon.empty")


func test_running_dry_is_announced() -> void:
	var emptied: Array[int] = []
	weapon.magazine_emptied.connect(func() -> void: emptied.append(1))
	for shot in 5:
		weapon.consume_shot()
		weapon.tick(1.0)
	assert_size(emptied, 1)


func test_the_rate_of_fire_is_enforced() -> void:
	assert_ok(weapon.consume_shot())
	assert_err(weapon.can_fire(), &"weapon.cooling_down")
	weapon.tick(0.15)
	assert_ok(weapon.can_fire())


func test_an_unlimited_reserve_never_runs_out() -> void:
	var profile := CombatFixtures.rifle()
	profile.ammo.reserve_capacity = -1
	weapon.set_profile(profile)
	assert_eq(weapon.get_reserve(), -1)
	weapon.consume_shot()
	weapon.tick(1.0)
	assert_ok(weapon.reload())
	weapon.tick(profile.ammo.reload_time)
	assert_eq(weapon.get_magazine(), profile.ammo.magazine_size)


func test_firing_is_announced_with_the_attack() -> void:
	var fired: Array[AttackDefinition] = []
	weapon.fired.connect(func(a: AttackDefinition) -> void: fired.append(a))
	weapon.consume_shot()
	assert_size(fired, 1)
	assert_eq(fired[0], weapon.get_attack())


# --- Reloading ------------------------------------------------------------

func test_reloading_refills_from_the_reserve() -> void:
	for shot in 3:
		weapon.consume_shot()
		weapon.tick(1.0)
	assert_eq(weapon.get_magazine(), 2)

	assert_ok(weapon.reload())
	assert_true(weapon.is_reloading())
	weapon.tick(2.0)

	assert_eq(weapon.get_magazine(), 5)
	assert_eq(weapon.get_reserve(), 7)
	assert_false(weapon.is_reloading())


func test_a_weapon_cannot_fire_while_reloading() -> void:
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.reload()
	assert_err(weapon.can_fire(), &"weapon.reloading")


func test_a_full_magazine_refuses_a_reload() -> void:
	assert_err(weapon.reload(), &"weapon.magazine_full")


func test_an_empty_reserve_refuses_a_reload() -> void:
	var profile := CombatFixtures.rifle(20.0, 2)
	profile.ammo.reserve_capacity = 0
	weapon.set_profile(profile)
	weapon.consume_shot()
	weapon.tick(1.0)
	assert_err(weapon.reload(), &"weapon.no_reserve")


func test_reloading_twice_is_refused_rather_than_restarted() -> void:
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.reload()
	assert_err(weapon.reload(), &"weapon.already_reloading")


func test_a_cancelled_reload_loads_nothing() -> void:
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.reload()
	weapon.tick(1.0)
	weapon.cancel_reload()
	weapon.tick(5.0)
	assert_eq(weapon.get_magazine(), 4)
	assert_false(weapon.is_reloading())


func test_a_partial_reserve_loads_what_it_can() -> void:
	var profile := CombatFixtures.rifle(20.0, 5)
	profile.ammo.reserve_capacity = 2
	weapon.set_profile(profile)
	for shot in 4:
		weapon.consume_shot()
		weapon.tick(1.0)
	weapon.reload()
	weapon.tick(2.0)
	assert_eq(weapon.get_magazine(), 3)
	assert_eq(weapon.get_reserve(), 0)


func test_an_incremental_reload_keeps_what_it_loaded() -> void:
	# The shotgun. Cancelling after two shells keeps two shells, which is the
	# entire reason incremental reloading exists.
	var profile := CombatFixtures.rifle(20.0, 4)
	profile.ammo.incremental = true
	profile.ammo.rounds_per_step = 1
	profile.ammo.reload_time = 0.5
	weapon.set_profile(profile)
	for shot in 4:
		weapon.consume_shot()
		weapon.tick(1.0)
	assert_eq(weapon.get_magazine(), 0)

	weapon.reload()
	weapon.tick(0.5)
	weapon.tick(0.5)
	assert_eq(weapon.get_magazine(), 2)
	assert_true(weapon.is_reloading())

	weapon.cancel_reload()
	weapon.tick(5.0)
	assert_eq(weapon.get_magazine(), 2)


func test_an_incremental_reload_stops_when_full() -> void:
	var profile := CombatFixtures.rifle(20.0, 2)
	profile.ammo.incremental = true
	profile.ammo.reload_time = 0.5
	weapon.set_profile(profile)
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.consume_shot()
	weapon.tick(1.0)

	weapon.reload()
	weapon.tick(0.5)
	weapon.tick(0.5)
	assert_eq(weapon.get_magazine(), 2)
	assert_false(weapon.is_reloading())


func test_reloading_marks_the_semantic_state() -> void:
	var state := CombatFixtures.state_of(entity)
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.reload()
	assert_true(state.has_state(GameplayNames.STATE_RELOADING))
	weapon.tick(2.0)
	assert_false(state.has_state(GameplayNames.STATE_RELOADING))


func test_a_weapon_with_no_magazine_cannot_reload() -> void:
	weapon.set_profile(CombatFixtures.sword())
	assert_err(weapon.reload(), &"weapon.none")


# --- Ammunition from a bag ------------------------------------------------

func _with_inventory(rounds: int) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container()
	entity.add_child(inventory)
	CombatFixtures.assemble(entity)

	if rounds > 0:
		var bullets := ItemFixtures.stackable(&"item.bullet", 99)
		inventory.add(ItemInstance.create(bullets, rounds))

	var profile := CombatFixtures.rifle(20.0, 5)
	profile.ammo.ammo_item_id = &"item.bullet"
	weapon.set_profile(profile)
	return inventory


func test_the_reserve_can_be_the_bag() -> void:
	var inventory := _with_inventory(12)
	assert_eq(weapon.get_reserve(), 12)

	for shot in 3:
		weapon.consume_shot()
		weapon.tick(1.0)
	weapon.reload()
	weapon.tick(2.0)

	assert_eq(weapon.get_magazine(), 5)
	assert_eq(inventory.count(&"item.bullet"), 9)


func test_an_empty_bag_refuses_a_reload() -> void:
	_with_inventory(0)
	weapon.consume_shot()
	weapon.tick(1.0)
	assert_err(weapon.reload(), &"weapon.no_reserve")


# --- Aim drift ------------------------------------------------------------

func test_spread_opens_with_each_shot_and_closes_again() -> void:
	assert_almost_eq(weapon.get_spread(), 0.0)
	weapon.consume_shot()
	assert_almost_eq(weapon.get_spread(), 1.0)
	weapon.tick(1.0)
	# One tick both recovers spread and clears the cadence timer.
	assert_true(weapon.get_spread() < 1.0)


func test_spread_never_exceeds_its_cap() -> void:
	# An unlimited weapon held down: the cone widens shot after shot and stops
	# at the profile's maximum rather than growing without bound.
	var profile := CombatFixtures.rifle()
	profile.ammo = null
	weapon.set_profile(profile)

	var widest := 0.0
	for shot in 30:
		if weapon.can_fire().is_ok():
			weapon.consume_shot()
		weapon.tick(0.02)
		widest = maxf(widest, weapon.get_spread())
	assert_true(widest > 2.0, "the cone should open, but reached only %f" % widest)
	assert_true(widest <= 5.0001, "the cone opened past its cap to %f" % widest)


func test_recoil_climbs_and_settles() -> void:
	weapon.consume_shot()
	assert_true(weapon.get_recoil().x > 0.0)
	weapon.tick(5.0)
	assert_almost_eq(weapon.get_recoil().x, 0.0)


func test_a_weapon_with_no_recoil_profile_never_drifts() -> void:
	weapon.set_profile(CombatFixtures.sword())
	weapon.consume_shot()
	assert_almost_eq(weapon.get_spread(), 0.0)


# --- Equipment ------------------------------------------------------------

func test_the_weapon_comes_from_what_is_equipped() -> void:
	var armed := add_test_node(CombatFixtures.fighter("Knight")) as Node3D

	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.loadout_override = ItemFixtures.loadout()
	armed.add_child(equipment)
	CombatFixtures.assemble(armed)

	var blade := ItemFixtures.weapon(&"item.sword")
	blade.weapon = CombatFixtures.sword(35.0)
	assert_ok(equipment.equip(ItemInstance.create(blade, 1)))

	var component := CombatFixtures.weapon_of(armed)
	assert_eq(component.get_profile(), blade.weapon)
	assert_eq(component.get_weapon_id(), &"item.sword")


func test_unequipping_leaves_the_entity_unarmed() -> void:
	var armed := add_test_node(CombatFixtures.fighter("Knight")) as Node3D
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.loadout_override = ItemFixtures.loadout()
	armed.add_child(equipment)
	CombatFixtures.assemble(armed)

	var blade := ItemFixtures.weapon(&"item.sword")
	blade.weapon = CombatFixtures.sword()
	equipment.equip(ItemInstance.create(blade, 1))
	equipment.unequip(&"slot.main_hand")

	assert_false(CombatFixtures.weapon_of(armed).has_weapon())


func test_an_override_wins_over_what_is_equipped() -> void:
	# A turret's weapon is not something it is wearing.
	var mounted := CombatFixtures.rifle(99.0)
	weapon.profile_override = mounted
	CombatFixtures.assemble(entity)
	assert_eq(weapon.get_profile(), mounted)


# --- Persistence ----------------------------------------------------------

func test_ammunition_survives_a_save() -> void:
	for shot in 3:
		weapon.consume_shot()
		weapon.tick(1.0)
	var saved := weapon.capture_state()

	weapon.set_profile(CombatFixtures.rifle(20.0, 5))
	assert_eq(weapon.get_magazine(), 5)

	weapon.restore_state(saved)
	assert_eq(weapon.get_magazine(), 2)
	assert_eq(weapon.get_reserve(), 10)


func test_a_reload_in_progress_does_not_survive_a_save() -> void:
	weapon.consume_shot()
	weapon.tick(1.0)
	weapon.reload()
	weapon.restore_state(weapon.capture_state())
	assert_false(weapon.is_reloading())


func test_weapons_are_persistent() -> void:
	assert_true(weapon.is_persistent())
