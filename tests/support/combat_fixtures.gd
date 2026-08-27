class_name CombatFixtures
extends RefCounted
## Builders for the swords, rifles, targets and fighters the M6 suites need.
##
## Entities are assembled by hand rather than instantiated from a scene: what
## most of these tests prove is that combat works on a plain [Node3D] with two
## components on it, which is exactly what rule 33 asks for. Static builders
## rather than [code].tres[/code] files, because the addon ships no content of
## its own (rule 29).

# --- Deliveries -----------------------------------------------------------

static func melee(
	reach: float = 2.0, arc_degrees: float = 90.0, max_targets: int = 0
) -> MeleeDelivery:
	var delivery := MeleeDelivery.new()
	delivery.reach = reach
	delivery.arc_degrees = arc_degrees
	delivery.max_targets = max_targets
	return delivery


static func hitscan(
	max_range: float = 100.0, pellets: int = 1, inherent_spread: float = 0.0
) -> HitscanDelivery:
	var delivery := HitscanDelivery.new()
	delivery.max_range = max_range
	delivery.pellets = pellets
	delivery.inherent_spread = inherent_spread
	return delivery


static func projectile_delivery(count: int = 1) -> ProjectileDelivery:
	var delivery := ProjectileDelivery.new()
	delivery.projectile_scene = projectile_scene()
	delivery.count = count
	return delivery


static func projectile_scene() -> PackedScene:
	return load("res://addons/universal_gameplay/combat/projectile.tscn")


# --- Attacks --------------------------------------------------------------

static func attack(
	id: StringName = &"attack.swing",
	damage: float = 10.0,
	delivery: AttackDelivery = null
) -> AttackDefinition:
	var definition := AttackDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.damage = damage
	var tags: Array[StringName] = [GameplayNames.DAMAGE_PHYSICAL]
	definition.damage_tags = tags
	definition.delivery = delivery if delivery != null else melee()
	return definition


## An attack with a wind-up, a window and a follow-through, for testing the
## state machine rather than the geometry.
static func timed_attack(
	startup: float = 0.2, active: float = 0.1, recovery: float = 0.2
) -> AttackDefinition:
	var definition := attack(&"attack.heavy", 25.0, melee())
	definition.startup = startup
	definition.active = active
	definition.recovery = recovery
	return definition


# --- Weapons --------------------------------------------------------------

static func ammo(
	magazine: int = 5, reserve: int = 10, reload_time: float = 2.0
) -> AmmoProfile:
	var profile := AmmoProfile.new()
	profile.magazine_size = magazine
	profile.reserve_capacity = reserve
	profile.reload_time = reload_time
	profile.cost_per_shot = 1
	return profile


static func recoil(
	spread_per_shot: float = 1.0, spread_max: float = 5.0
) -> RecoilProfile:
	var profile := RecoilProfile.new()
	profile.spread_min = 0.0
	profile.spread_max = spread_max
	profile.spread_per_shot = spread_per_shot
	profile.spread_recovery_per_second = 2.0
	profile.recoil_pitch = 1.0
	profile.recoil_yaw = 0.0
	profile.recoil_max = 8.0
	profile.recoil_recovery_per_second = 4.0
	return profile


static func rifle(
	damage: float = 20.0,
	magazine: int = 5,
	mode: WeaponProfile.FireMode = WeaponProfile.FireMode.SINGLE
) -> WeaponProfile:
	var profile := WeaponProfile.new()
	profile.primary = attack(&"attack.shot", damage, hitscan())
	profile.fire_mode = mode
	profile.rate_per_second = 10.0
	profile.ammo = ammo(magazine)
	profile.recoil = recoil()
	return profile


static func sword(damage: float = 30.0) -> WeaponProfile:
	var profile := WeaponProfile.new()
	profile.primary = attack(&"attack.slash", damage, melee())
	profile.fire_mode = WeaponProfile.FireMode.SINGLE
	return profile


static func combat_profile(unarmed_damage: float = 5.0) -> CombatProfile:
	var profile := CombatProfile.new()
	profile.unarmed = attack(&"attack.punch", unarmed_damage, melee(1.5, 60.0))
	profile.aim_height = 0.0
	return profile


# --- Entities -------------------------------------------------------------

## Something that can be hit and knows it: health, a receiver and states.
static func dummy(
	entity_name: String = "Dummy",
	position: Vector3 = Vector3.ZERO,
	health_amount: float = 100.0
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name
	entity.position = position

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = health_amount
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)
	return entity


## Something that can attack. [param weapon_profile] null leaves it unarmed.
static func fighter(
	entity_name: String = "Fighter",
	position: Vector3 = Vector3.ZERO,
	weapon_profile: WeaponProfile = null,
	profile: CombatProfile = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name
	entity.position = position

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var weapon := WeaponComponent.new()
	weapon.name = "WeaponComponent"
	weapon.profile_override = weapon_profile
	weapon.auto_tick = false
	entity.add_child(weapon)

	var combat := CombatComponent.new()
	combat.name = "CombatComponent"
	combat.profile_override = profile if profile != null else combat_profile()
	combat.weapon = weapon
	combat.auto_tick = false
	entity.add_child(combat)
	return entity


## Adds a stats component carrying stamina, for testing attack costs.
static func with_stamina(entity: Node, amount: float = 100.0) -> StatsComponent:
	var stamina := StatDefinition.new()
	stamina.id = GameplayNames.STAT_STAMINA
	stamina.display_name = "Stamina"
	stamina.default_base = amount
	stamina.minimum = 0.0
	stamina.depletable = true

	var profile := StatsProfile.new()
	var stats_list: Array[StatDefinition] = [stamina]
	profile.stats = stats_list

	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = profile
	stats.auto_tick = false
	entity.add_child(stats)
	return stats


## Runs initialize over an assembled entity, the way a binder would.
static func assemble(entity: Node, definition: FrameworkDefinition = null) -> void:
	var context := EntityContext.create(entity, definition)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func combat_of(entity: Node) -> CombatComponent:
	return _find(entity, CombatComponent) as CombatComponent


static func weapon_of(entity: Node) -> WeaponComponent:
	return _find(entity, WeaponComponent) as WeaponComponent


static func health_of(entity: Node) -> HealthComponent:
	return _find(entity, HealthComponent) as HealthComponent


static func state_of(entity: Node) -> SemanticState:
	return _find(entity, SemanticState) as SemanticState


static func _find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
