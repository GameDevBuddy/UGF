extends FrameworkTestCase
## Covers the combat definitions and profiles: timing, reach, the damage
## context they produce, and the validation that catches content nobody could
## fight with.

# --- AttackDefinition -----------------------------------------------------

func test_an_attack_with_no_timing_is_instant() -> void:
	var attack := CombatFixtures.attack()
	assert_true(attack.is_instant())
	assert_almost_eq(attack.get_duration(), 0.0)


func test_timing_adds_up() -> void:
	var attack := CombatFixtures.timed_attack(0.2, 0.1, 0.3)
	assert_false(attack.is_instant())
	assert_almost_eq(attack.get_duration(), 0.6)


func test_an_attack_reports_the_reach_of_its_delivery() -> void:
	assert_almost_eq(CombatFixtures.attack(&"a", 1.0, CombatFixtures.melee(3.0)).get_reach(), 3.0)
	assert_almost_eq(
		CombatFixtures.attack(&"b", 1.0, CombatFixtures.hitscan(50.0)).get_reach(), 50.0
	)


func test_an_attack_with_no_delivery_reaches_nothing() -> void:
	var attack := CombatFixtures.attack()
	attack.delivery = null
	assert_almost_eq(attack.get_reach(), 0.0)


func test_combo_tags_are_carried_and_matched() -> void:
	var attack := CombatFixtures.attack()
	var tags: Array[StringName] = [&"combo.light", &"combo.opener"]
	attack.combo_tags = tags
	assert_true(attack.has_combo_tag(&"combo.light"))
	assert_false(attack.has_combo_tag(&"combo.finisher"))


func test_a_cost_needs_a_stat_to_spend() -> void:
	var attack := CombatFixtures.attack()
	assert_false(attack.has_cost())
	attack.cost = 20.0
	assert_false(attack.has_cost(), "a cost with no stat is not a cost")
	attack.cost_stat = GameplayNames.STAT_STAMINA
	assert_true(attack.has_cost())


func test_an_attack_with_no_delivery_is_flagged() -> void:
	var attack := CombatFixtures.attack()
	attack.delivery = null
	var result := attack.validate()
	assert_true(result.is_valid())
	assert_true(result.has_warnings())


func test_untagged_damage_is_flagged() -> void:
	var attack := CombatFixtures.attack()
	var none: Array[StringName] = []
	attack.damage_tags = none
	assert_true(attack.validate().has_warnings())


func test_a_cost_with_no_stat_is_flagged() -> void:
	var attack := CombatFixtures.attack()
	attack.cost = 10.0
	assert_true(attack.validate().has_warnings())


func test_a_broken_delivery_surfaces_through_the_attack() -> void:
	assert_false(CombatFixtures.attack(&"a", 1.0, CombatFixtures.melee(0.0)).validate().is_valid())


func test_a_complete_attack_validates_clean() -> void:
	var result := CombatFixtures.attack().validate()
	assert_true(result.is_valid())
	assert_false(result.has_warnings())


# --- AttackContext --------------------------------------------------------

func test_a_context_turns_a_hit_into_damage() -> void:
	var attacker := add_test_node(Node3D.new())
	var attack := CombatFixtures.attack(&"attack.shot", 40.0)
	var context := AttackContext.create(attacker, attack)
	context.weapon_id = &"item.rifle"

	var hit := CombatHit.create(add_test_node(Node.new()), Vector3.UP, Vector3.FORWARD, 12.0)
	var damage := context.make_damage(hit)

	assert_almost_eq(damage.amount, 40.0)
	assert_eq(damage.instigator, attacker)
	assert_eq(damage.weapon_id, &"item.rifle")
	assert_has(damage.tags, GameplayNames.DAMAGE_PHYSICAL)
	assert_eq(damage.hit_position, Vector3.UP)
	assert_eq(damage.hit_normal, Vector3.FORWARD)


func test_a_scaled_hit_scales_the_damage() -> void:
	var context := AttackContext.create(null, CombatFixtures.attack(&"a", 40.0))
	var hit := CombatHit.create(null)
	hit.damage_scale = 0.25
	assert_almost_eq(context.make_damage(hit).amount, 10.0)


func test_a_context_with_no_attack_deals_nothing() -> void:
	var context := AttackContext.new()
	assert_almost_eq(context.make_damage(CombatHit.create(null)).amount, 0.0)


func test_a_context_excludes_its_own_attacker() -> void:
	var attacker := add_test_node(Node3D.new())
	assert_has(AttackContext.create(attacker, null).exclude, attacker)


func test_a_context_makes_its_own_generator_when_it_needs_one() -> void:
	var context := AttackContext.new()
	assert_not_null(context.get_rng())
	assert_eq(context.get_rng(), context.rng)


# --- CombatHit ------------------------------------------------------------

func test_a_hit_on_something_damageable_finds_its_receiver() -> void:
	var dummy := add_test_node(CombatFixtures.dummy())
	CombatFixtures.assemble(dummy)
	var hit := CombatHit.create(dummy)
	assert_true(hit.is_damageable())
	assert_not_null(hit.get_receiver())


func test_a_hit_on_scenery_has_no_receiver() -> void:
	var hit := CombatHit.create(add_test_node(Node.new()))
	assert_false(hit.is_damageable())
	assert_null(hit.get_receiver())


func test_a_hit_on_nothing_is_answered_rather_than_crashing() -> void:
	assert_null(CombatHit.create(null).get_receiver())


# --- WeaponProfile --------------------------------------------------------

func test_a_weapon_reports_its_attacks() -> void:
	var profile := CombatFixtures.rifle()
	assert_eq(profile.get_attack(), profile.primary)
	assert_null(profile.get_attack(true))
	profile.secondary = CombatFixtures.attack(&"attack.bash", 5.0)
	assert_eq(profile.get_attack(true), profile.secondary)


func test_the_interval_comes_from_the_rate_when_there_is_one() -> void:
	var profile := CombatFixtures.rifle()
	profile.rate_per_second = 4.0
	assert_almost_eq(profile.get_interval(), 0.25)


func test_the_interval_falls_back_to_the_attacks_own_timing() -> void:
	var profile := CombatFixtures.sword()
	profile.primary = CombatFixtures.timed_attack(0.2, 0.1, 0.2)
	assert_almost_eq(profile.get_interval(), 0.5)


func test_a_weapon_with_no_primary_attack_is_a_content_error() -> void:
	assert_false(WeaponProfile.new().validate().is_valid())


func test_an_automatic_weapon_with_no_rate_is_flagged() -> void:
	var profile := CombatFixtures.rifle()
	profile.fire_mode = WeaponProfile.FireMode.AUTOMATIC
	profile.rate_per_second = 0.0
	assert_true(profile.validate().has_warnings())


func test_a_complete_weapon_validates_clean() -> void:
	var result := CombatFixtures.rifle().validate()
	assert_true(result.is_valid())
	assert_false(result.has_warnings())


# --- AmmoProfile ----------------------------------------------------------

func test_a_magazineless_weapon_is_infinite() -> void:
	var ammo := AmmoProfile.new()
	ammo.magazine_size = 0
	assert_true(ammo.is_infinite())


func test_a_negative_reserve_is_unlimited() -> void:
	var ammo := CombatFixtures.ammo(5, -1)
	assert_true(ammo.has_unlimited_reserve())


func test_naming_an_item_makes_the_bag_the_reserve() -> void:
	var ammo := CombatFixtures.ammo()
	assert_false(ammo.draws_from_inventory())
	ammo.ammo_item_id = &"item.bullet"
	assert_true(ammo.draws_from_inventory())


func test_a_shot_costing_more_than_the_magazine_is_a_content_error() -> void:
	var ammo := CombatFixtures.ammo(5, 10)
	ammo.cost_per_shot = 6
	assert_false(ammo.validate().is_valid())


func test_a_reload_time_on_a_magazineless_weapon_is_flagged() -> void:
	var ammo := AmmoProfile.new()
	ammo.magazine_size = 0
	ammo.reload_time = 2.0
	assert_true(ammo.validate().has_warnings())


# --- RecoilProfile --------------------------------------------------------

func test_a_cone_that_closes_as_it_fires_is_a_content_error() -> void:
	var recoil := CombatFixtures.recoil()
	recoil.spread_min = 5.0
	recoil.spread_max = 1.0
	assert_false(recoil.validate().is_valid())


func test_spread_that_never_recovers_is_flagged() -> void:
	var recoil := CombatFixtures.recoil()
	recoil.spread_recovery_per_second = 0.0
	assert_true(recoil.validate().has_warnings())


func test_recoil_that_never_settles_is_flagged() -> void:
	var recoil := CombatFixtures.recoil()
	recoil.recoil_recovery_per_second = 0.0
	assert_true(recoil.validate().has_warnings())


# --- CombatProfile --------------------------------------------------------

func test_a_broken_unarmed_attack_surfaces_through_the_profile() -> void:
	var profile := CombatFixtures.combat_profile()
	profile.unarmed.delivery = CombatFixtures.melee(0.0)
	assert_false(profile.validate().is_valid())


func test_a_profile_with_no_unarmed_attack_is_valid() -> void:
	# A civilian that never throws a punch is content, not a mistake.
	assert_true(CombatProfile.new().validate().is_valid())


# --- Definitions carry combat ---------------------------------------------

func test_an_item_definition_carries_a_weapon_profile() -> void:
	var sword := ItemFixtures.weapon(&"item.sword")
	sword.weapon = CombatFixtures.sword()
	assert_true(sword.validate().is_valid())
	assert_eq(sword.weapon.primary.damage, 30.0)


func test_a_broken_weapon_surfaces_through_the_item() -> void:
	var sword := ItemFixtures.weapon(&"item.sword")
	sword.weapon = WeaponProfile.new()
	assert_false(sword.validate().is_valid())


func test_a_character_definition_carries_a_combat_profile() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.brawler"
	definition.display_name = "Brawler"
	definition.movement = MovementProfile.new()
	definition.combat = CombatFixtures.combat_profile()
	definition.scene = PackedScene.new()
	assert_true(definition.validate().is_valid())


func test_a_broken_combat_profile_surfaces_through_the_character() -> void:
	var definition := CharacterDefinition.new()
	definition.id = &"character.brawler"
	definition.display_name = "Brawler"
	definition.movement = MovementProfile.new()
	definition.scene = PackedScene.new()
	var profile := CombatFixtures.combat_profile()
	profile.unarmed.delivery = CombatFixtures.melee(0.0)
	definition.combat = profile
	assert_false(definition.validate().is_valid())
